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
        guard let value = cleaned(artist) else {
            return embeddedLyricsArtist() ?? "未知作者"
        }
        if let embeddedArtist = embeddedLyricsArtist(),
           artistValue(embeddedArtist, isMoreCompleteThan: value) {
            return embeddedArtist
        }
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
        let separatorNormalized = featNormalized.replacingOccurrences(
            of: #"[;；/／,，|]+"#,
            with: "、",
            options: .regularExpression
        )
        let artists = separatorNormalized
            .components(separatedBy: "、")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return artists.isEmpty ? value : artists.joined(separator: "、")
    }

    private func embeddedLyricsArtist() -> String? {
        guard let embeddedLyrics else { return nil }
        for line in embeddedLyrics.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.localizedCaseInsensitiveContains("[ar:"),
                  let start = trimmed.range(of: "[ar:", options: .caseInsensitive),
                  let end = trimmed[start.upperBound...].firstIndex(of: "]") else {
                continue
            }
            let rawArtist = String(trimmed[start.upperBound..<end])
            guard let cleaned = cleaned(rawArtist) else { continue }
            return normalizedArtist(cleaned)
        }
        return nil
    }

    private func artistValue(_ candidate: String, isMoreCompleteThan current: String) -> Bool {
        let currentTokens = Set(artistTokens(in: current))
        let candidateTokens = Set(artistTokens(in: candidate))
        let represented = currentTokens.allSatisfy { currentToken in
            candidateTokens.contains { candidateToken in
                candidateToken == currentToken
                    || candidateToken.localizedCaseInsensitiveContains(currentToken)
                    || currentToken.localizedCaseInsensitiveContains(candidateToken)
            }
        }
        return represented && (candidateTokens.count > currentTokens.count || candidate.count > current.count)
    }

    private func artistTokens(in value: String) -> [String] {
        normalizedArtist(value)
            .components(separatedBy: "、")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

}
