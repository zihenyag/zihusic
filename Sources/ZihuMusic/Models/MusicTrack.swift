import Foundation

enum TrackSource: String, Codable, CaseIterable {
    case local
    case downloaded
}

struct MusicTrack: Identifiable, Codable, Hashable {
    var id: UUID
    var filePath: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var format: String
    var sampleRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var artworkFileName: String?
    var lyricsFilePath: String?
    var embeddedLyrics: String?
    var source: TrackSource
    var importedAt: Date
    var updatedAt: Date
    var fileModifiedAt: Date?

    init(
        id: UUID = UUID(),
        filePath: String,
        title: String,
        artist: String = "",
        album: String = "",
        duration: Double = 0,
        format: String,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        channelCount: Int? = nil,
        artworkFileName: String? = nil,
        lyricsFilePath: String? = nil,
        embeddedLyrics: String? = nil,
        source: TrackSource = .local,
        importedAt: Date = Date(),
        updatedAt: Date = Date(),
        fileModifiedAt: Date? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.artworkFileName = artworkFileName
        self.lyricsFilePath = lyricsFilePath
        self.embeddedLyrics = embeddedLyrics
        self.source = source
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.fileModifiedAt = fileModifiedAt
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var displayTitle: String {
        cleaned(title) ?? fileURL.deletingPathExtension().lastPathComponent
    }

    var displayArtist: String {
        guard let value = cleaned(artist) else { return "未知作者" }
        return normalizedArtist(value)
    }

    var displayAlbum: String {
        cleaned(album) ?? "未知专辑"
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutQuestionSuffix = trimmed
            .replacingOccurrences(of: #"\s*[?？]+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutQuestionSuffix.isEmpty else { return nil }

        let onlyQuestionMarks = withoutQuestionSuffix.allSatisfy { character in
            character == "?" || character == "？"
        }
        return onlyQuestionMarks ? nil : withoutQuestionSuffix
    }

    private func normalizedArtist(_ value: String) -> String {
        let featNormalized = value.replacingOccurrences(
            of: #"(?i)\s+(feat\.?|ft\.?|featuring|with)\s+"#,
            with: "、",
            options: .regularExpression
        )
        let separators = CharacterSet(charactersIn: ";；/／,，|")
        let artists = featNormalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return artists.isEmpty ? value : artists.joined(separator: "、")
    }

}
