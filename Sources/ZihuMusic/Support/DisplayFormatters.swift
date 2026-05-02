import Foundation

enum DisplayFormatters {
    static func time(_ value: TimeInterval) -> String {
        guard value.isFinite && value > 0 else { return "0:00" }
        let total = Int(value.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func technicalSummary(for track: MusicTrack) -> String {
        var parts = [track.format.uppercased()]
        if let sampleRate = track.sampleRate {
            let rate = sampleRate >= 1000 ? "\(sampleRate / 1000) kHz" : "\(sampleRate) Hz"
            parts.append(rate)
        }
        if let bitDepth = track.bitDepth, bitDepth > 0 {
            parts.append("\(bitDepth)-bit")
        }
        if let channelCount = track.channelCount {
            parts.append(channelCount == 1 ? "Mono" : "\(channelCount) ch")
        }
        parts.append(time(track.duration))
        return parts.joined(separator: " · ")
    }

    static func sanitizedFileName(_ value: String, fallback: String = "Music") -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }
}
