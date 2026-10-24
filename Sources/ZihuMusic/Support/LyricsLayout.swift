import AppKit

/// Shared text metrics for drawing, scrolling, and click-to-seek. A lyric entry
/// can contain any number of translated or wrapped lines; only single-line
/// entries have the compact minimum height.
struct LyricsLayout {
    static let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    static let minimumRowHeight: CGFloat = 52
    static let paragraphSpacing: CGFloat = 4
    static let rowPadding: CGFloat = 18

    let heights: [CGFloat]
    let starts: [CGFloat]
    let centers: [CGFloat]
    let totalHeight: CGFloat

    init(texts: [String], width: CGFloat) {
        var heights: [CGFloat] = []
        var starts: [CGFloat] = []
        var centers: [CGFloat] = []
        var offset: CGFloat = 0
        for text in texts {
            let height = max(Self.minimumRowHeight, Self.textHeight(text, width: width) + Self.rowPadding)
            heights.append(height)
            starts.append(offset)
            centers.append(offset + height / 2)
            offset += height
        }
        self.heights = heights
        self.starts = starts
        self.centers = centers
        totalHeight = offset
    }

    static func attributedText(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = paragraphSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: color
        ])
    }

    static func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        let width = width.isFinite ? max(width, 1) : 1
        let rect = attributedText(text).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 2
    }

    func center(at position: Double) -> CGFloat {
        guard !centers.isEmpty else { return 0 }
        let position = position.isFinite ? min(max(position, 0), Double(centers.count - 1)) : 0
        let lower = Int(position)
        let upper = min(lower + 1, centers.count - 1)
        return centers[lower] + CGFloat(position - Double(lower)) * (centers[upper] - centers[lower])
    }

    func position(atCenter offset: CGFloat) -> Double {
        guard centers.count > 1 else { return 0 }
        if offset <= centers[0] { return 0 }
        if offset >= centers[centers.count - 1] { return Double(centers.count - 1) }
        var lower = 0
        var upper = centers.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if centers[middle] <= offset { lower = middle } else { upper = middle }
        }
        return Double(lower) + Double((offset - centers[lower]) / (centers[upper] - centers[lower]))
    }

    func index(atContentY offset: CGFloat) -> Int? {
        guard !starts.isEmpty, offset.isFinite else { return nil }
        var lower = 0
        var upper = starts.count
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= offset { lower = middle } else { upper = middle }
        }
        return lower
    }

    func visibleRange(center: CGFloat, viewportHeight: CGFloat) -> Range<Int> {
        guard let first = index(atContentY: center - viewportHeight / 2 - 2 * Self.minimumRowHeight),
              let last = index(atContentY: center + viewportHeight / 2 + 2 * Self.minimumRowHeight) else { return 0..<0 }
        return first..<min(last + 1, heights.count)
    }

    /// Separate LRC entries with the same timestamp are commonly translations.
    /// Preserve intro credits at time zero, which are animated individually.
    static func groupTranslations(_ source: [LyricsLine]) -> [LyricsLine] {
        var result: [LyricsLine] = []
        for line in source {
            if let previous = result.last, line.time > 0.05, abs(previous.time - line.time) < 0.001 {
                if previous.text != line.text {
                    result[result.count - 1] = LyricsLine(time: previous.time, text: previous.text + "\n" + line.text)
                }
            } else {
                result.append(line)
            }
        }
        return result
    }
}
