import AppKit

enum LyricsInteraction {
    static let returnDelay: TimeInterval = 3

    static func activeRect(size: CGSize, top: CGFloat, bottom: CGFloat) -> CGRect {
        CGRect(x: 0, y: min(top, size.height), width: size.width,
               height: max(0, size.height - top - bottom))
    }

    static func index(at point: CGPoint, size: CGSize, center: CGFloat, layout: LyricsLayout,
                      top: CGFloat, bottom: CGFloat) -> Int? {
        guard activeRect(size: size, top: top, bottom: bottom).contains(point) else { return nil }
        let offset = point.y - size.height / 2 + center
        guard offset >= 0, offset < layout.totalHeight else { return nil }
        return layout.index(atContentY: offset)
    }
}
