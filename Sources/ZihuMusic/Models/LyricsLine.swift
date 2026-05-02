import Foundation

struct LyricsLine: Identifiable, Hashable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}
