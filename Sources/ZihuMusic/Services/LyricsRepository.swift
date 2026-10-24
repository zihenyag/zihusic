import CryptoKit
import Foundation

/// Local cache reads and source validation never run on the UI actor. A cached
/// timeline can be displayed immediately while a changed sidecar is refreshed.
@MainActor
final class LyricsRepository {
    struct Source: Hashable, Codable, Sendable {
        let path: String?
        let embedded: String?

        init(_ track: MusicTrack) {
            path = track.lyricsFilePath
            embedded = track.embeddedLyrics
        }

        var cacheName: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = (try? encoder.encode(self)) ?? Data()
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".json"
        }
    }

    private struct Record: Codable, Sendable {
        let version: Int
        let source: Source
        let modified: Date?
        let size: Int?
        let timeline: LyricsTimeline
    }

    static let shared = LyricsRepository()
    private let directory: URL
    private var memory: [Source: LyricsTimeline] = [:]
    private var pending: [Source: Task<LyricsTimeline, Never>] = [:]

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.local.zihusic/Lyrics", isDirectory: true)) {
        self.directory = directory
    }

    func cached(for source: Source) -> LyricsTimeline? { memory[source] }

    func preview(for track: MusicTrack) async -> LyricsTimeline? {
        let source = Source(track)
        if let cached = memory[source] { return cached }
        let directory = directory
        let preview = await Task.detached(priority: .userInitiated) {
            Self.cachedRecord(source: source, directory: directory)?.timeline
        }.value
        if let preview { memory[source] = preview }
        return preview
    }

    func timeline(for track: MusicTrack, priority: TaskPriority = .userInitiated) async -> LyricsTimeline {
        let source = Source(track)
        if let task = pending[source] { return await task.value }
        let directory = directory
        let task = Task.detached(priority: priority) {
            Self.read(track: track, source: source, directory: directory)
        }
        pending[source] = task
        let result = await task.value
        pending[source] = nil
        memory[source] = result
        return result
    }

    func prefetch(_ tracks: [MusicTrack]) async {
        for track in tracks {
            guard !Task.isCancelled else { return }
            _ = await timeline(for: track, priority: .utility)
        }
    }

    private nonisolated static func read(track: MusicTrack, source: Source, directory: URL) -> LyricsTimeline {
        let url = directory.appendingPathComponent(source.cacheName)
        let cached = cachedRecord(source: source, directory: directory)
        let attributes = source.path.flatMap { try? FileManager.default.attributesOfItem(atPath: $0) }
        let modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.intValue
        if let cached, cached.version == 1, cached.source == source,
           (cached.modified == modified && cached.size == size || source.path != nil && attributes == nil) {
            return cached.timeline
        }
        let timeline = LyricsTimeline(LyricsService().lyrics(for: track))
        let record = Record(version: 1, source: source, modified: modified, size: size, timeline: timeline)
        if let data = try? JSONEncoder().encode(record) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return timeline
    }

    private nonisolated static func cachedRecord(source: Source, directory: URL) -> Record? {
        let url = directory.appendingPathComponent(source.cacheName)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1, record.source == source else { return nil }
        return record
    }
}
