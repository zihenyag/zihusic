import AVFoundation
import CryptoKit

struct AirPlayPreparedAsset: @unchecked Sendable {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: Double
}

/// AirPlay's buffered PCM conversion failed on the tested macOS receiver. Feed
/// both renderers the same AAC packets instead. Originals are never rewritten.
enum AirPlayAudioAsset {
    static func prepare(_ source: URL, cacheDirectory: URL? = nil) async throws -> AirPlayPreparedAsset {
        let directory = cacheDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("com.local.zihusic-airplay", isDirectory: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let identity = source.standardizedFileURL.path + "|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date.distantPast)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(key + ".m4a")
        if !FileManager.default.fileExists(atPath: destination.path) {
            let temporary = directory.appendingPathComponent(UUID().uuidString + ".partial.m4a")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let asset = AVURLAsset(url: source)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw AudioError("无法准备 AirPlay 音频")
            }
            if #available(macOS 15, *) {
                try await exporter.export(to: temporary, as: .m4a)
            } else {
                try await exportLegacy(exporter, to: temporary)
            }
            try Task.checkCancellation()
            // Another preparation may have completed the same song meanwhile.
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        }
        try Task.checkCancellation()
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        pruneCache(directory, keeping: destination)
        let asset = AVURLAsset(url: destination)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioError("音频文件没有可播放的音轨")
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw AudioError("音频时长无效") }
        return AirPlayPreparedAsset(asset: asset, track: track, duration: duration)
    }

    @available(macOS, introduced: 10.7, deprecated: 15)
    private static func exportLegacy(_ exporter: AVAssetExportSession, to url: URL) async throws {
        exporter.outputURL = url
        exporter.outputFileType = .m4a
        let transfer = LegacyExportTransfer(session: exporter)
        await withTaskCancellationHandler {
            await exporter.export()
        } onCancel: {
            transfer.session.cancelExport()
        }
        guard exporter.status == .completed else {
            throw exporter.error ?? AudioError("AirPlay 音频准备失败")
        }
    }

    private static func pruneCache(_ directory: URL, keeping current: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let entries = files.filter { $0.pathExtension == "m4a" && !$0.lastPathComponent.contains(".partial.") }
            .compactMap { url -> (URL, Date, Int)? in
                guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
                return (url, info.contentModificationDate ?? .distantPast, info.fileSize ?? 0)
            }.sorted { $0.1 > $1.1 }
        var bytes = 0
        for (index, entry) in entries.enumerated() {
            bytes += entry.2
            if entry.0 != current, index >= 2, (index >= 12 || bytes > 256 * 1_024 * 1_024) {
                try? FileManager.default.removeItem(at: entry.0)
            }
        }
    }

    private struct LegacyExportTransfer: @unchecked Sendable {
        let session: AVAssetExportSession
    }

    struct AudioError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
