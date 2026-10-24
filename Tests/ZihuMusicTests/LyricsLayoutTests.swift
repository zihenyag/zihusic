import XCTest
@testable import ZihuMusic

final class LyricsLayoutTests: XCTestCase {
    func testBlurAndFullDockHeightExcludeLyricHitTesting() {
        let layout = LyricsLayout(texts: Array(repeating: "A lyric", count: 30), width: 340)
        let size = CGSize(width: 396, height: 760)
        let center = layout.centers[15]
        for y in [0.0, 40, 67.9, 634, 690, 759] {
            XCTAssertNil(LyricsInteraction.index(at: CGPoint(x: 180, y: y), size: size,
                center: center, layout: layout, top: 68, bottom: 126))
        }
        for y in [68.0, 240, 380, 633.9] {
            XCTAssertNotNil(LyricsInteraction.index(at: CGPoint(x: 180, y: y), size: size,
                center: center, layout: layout, top: 68, bottom: 126))
        }
        XCTAssertEqual(LyricsInteraction.index(at: CGPoint(x: 180, y: 380), size: size,
            center: center, layout: layout, top: 68, bottom: 126), 15)
        XCTAssertNil(LyricsInteraction.index(at: CGPoint(x: 180, y: 100), size: size,
            center: layout.centers[0], layout: layout, top: 68, bottom: 126))
    }

    func testLyricsStayOnOneRowUntilTheExactNextBoundary() {
        let timeline = LyricsTimeline([
            LyricsLine(time: 0, text: "Intro"),
            LyricsLine(time: 10, text: "First line"),
            LyricsLine(time: 10, text: "第一句翻译"),
            LyricsLine(time: 14.5, text: "Second line")
        ])
        XCTAssertEqual(timeline.lines.count, 3)
        XCTAssertEqual(timeline.lines[1].text, "First line\n第一句翻译")
        for time in [10.0, 10.01, 11, 12.8, 14.499] { XCTAssertEqual(timeline.index(at: time), 1) }
        XCTAssertEqual(timeline.index(at: 14.5), 2)
        XCTAssertEqual(timeline.index(at: 9.999), 0)
        XCTAssertEqual(timeline.index(at: 100), 2)
        XCTAssertEqual(timeline.index(at: .nan), 0)
    }

    func testIntroCreditsHaveDiscreteBoundariesAndEmptyLyricsAreSafe() {
        XCTAssertEqual(LyricsTimeline([]).index(at: 10), 0)
        let timeline = LyricsTimeline([LyricsLine(time: 0, text: "Title"), LyricsLine(time: 0, text: "Artist"),
                                       LyricsLine(time: 12, text: "First lyric")])
        XCTAssertEqual(timeline.index(at: 0), 0)
        XCTAssertEqual(timeline.index(at: timeline.lines[1].time - 0.001), 0)
        XCTAssertEqual(timeline.index(at: timeline.lines[1].time), 1)
        XCTAssertEqual(timeline.index(at: 12), 2)
    }

    func testTranslationAndLongParagraphGetTheirFullHeight() {
        let single = LyricsLayout(texts: ["A quiet river"], width: 340)
        let bilingual = LyricsLayout(texts: ["A quiet river\n一条安静的河流"], width: 340)
        let paragraph = String(repeating: "A longer sentence that wraps naturally across the lyric column. ", count: 5)
        let narrow = LyricsLayout(texts: [paragraph], width: 180)
        let wide = LyricsLayout(texts: [paragraph], width: 540)
        XCTAssertEqual(single.heights[0], 52)
        XCTAssertGreaterThan(bilingual.heights[0], single.heights[0])
        XCTAssertGreaterThan(narrow.heights[0], wide.heights[0])
        XCTAssertGreaterThan(wide.heights[0], 100)
        XCTAssertGreaterThanOrEqual(bilingual.heights[0], LyricsLayout.textHeight("A quiet river\n一条安静的河流", width: 340) + 18)
    }

    func testThreeAndFourExplicitLinesAreNotLimitedToTwo() {
        let layout = LyricsLayout(texts: ["First\n第一行\nSecond\n第二行"], width: 300)
        let twoLines = LyricsLayout(texts: ["First\n第一行"], width: 300)
        XCTAssertGreaterThan(layout.heights[0], twoLines.heights[0] + 40)
    }

    func testHitTestingCoversEachVariableHeightRow() throws {
        let layout = LyricsLayout(texts: ["One", "Two\n二\nTranslation", String(repeating: "长句自然换行，", count: 20), "Last"], width: 220)
        for index in layout.heights.indices {
            XCTAssertEqual(layout.index(atContentY: layout.starts[index] + 1), index)
            XCTAssertEqual(layout.index(atContentY: layout.starts[index] + layout.heights[index] - 1), index)
            if index + 1 < layout.heights.count {
                XCTAssertEqual(layout.starts[index] + layout.heights[index], layout.starts[index + 1], accuracy: 0.001)
            }
        }
        XCTAssertEqual(layout.index(atContentY: -100), 0)
        XCTAssertEqual(layout.index(atContentY: layout.totalHeight + 100), 3)
    }

    func testScrollAndCenteringUseTheSameMeasuredPositions() {
        let layout = LyricsLayout(texts: ["Short", "A line\n一行\nAnother line", "Last"], width: 260)
        for position in stride(from: 0.0, through: 2.0, by: 0.125) {
            XCTAssertEqual(layout.position(atCenter: layout.center(at: position)), position, accuracy: 0.0001)
        }
        let range = layout.visibleRange(center: layout.centers[1], viewportHeight: 150)
        XCTAssertTrue(range.contains(1))
    }

    func testSameTimestampTranslationStaysWithItsOriginal() {
        let parsed = LyricsService().parseLRC("[00:00.00]Title\n[00:00.00]Artist\n[00:10.00]An original sentence\n[00:10.00]对应的翻译\n[00:13.00]Next sentence")
        let grouped = LyricsLayout.groupTranslations(parsed)
        XCTAssertEqual(grouped.count, 4)
        XCTAssertEqual(grouped[2].text, "An original sentence\n对应的翻译")
        XCTAssertEqual(grouped[2].time, 10)
        XCTAssertEqual(grouped[3].time, 13)
    }
}
