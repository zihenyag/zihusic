import Foundation

enum MetadataWriterError: LocalizedError {
    case unsupportedFormat(String)
    case missingOriginal(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "暂不支持写回 \(format.uppercased()) 标签；已保存到应用资料库。"
        case .missingOriginal(let url):
            return "找不到原始音乐文件：\(url.path)"
        }
    }
}

struct MetadataWriterService {
    func write(track: MusicTrack, artworkURL: URL?) throws {
        let url = track.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataWriterError.missingOriginal(url)
        }

        switch url.pathExtension.lowercased() {
        case "flac":
            try writeFLAC(track: track, artworkURL: artworkURL)
        case "mp3", "m4a", "aac":
            try writeWithFFmpeg(track: track, artworkURL: artworkURL)
        default:
            throw MetadataWriterError.unsupportedFormat(url.pathExtension)
        }
    }

    private func writeFLAC(track: MusicTrack, artworkURL: URL?) throws {
        guard let metaflac = ProcessRunner.findExecutable(named: "metaflac") else {
            throw ProcessRunnerError.executableMissing("metaflac")
        }

        var arguments = [
            "--preserve-modtime",
            "--remove-tag=TITLE",
            "--remove-tag=ARTIST",
            "--remove-tag=ALBUM",
            "--set-tag=TITLE=\(track.title)",
            "--set-tag=ARTIST=\(track.artist)",
            "--set-tag=ALBUM=\(track.album)"
        ]

        if let lyrics = track.embeddedLyrics, !lyrics.isEmpty {
            arguments.append("--remove-tag=UNSYNCEDLYRICS")
            arguments.append("--set-tag=UNSYNCEDLYRICS=\(lyrics)")
        }

        arguments.append(track.filePath)
        try ProcessRunner.run(metaflac, arguments: arguments)

        if let artworkURL {
            _ = try? ProcessRunner.run(metaflac, arguments: ["--remove", "--block-type=PICTURE", track.filePath])
            try ProcessRunner.run(metaflac, arguments: ["--import-picture-from=3||||\(artworkURL.path)", track.filePath])
        }
    }

    private func writeWithFFmpeg(track: MusicTrack, artworkURL: URL?) throws {
        guard let ffmpeg = ProcessRunner.findExecutable(named: "ffmpeg") else {
            throw ProcessRunnerError.executableMissing("ffmpeg")
        }

        let original = track.fileURL
        let ext = original.pathExtension
        let temp = original.deletingLastPathComponent()
            .appendingPathComponent(".\(original.deletingPathExtension().lastPathComponent).zihu.tmp.\(ext)")

        try? FileManager.default.removeItem(at: temp)

        var arguments = ["-y", "-i", original.path]
        if let artworkURL {
            arguments.append(contentsOf: ["-i", artworkURL.path, "-map", "0:a", "-map", "1:v", "-c:a", "copy", "-c:v", "mjpeg", "-disposition:v", "attached_pic"])
        } else {
            arguments.append(contentsOf: ["-map", "0:a", "-c:a", "copy"])
        }

        arguments.append(contentsOf: [
            "-metadata", "title=\(track.title)",
            "-metadata", "artist=\(track.artist)",
            "-metadata", "album=\(track.album)"
        ])

        if ext.lowercased() == "mp3" {
            arguments.append(contentsOf: ["-id3v2_version", "3"])
        }

        arguments.append(temp.path)
        try ProcessRunner.run(ffmpeg, arguments: arguments)

        let backup = original.deletingLastPathComponent()
            .appendingPathComponent(".\(original.lastPathComponent).zihu.backup")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: original, to: backup)
        do {
            try FileManager.default.moveItem(at: temp, to: original)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.moveItem(at: backup, to: original)
            throw error
        }
    }
}
