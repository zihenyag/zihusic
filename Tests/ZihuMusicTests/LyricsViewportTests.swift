import AppKit
import XCTest
@testable import ZihuMusic

@MainActor
final class LyricsViewportTests: XCTestCase {
    func testChangingTracksCancelsThePreviousLinesMovement() async throws {
        let view = LyricsScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 760))
        let first = LyricsTimeline((0..<30).map { LyricsLine(time: Double($0), text: "Old \($0)") })
        configure(view, timeline: first, index: 15)
        configure(view, timeline: first, index: 16)
        try await Task.sleep(nanoseconds: 100_000_000)
        let next = LyricsTimeline((0..<10).map { LyricsLine(time: Double($0), text: "New \($0)") })
        configure(view, timeline: next, index: 0)
        try await Task.sleep(nanoseconds: 450_000_000)
        try assertCentered(view, text: "New 0")
    }

    func testCurrentLyricStaysCenteredAfterResizeAndChangingTracks() throws {
        let view = LyricsScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 760))
        let timeline = LyricsTimeline((0..<30).map { LyricsLine(time: Double($0 * 5), text: "Lyric \($0)") })
        configure(view, timeline: timeline, index: 15)
        try assertCentered(view, text: "Lyric 15")
        view.setFrameSize(CGSize(width: 640, height: 1_000))
        view.layoutSubtreeIfNeeded()
        configure(view, timeline: timeline, index: 15)
        try assertCentered(view, text: "Lyric 15")
        let translated = LyricsTimeline((0..<5).map { LyricsLine(time: Double($0 * 3), text: "New lyric \($0)\n翻译") })
        configure(view, timeline: translated, index: 2)
        try assertCentered(view, text: "New lyric 2\n翻译")
    }

    private func configure(_ view: LyricsScrollView, timeline: LyricsTimeline, index: Int) {
        view.tile()
        view.configure(lines: timeline.lines, index: index, top: 68, bottom: 126,
            accent: .controlAccentColor, normal: .secondaryLabelColor, hover: .labelColor, seek: { _ in })
        view.layoutSubtreeIfNeeded()
    }

    private func assertCentered(_ view: LyricsScrollView, text: String) throws {
        let row = try XCTUnwrap(view.documentView?.subviews.first { ($0.accessibilityValue() as? String) == text })
        XCTAssertEqual(row.convert(row.bounds, to: view).midY, view.contentView.bounds.height / 2, accuracy: 0.5)
    }
}
