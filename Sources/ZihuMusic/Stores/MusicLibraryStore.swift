import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MusicLibraryStore: ObservableObject {
    @Published var tracks: [MusicTrack] = []
    @Published var selectedTrackID: MusicTrack.ID?
    @Published var searchText = ""
    @Published var isImporting = false
    @Published var statusMessage = ""
    @Published var lastImportFolder = AppDirectories.defaultMusicFolder.path

    private let metadataService = MetadataService()
    private let metadataWriter = MetadataWriterService()
    private let lyricsService = LyricsService()

    init() {
        load()
    }

    var filteredTracks: [MusicTrack] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }
        return tracks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.displayArtist.localizedCaseInsensitiveContains(query)
                || $0.displayAlbum.localizedCaseInsensitiveContains(query)
        }
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
            tracks = try JSONDecoder.iso8601Decoder.decode([MusicTrack].self, from: data)
            selectedTrackID = tracks.first?.id
        } catch {
            statusMessage = "读取资料库失败：\(error.localizedDescription)"
        }
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

    func importDefaultFolder() async {
        await importFolder(AppDirectories.defaultMusicFolder)
    }

    func chooseAndImportFolder() async {
        let panel = NSOpenPanel()
        panel.title = "选择音乐文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: lastImportFolder, isDirectory: true)

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        await importFolder(folder)
    }

    func importFolder(_ folder: URL) async {
        isImporting = true
        statusMessage = "正在扫描 \(folder.path)"
        lastImportFolder = folder.path

        let existing = Dictionary(uniqueKeysWithValues: tracks.map { ($0.filePath, $0) })
        let urls = audioFiles(in: folder)
        let scannedPaths = Set(urls.map { standardizedPath($0) })

        let imported = await Task.detached(priority: .userInitiated) {
            let service = MetadataService()
            return urls.compactMap { service.loadTrack(from: $0, existing: existing[$0.path], source: .local) }
        }.value

        let removedCount = synchronize(imported, scannedPaths: scannedPaths, folder: folder)
        save()
        isImporting = false
        statusMessage = removedCount > 0 ? "已导入 \(imported.count) 首音乐，移除 \(removedCount) 条失效记录" : "已导入 \(imported.count) 首音乐"
        if selectedTrackID == nil {
            selectedTrackID = tracks.first?.id
        }
    }

    func importFile(_ file: URL, source: TrackSource = .downloaded) async {
        guard let track = await Task.detached(priority: .userInitiated, operation: {
            MetadataService().loadTrack(from: file, existing: nil, source: source)
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

    func chooseArtwork(for track: MusicTrack) {
        let panel = NSOpenPanel()
        panel.title = "选择封面"
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let source = panel.url else { return }
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
        } catch {
            statusMessage = "更新封面失败：\(error.localizedDescription)"
        }
    }

    func writeTags(for track: MusicTrack) async {
        do {
            try metadataWriter.write(track: track, artworkURL: artworkURL(for: track))
            statusMessage = "标签已写入音频文件"
            await importFile(track.fileURL, source: track.source)
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
