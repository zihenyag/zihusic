import AppKit
import Foundation
import UniformTypeIdentifiers

private let lastImportFolderDefaultsKey = "lastImportFolder"
private let selectedTrackIDDefaultsKey = "selectedTrackID"

struct LibraryImportProgress: Equatable, Sendable {
    let id: UUID
    var completed: Int
    var total: Int
    var phase: String
    var detail: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

@MainActor
final class MusicLibraryStore: ObservableObject {
    @Published var tracks: [MusicTrack] = [] {
        didSet { rebuildVisibleTracks() }
    }
    @Published var selectedTrackID: MusicTrack.ID? {
        didSet {
            guard selectedTrackID != oldValue else { return }
            persistSelectedTrackID()
        }
    }
    @Published var searchText = "" {
        didSet { rebuildVisibleTracks() }
    }
    @Published private(set) var visibleTracks: [MusicTrack] = []
    @Published private(set) var visibleTracksRevision = 0
    @Published private(set) var importProgress: LibraryImportProgress?
    @Published var isImporting = false
    @Published var statusMessage = ""
    @Published var lastImportFolder = UserDefaults.standard.string(forKey: lastImportFolderDefaultsKey) ?? ""

    private let metadataService = MetadataService()
    private let metadataWriter = MetadataWriterService()
    private let lyricsService = LyricsService()

    init() {
        load()
        Task {
            await refreshCachedMetadataFromFiles()
        }
    }

    var filteredTracks: [MusicTrack] {
        visibleTracks
    }

    var selectedTrack: MusicTrack? {
        guard let selectedTrackID else { return tracks.first }
        return tracks.first { $0.id == selectedTrackID }
    }

    func load() {
        do {
            try AppDirectories.ensureCreated()
            guard FileManager.default.fileExists(atPath: AppDirectories.libraryFile.path) else { return }
            let data = try Data(contentsOf: AppDirectories.libraryFile)
            let loadedTracks = try JSONDecoder.iso8601Decoder.decode([MusicTrack].self, from: data)
            tracks = loadedTracks
            restoreSelectedTrackID(from: loadedTracks)
        } catch {
            statusMessage = "读取资料库失败：\(error.localizedDescription)"
        }
    }

    private func refreshCachedMetadataFromFiles() async {
        let cachedTracks = tracks
        guard !cachedTracks.isEmpty else { return }

        let requests = cachedTracks.compactMap { track -> TrackScanRequest? in
            guard FileManager.default.fileExists(atPath: track.filePath),
                  shouldReloadMetadata(for: track, fileURL: track.fileURL) else {
                return nil
            }
            return TrackScanRequest(url: track.fileURL, existing: track)
        }
        guard !requests.isEmpty else { return }

        let refreshed = await loadTracksConcurrently(requests)

        guard !refreshed.isEmpty else { return }

        var changed = false
        var byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for updated in refreshed {
            guard let existing = byID[updated.id] else { continue }
            if existing.artist != updated.artist
                || existing.embeddedLyrics != updated.embeddedLyrics
                || existing.title != updated.title
                || existing.album != updated.album {
                byID[updated.id] = updated
                changed = true
            }
        }

        guard changed else { return }
        tracks = sortedTracks(from: Array(byID.values))
        save()
    }

    func save() {
        do {
            try AppDirectories.ensureCreated()
            let data = try JSONEncoder.sortedPrettyPrinted.encode(tracks)
            try data.write(to: AppDirectories.libraryFile, options: .atomic)
        } catch {
            statusMessage = "保存资料库失败：\(error.localizedDescription)"
        }
    }

    var hasImportFolder: Bool {
        !lastImportFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func chooseAndImportFolder() async {
        let panel = NSOpenPanel()
        panel.title = "选择音乐文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if hasImportFolder {
            panel.directoryURL = URL(fileURLWithPath: lastImportFolder, isDirectory: true)
        }

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        await importFolder(folder)
    }

    func rescanLastImportFolder() async {
        guard hasImportFolder else {
            statusMessage = "请先选择音乐文件夹"
            return
        }

        let folder = URL(fileURLWithPath: lastImportFolder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            statusMessage = "找不到上次选择的文件夹：\(folder.path)"
            return
        }

        await importFolder(folder)
    }

    func importFolder(_ folder: URL) async {
        guard !isImporting else {
            statusMessage = "扫描仍在进行"
            return
        }

        let scanID = UUID()
        isImporting = true
        updateImportProgress(id: scanID, completed: 0, total: 0, phase: "正在查找音乐文件", detail: folder.path)
        lastImportFolder = folder.path
        UserDefaults.standard.set(folder.path, forKey: lastImportFolderDefaultsKey)

        let existing = Dictionary(uniqueKeysWithValues: tracks.map { (standardizedPath($0.fileURL), $0) })
        let urls = audioFiles(in: folder)
        let scannedPaths = Set(urls.map { standardizedPath($0) })
        updateImportProgress(id: scanID, completed: 0, total: urls.count, phase: "正在扫描音乐", detail: "找到 \(urls.count) 首音乐")

        var reused: [MusicTrack] = []
        var requests: [TrackScanRequest] = []
        reused.reserveCapacity(urls.count)
        requests.reserveCapacity(urls.count)

        for url in urls {
            let existingTrack = existing[standardizedPath(url)]
            if var cached = reusableTrack(existingTrack, for: url) {
                cached.lyricsFilePath = findLyricsFile(for: cached)?.path
                reused.append(cached)
            } else {
                requests.append(TrackScanRequest(url: url, existing: existingTrack))
            }
        }

        updateImportProgress(
            id: scanID,
            completed: reused.count,
            total: urls.count,
            phase: requests.isEmpty ? "正在整理资料库" : "正在读取变更",
            detail: requests.isEmpty ? "全部文件未变化" : "需要读取 \(requests.count) 首"
        )

        let loaded = await loadTracksConcurrently(
            requests,
            progressID: scanID,
            initialCompleted: reused.count,
            total: urls.count
        )
        let imported = reused + loaded

        let removedCount = synchronize(imported, scannedPaths: scannedPaths, folder: folder)
        save()
        isImporting = false
        let finalStatus = removedCount > 0 ? "已导入 \(imported.count) 首音乐，移除 \(removedCount) 条失效记录" : "已导入 \(imported.count) 首音乐"
        statusMessage = finalStatus
        updateImportProgress(id: scanID, completed: urls.count, total: urls.count, phase: "扫描完成", detail: finalStatus)
        statusMessage = finalStatus
        if selectedTrackID == nil {
            selectedTrackID = tracks.first?.id
        }

        try? await Task.sleep(nanoseconds: 900_000_000)
        if importProgress?.id == scanID {
            importProgress = nil
        }
    }

    func importFile(_ file: URL, source: TrackSource = .downloaded) async {
        guard let track = await Task.detached(priority: .userInitiated, operation: {
            await MetadataService().loadTrack(from: file, existing: nil, source: source)
        }).value else { return }

        merge([track])
        selectedTrackID = track.id
        save()
    }

    func updateTrack(_ track: MusicTrack) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        var updated = track
        updated.updatedAt = Date()
        tracks[index] = updated
        save()
    }

    @discardableResult
    func chooseArtwork(for track: MusicTrack) -> MusicTrack? {
        let panel = NSOpenPanel()
        panel.title = "选择封面"
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        do {
            try AppDirectories.ensureCreated()
            let ext = source.pathExtension.isEmpty ? "image" : source.pathExtension
            let fileName = "\(track.id.uuidString)-manual-cover.\(ext)"
            let destination = AppDirectories.artworkDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            var updated = track
            updated.artworkFileName = fileName
            updateTrack(updated)
            statusMessage = "封面已更新"
            return updated
        } catch {
            statusMessage = "更新封面失败：\(error.localizedDescription)"
            return nil
        }
    }

    func writeTags(for track: MusicTrack) async {
        do {
            try metadataWriter.write(track: track, artworkURL: artworkURL(for: track))
            statusMessage = "标签已写入音频文件"
            if let refreshed = await Task.detached(priority: .userInitiated, operation: {
                await MetadataService().loadTrack(from: track.fileURL, existing: track, source: track.source)
            }).value {
                updateTrack(refreshed)
            } else {
                updateTrack(track)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func playSelected(using player: AudioPlayerService) {
        guard let track = selectedTrack else { return }
        player.play(track)
    }

    func playNext(using player: AudioPlayerService) {
        guard !tracks.isEmpty else { return }
        let currentID = player.currentTrack?.id ?? selectedTrackID
        let currentIndex = tracks.firstIndex { $0.id == currentID } ?? -1
        let next = tracks[(currentIndex + 1) % tracks.count]
        selectedTrackID = next.id
        player.play(next)
    }

    func playPrevious(using player: AudioPlayerService) {
        guard !tracks.isEmpty else { return }
        let currentID = player.currentTrack?.id ?? selectedTrackID
        let currentIndex = tracks.firstIndex { $0.id == currentID } ?? 0
        let previous = tracks[(currentIndex - 1 + tracks.count) % tracks.count]
        selectedTrackID = previous.id
        player.play(previous)
    }

    func artworkURL(for track: MusicTrack) -> URL? {
        guard let name = track.artworkFileName, !name.isEmpty else { return nil }
        if name.hasPrefix("/") {
            return URL(fileURLWithPath: name)
        }
        return AppDirectories.artworkDirectory.appendingPathComponent(name)
    }

    func lyrics(for track: MusicTrack) -> [LyricsLine] {
        lyricsService.lyrics(for: track)
    }

    private func merge(_ imported: [MusicTrack]) {
        var byPath = Dictionary(uniqueKeysWithValues: tracks.map { ($0.filePath, $0) })
        for track in imported {
            byPath[track.filePath] = track
        }
        tracks = sortedTracks(from: Array(byPath.values))
    }

    private func restoreSelectedTrackID(from loadedTracks: [MusicTrack]) {
        let savedID = UserDefaults.standard
            .string(forKey: selectedTrackIDDefaultsKey)
            .flatMap(UUID.init(uuidString:))

        if let savedID, loadedTracks.contains(where: { $0.id == savedID }) {
            selectedTrackID = savedID
        } else {
            selectedTrackID = nil
        }
    }

    private func persistSelectedTrackID() {
        if let selectedTrackID {
            UserDefaults.standard.set(selectedTrackID.uuidString, forKey: selectedTrackIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedTrackIDDefaultsKey)
        }
    }

    @discardableResult
    private func synchronize(_ imported: [MusicTrack], scannedPaths: Set<String>, folder: URL) -> Int {
        let folderPath = standardizedPath(folder)
        var byPath = Dictionary(uniqueKeysWithValues: tracks.map { ($0.filePath, $0) })
        var removedCount = 0

        for (path, _) in byPath {
            let normalizedPath = standardizedPath(URL(fileURLWithPath: path))
            guard isPath(normalizedPath, inside: folderPath) else { continue }

            if !scannedPaths.contains(normalizedPath) || !FileManager.default.fileExists(atPath: normalizedPath) {
                byPath.removeValue(forKey: path)
                removedCount += 1
            }
        }

        for track in imported {
            byPath[track.filePath] = track
        }

        tracks = sortedTracks(from: Array(byPath.values))
        if let selectedTrackID, !tracks.contains(where: { $0.id == selectedTrackID }) {
            self.selectedTrackID = tracks.first?.id
        }
        return removedCount
    }

    private func sortedTracks(from source: [MusicTrack]) -> [MusicTrack] {
        source.sorted {
            if $0.displayArtist == $1.displayArtist {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending
        }
    }

    private func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func isPath(_ path: String, inside folderPath: String) -> Bool {
        path == folderPath || path.hasPrefix(folderPath + "/")
    }

    private func audioFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let ext = url.pathExtension.lowercased()
            guard MetadataService.supportedExtensions.contains(ext) else { return nil }
            return url
        }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func rebuildVisibleTracks() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? tracks : tracks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.displayArtist.localizedCaseInsensitiveContains(query)
                || $0.displayAlbum.localizedCaseInsensitiveContains(query)
        }

        visibleTracks = filtered.sorted { left, right in
            let leftTitle = Self.sortKey(left.displayTitle)
            let rightTitle = Self.sortKey(right.displayTitle)
            if leftTitle == rightTitle {
                return Self.sortKey(left.displayArtist) < Self.sortKey(right.displayArtist)
            }
            return leftTitle < rightTitle
        }
        visibleTracksRevision &+= 1
    }

    private func loadTracksConcurrently(
        _ requests: [TrackScanRequest],
        progressID: UUID? = nil,
        initialCompleted: Int = 0,
        total: Int = 0
    ) async -> [MusicTrack] {
        guard !requests.isEmpty else { return [] }

        var loaded: [MusicTrack] = []
        loaded.reserveCapacity(requests.count)
        var completed = initialCompleted

        for batchStart in stride(from: 0, to: requests.count, by: Self.metadataScanConcurrency) {
            let batchEnd = min(batchStart + Self.metadataScanConcurrency, requests.count)
            let batch = Array(requests[batchStart..<batchEnd])

            await withTaskGroup(of: MusicTrack?.self) { group in
                for request in batch {
                    group.addTask {
                        await MetadataService().loadTrack(from: request.url, existing: request.existing, source: .local)
                    }
                }

                for await track in group {
                    if let track {
                        loaded.append(track)
                    }
                    completed += 1
                    if let progressID {
                        updateImportProgress(
                            id: progressID,
                            completed: completed,
                            total: total,
                            phase: "正在读取变更",
                            detail: "\(completed)/\(total)"
                        )
                    }
                }
            }
        }

        return loaded
    }

    private func reusableTrack(_ track: MusicTrack?, for url: URL) -> MusicTrack? {
        guard var track,
              let modifiedAt = Self.fileModifiedAt(for: url),
              Self.sameModificationDate(track.fileModifiedAt, modifiedAt) else {
            return nil
        }

        track.fileModifiedAt = modifiedAt
        return track
    }

    private func shouldReloadMetadata(for track: MusicTrack, fileURL: URL) -> Bool {
        guard let modifiedAt = Self.fileModifiedAt(for: fileURL) else { return true }
        return !Self.sameModificationDate(track.fileModifiedAt, modifiedAt)
    }

    private func updateImportProgress(id: UUID, completed: Int, total: Int, phase: String, detail: String) {
        importProgress = LibraryImportProgress(
            id: id,
            completed: completed,
            total: total,
            phase: phase,
            detail: detail
        )
        statusMessage = total > 0 ? "\(phase)：\(completed)/\(total)" : phase
    }

    private func findLyricsFile(for track: MusicTrack) -> URL? {
        let url = track.fileURL
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let title = track.displayTitle
        let artist = track.displayArtist
        let names = [
            "\(base).ass",
            "\(base).ASS",
            "\(title).ass",
            "\(title).ASS",
            artist.isEmpty ? nil : "\(artist) - \(title).ass",
            artist.isEmpty ? nil : "\(artist) - \(title).ASS",
            "\(base).lrc",
            "\(base).LRC",
            "\(title).lrc",
            "\(title).LRC",
            artist.isEmpty ? nil : "\(artist) - \(title).lrc"
        ].compactMap { $0 }

        return names
            .map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let metadataScanConcurrency = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))

    private static func fileModifiedAt(for url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    private static func sameModificationDate(_ left: Date?, _ right: Date?) -> Bool {
        guard let left, let right else { return false }
        return abs(left.timeIntervalSince(right)) < 1
    }

    private static func sortKey(_ value: String) -> String {
        let mutable = NSMutableString(string: value) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private struct TrackScanRequest: Sendable {
        var url: URL
        var existing: MusicTrack?
    }
}

private extension JSONEncoder {
    static var sortedPrettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
