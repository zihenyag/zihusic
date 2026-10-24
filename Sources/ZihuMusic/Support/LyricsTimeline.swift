import Foundation

/// Timestamp lookup stays discrete; the viewport animates only when a line changes.
struct LyricsTimeline: Equatable, Codable, Sendable {
    struct Entry: Identifiable, Equatable, Codable, Sendable {
        let id: UUID
        let time: Double
        let text: String
    }
    let lines: [Entry]

    init(_ source: [LyricsLine]) {
        let source = LyricsLayout.groupTranslations(source)
        var times = source.map(\.time)
        let introCount = source.prefix { $0.time <= 0.05 }.count
        if introCount > 1, introCount < source.count {
            let firstTime = source[introCount].time
            if firstTime > 2 {
                let spacing = min(2.4, max(0.9, max(firstTime - 1.2, 0.6) / Double(introCount)))
                for index in 0..<introCount { times[index] = min(Double(index) * spacing, firstTime - 1.2) }
            }
        }
        lines = source.enumerated().map { Entry(id: $0.element.id, time: times[$0.offset], text: $0.element.text) }
    }

    func index(at time: Double) -> Int {
        guard !lines.isEmpty else { return 0 }
        let time = time.isFinite ? time : 0
        var lower = 0
        var upper = lines.count
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if lines[middle].time <= time { lower = middle } else { upper = middle }
        }
        return lower
    }
}
