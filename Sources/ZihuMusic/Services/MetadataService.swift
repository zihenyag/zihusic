import AVFoundation
import CoreMedia
import Foundation

struct MetadataService {
    static let supportedExtensions: Set<String> = [
        "flac", "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "alac"
    ]

    func loadTrack(from url: URL, existing: MusicTrack? = nil, source: TrackSource = .local) -> MusicTrack? {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }

        let id = existing?.id ?? UUID()
        let existingTitle = usableMetadata(existing?.title)
        let existingArtist = usableMetadata(existing?.artist)
        let existingAlbum = usableMetadata(existing?.album)
        var title = existingTitle ?? url.deletingPathExtension().lastPathComponent
        var artist = existingArtist ?? ""
        var album = existingAlbum ?? ""
        var duration = existing?.duration ?? 0
        var sampleRate = existing?.sampleRate
        var bitDepth = existing?.bitDepth
        var channelCount = existing?.channelCount
        var artworkFileName = existing?.artworkFileName
        var embeddedLyrics = existing?.embeddedLyrics

        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = fileAttributes?[.modificationDate] as? Date

        if url.pathExtension.lowercased() == "flac" {
            let flacMetadata = readFLACMetadata(from: url, id: id)
            title = existingTitle ?? usableMetadata(flacMetadata.title) ?? title
            artist = preferredArtist(current: artist, candidate: flacMetadata.artist)
            album = existingAlbum ?? usableMetadata(flacMetadata.album) ?? album
            if flacMetadata.duration > 0 {
                duration = flacMetadata.duration
            }
            sampleRate = flacMetadata.sampleRate ?? sampleRate
            bitDepth = flacMetadata.bitDepth ?? bitDepth
            channelCount = flacMetadata.channelCount ?? channelCount
            artworkFileName = artworkFileName ?? flacMetadata.artworkFileName
            embeddedLyrics = embeddedLyrics ?? flacMetadata.lyrics
        }

        let avMetadata = readAVMetadata(from: url, id: id)
        title = existingTitle ?? usableMetadata(avMetadata.title) ?? title
        artist = preferredArtist(current: artist, candidate: avMetadata.artist)
        album = existingAlbum ?? usableMetadata(avMetadata.album) ?? album
        duration = duration > 0 ? duration : avMetadata.duration
        sampleRate = sampleRate ?? avMetadata.sampleRate
        bitDepth = bitDepth ?? avMetadata.bitDepth
        channelCount = channelCount ?? avMetadata.channelCount
        artworkFileName = artworkFileName ?? avMetadata.artworkFileName

        let ffprobeMetadata = readFFProbeMetadata(from: url)
        title = existingTitle ?? usableMetadata(ffprobeMetadata.title) ?? title
        artist = preferredArtist(current: artist, candidate: ffprobeMetadata.artist)
        album = existingAlbum ?? usableMetadata(ffprobeMetadata.album) ?? album

        artworkFileName = artworkFileName ?? findFolderArtwork(near: url)
        let lyricsFilePath = findLyricsFile(for: url, title: title, artist: artist)?.path

        return MusicTrack(
            id: id,
            filePath: url.path,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            format: url.pathExtension.lowercased(),
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: channelCount,
            artworkFileName: artworkFileName,
            lyricsFilePath: lyricsFilePath,
            embeddedLyrics: embeddedLyrics,
            source: existing?.source ?? source,
            importedAt: existing?.importedAt ?? Date(),
            updatedAt: Date(),
            fileModifiedAt: modifiedAt
        )
    }

    private struct MetadataSnapshot {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double = 0
        var sampleRate: Int?
        var bitDepth: Int?
        var channelCount: Int?
        var artworkFileName: String?
        var lyrics: String?
    }

    private func readAVMetadata(from url: URL, id: UUID) -> MetadataSnapshot {
        let asset = AVURLAsset(url: url)
        var snapshot = MetadataSnapshot(duration: CMTimeGetSeconds(asset.duration))

        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let rawDescription = audioTrack.formatDescriptions.first {
            let description = rawDescription as! CMAudioFormatDescription
            if let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                if streamDescription.mSampleRate > 0 {
                    snapshot.sampleRate = Int(streamDescription.mSampleRate)
                }
                if streamDescription.mBitsPerChannel > 0 {
                    snapshot.bitDepth = Int(streamDescription.mBitsPerChannel)
                }
                if streamDescription.mChannelsPerFrame > 0 {
                    snapshot.channelCount = Int(streamDescription.mChannelsPerFrame)
                }
            }
        }

        var artistValues: [String] = []
        for item in asset.commonMetadata {
            switch item.commonKey?.rawValue {
            case "title":
                snapshot.title = item.stringValue
            case "artist":
                if let value = item.stringValue {
                    artistValues.append(value)
                }
            case "albumName":
                snapshot.album = item.stringValue
            case "artwork":
                if let data = item.dataValue ?? item.value as? Data {
                    snapshot.artworkFileName = writeArtwork(data: data, id: id, preferredExtension: "artwork")
                }
            default:
                break
            }
        }

        snapshot.artist = combinedArtistValues(artistValues)
        return snapshot
    }

    private func readFLACMetadata(from url: URL, id: UUID) -> MetadataSnapshot {
        guard let metaflac = ProcessRunner.findExecutable(named: "metaflac") else {
            return MetadataSnapshot()
        }

        var snapshot = MetadataSnapshot()
        var artistValues: [String] = []
        var albumArtistValues: [String] = []

        if let tags = try? ProcessRunner.run(metaflac, arguments: ["--export-tags-to=-", url.path]).stdout {
            for line in tags.components(separatedBy: .newlines) {
                guard let equals = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<equals]).uppercased()
                let value = String(line[line.index(after: equals)...])
                switch key {
                case "TITLE":
                    snapshot.title = value
                case "ARTIST":
                    artistValues.append(value)
                case "ALBUMARTIST":
                    albumArtistValues.append(value)
                case "ALBUM":
                    snapshot.album = value
                case "LYRICS", "UNSYNCEDLYRICS", "LYRIC":
                    if snapshot.lyrics == nil { snapshot.lyrics = value }
                default:
                    break
                }
            }
        }
        snapshot.artist = combinedArtistValues(artistValues.isEmpty ? albumArtistValues : artistValues)

        if let stream = try? ProcessRunner.run(
            metaflac,
            arguments: ["--show-sample-rate", "--show-channels", "--show-bps", "--show-total-samples", url.path]
        ).stdout {
            let values = stream.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if values.count >= 4 {
                snapshot.sampleRate = Int(values[0])
                snapshot.channelCount = Int(values[1])
                snapshot.bitDepth = Int(values[2])
                if let totalSamples = Double(values[3]), let rate = Double(values[0]), rate > 0 {
                    snapshot.duration = totalSamples / rate
                }
            }
        }

        let pictureName = "\(id.uuidString)-flac-artwork"
        let pictureURL = AppDirectories.artworkDirectory.appendingPathComponent(pictureName)
        if (try? ProcessRunner.run(metaflac, arguments: ["--export-picture-to=\(pictureURL.path)", url.path])) != nil {
            snapshot.artworkFileName = pictureName
        }

        return snapshot
    }

    private func readFFProbeMetadata(from url: URL) -> MetadataSnapshot {
        guard let ffprobe = ProcessRunner.findExecutable(named: "ffprobe") else {
            return MetadataSnapshot()
        }

        guard let output = try? ProcessRunner.run(
            ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format_tags",
                "-of", "default=noprint_wrappers=1",
                url.path
            ]
        ).stdout else {
            return MetadataSnapshot()
        }

        var snapshot = MetadataSnapshot()
        var artistValues: [String] = []
        for line in output.components(separatedBy: .newlines) {
            guard line.hasPrefix("TAG:"), let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.index(line.startIndex, offsetBy: 4)..<equals]).uppercased()
            let value = String(line[line.index(after: equals)...])
            switch key {
            case "TITLE":
                snapshot.title = value
            case "ARTIST", "ALBUM_ARTIST", "ALBUMARTIST":
                artistValues.append(value)
            case "ALBUM":
                snapshot.album = value
            case "LYRICS", "UNSYNCEDLYRICS", "LYRIC":
                if snapshot.lyrics == nil { snapshot.lyrics = value }
            default:
                break
            }
        }
        snapshot.artist = combinedArtistValues(artistValues)
        return snapshot
    }

    private func preferredArtist(current: String, candidate: String?) -> String {
        let currentValue = usableMetadata(current) ?? ""
        guard let candidateValue = usableMetadata(candidate) else {
            return currentValue
        }
        guard !currentValue.isEmpty else { return candidateValue }

        let currentTokens = artistTokens(in: currentValue)
        let candidateTokens = artistTokens(in: candidateValue)
        if candidateTokens.count > currentTokens.count,
           currentTokens.isEmpty || currentTokens.isSubset(of: candidateTokens) {
            return candidateValue
        }
        return currentValue
    }

    private func usableMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutQuestionSuffix = trimmed
            .replacingOccurrences(of: #"\s*[?？]+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutQuestionSuffix.isEmpty else { return nil }

        let onlyQuestionMarks = withoutQuestionSuffix.allSatisfy { $0 == "?" || $0 == "？" }
        return onlyQuestionMarks ? nil : withoutQuestionSuffix
    }

    private func combinedArtistValues(_ values: [String]) -> String? {
        let joined = values
            .flatMap { artistTokensForDisplay(in: $0) }
            .reduce(into: [String]()) { result, value in
                if !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                    result.append(value)
                }
            }
            .joined(separator: ";")
        return joined.isEmpty ? nil : joined
    }

    private func artistTokens(in value: String) -> Set<String> {
        Set(artistTokensForDisplay(in: value).map { $0.lowercased() })
    }

    private func artistTokensForDisplay(in value: String) -> [String] {
        let normalized = value.replacingOccurrences(
            of: #"(?i)\s+(feat\.?|ft\.?|featuring|with)\s+"#,
            with: ";",
            options: .regularExpression
        )
        let separators = CharacterSet(charactersIn: ";；/／,，|")
        return normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { usableMetadata($0) }
    }

    private func writeArtwork(data: Data, id: UUID, preferredExtension: String) -> String? {
        do {
            try AppDirectories.ensureCreated()
            let fileName = "\(id.uuidString)-\(preferredExtension)"
            let destination = AppDirectories.artworkDirectory.appendingPathComponent(fileName)
            try data.write(to: destination, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private func findFolderArtwork(near url: URL) -> String? {
        let folder = url.deletingLastPathComponent()
        let candidates = ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "front.png"]
        for name in candidates {
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    private func findLyricsFile(for url: URL, title: String, artist: String) -> URL? {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
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
}
