import Foundation

struct LyricsService {
    func lyrics(for track: MusicTrack) -> [LyricsLine] {
        if let path = track.lyricsFilePath,
           let text = readText(at: URL(fileURLWithPath: path)) {
            if path.lowercased().hasSuffix(".ass") {
                return parseASS(text)
            }
            return parseLRC(text)
        }

        if let embedded = track.embeddedLyrics, !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return parseLRC(embedded)
        }

        return []
    }

    func parseLRC(_ text: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex?.matches(in: line, range: nsRange) ?? []
            guard !matches.isEmpty else {
                if lines.isEmpty {
                    lines.append(LyricsLine(time: 0, text: line))
                }
                continue
            }

            let lyricStart = matches.last?.range.upperBound ?? 0
            let lyricText = String(line[String.Index(utf16Offset: lyricStart, in: line)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: line),
                    let secondRange = Range(match.range(at: 2), in: line),
                    let minutes = Double(line[minuteRange]),
                    let seconds = Double(line[secondRange])
                else { continue }

                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line),
                   let rawFraction = Double(line[fractionRange]) {
                    let divisor = pow(10.0, Double(line[fractionRange].count))
                    fraction = rawFraction / divisor
                }

                lines.append(LyricsLine(time: minutes * 60 + seconds + fraction, text: lyricText))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    func parseASS(_ text: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        var fields: [String] = []
        var inEvents = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.caseInsensitiveCompare("[Events]") == .orderedSame {
                inEvents = true
                continue
            }

            if line.hasPrefix("[") {
                inEvents = false
                continue
            }

            guard inEvents else { continue }

            if line.lowercased().hasPrefix("format:") {
                let format = line.dropFirst("Format:".count)
                fields = format.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                continue
            }

            guard line.lowercased().hasPrefix("dialogue:") else { continue }
            let payload = String(line.dropFirst("Dialogue:".count)).trimmingCharacters(in: .whitespaces)
            let parts = payload.split(separator: ",", maxSplits: max(fields.count - 1, 9), omittingEmptySubsequences: false)
                .map(String.init)
            guard !parts.isEmpty else { continue }

            let startIndex = fields.firstIndex(of: "start") ?? 1
            let textIndex = fields.firstIndex(of: "text") ?? min(9, max(parts.count - 1, 0))
            guard parts.indices.contains(startIndex), parts.indices.contains(textIndex) else { continue }

            let time = parseASSTime(parts[startIndex])
            let text = cleanASSText(parts[textIndex...].joined(separator: ","))
            guard let time, !text.isEmpty else { continue }
            lines.append(LyricsLine(time: time, text: text))
        }

        return lines.sorted { $0.time < $1.time }
    }

    func currentIndex(in lines: [LyricsLine], time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var current = 0
        for (index, line) in lines.enumerated() where line.time <= time {
            current = index
        }
        return current
    }

    private func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        return nil
    }

    private func parseASSTime(_ value: String) -> TimeInterval? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private func cleanASSText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\[Nn]"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\\h"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
