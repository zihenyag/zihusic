import XCTest
@testable import ZihuMusic

final class AirPlaySelectionTests: XCTestCase {
    func testLateSnapshotCannotUndoFirstClickOrRapidToggle() {
        var state = AirPlaySelection()
        let initialRead = state.revision
        state.request(["macbook"])
        XCTAssertFalse(state.receive([], revision: initialRead))
        XCTAssertEqual(state.selected, ["macbook"])
        XCTAssertEqual(state.pending, ["macbook"])

        let connectRead = state.revision
        state.request([])
        XCTAssertFalse(state.receive(["macbook"], revision: connectRead))
        XCTAssertTrue(state.selected.isEmpty)
        XCTAssertTrue(state.receive([], revision: state.revision))
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertNil(state.requested)
    }

    func testAddingAndRemovingOneSpeakerPreservesOtherSpeakers() {
        var state = AirPlaySelection()
        state.receive(["a"], revision: state.revision)
        state.request(["a", "b"])
        state.receive(["a"], revision: state.revision)
        XCTAssertEqual(state.selected, ["a", "b"])
        XCTAssertEqual(state.pending, ["b"])
        state.receive(["a", "b"], revision: state.revision)
        XCTAssertTrue(state.pending.isEmpty)
        state.request(["b"])
        XCTAssertEqual(state.pending, ["a"])
        state.receive(["b"], revision: state.revision)
        XCTAssertEqual(state.selected, ["b"])
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testTimeoutWorksWithoutAnotherBackendReplyAndAllowsRetry() {
        var state = AirPlaySelection()
        let now = Date(timeIntervalSince1970: 1_000)
        state.receive(["a"], revision: state.revision)
        state.request(["a", "b"], now: now)
        let stuckRead = state.revision
        XCTAssertFalse(state.expire(now: now.addingTimeInterval(11.9)))
        XCTAssertTrue(state.expire(now: now.addingTimeInterval(12)))
        XCTAssertEqual(state.selected, ["a"])
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertFalse(state.receive(["a", "b"], revision: stuckRead))
        state.request(["a", "b"], now: now.addingTimeInterval(13))
        state.receive(["a", "b"], revision: state.revision)
        XCTAssertEqual(state.selected, ["a", "b"])
        XCTAssertFalse(state.expire(now: now.addingTimeInterval(30)))
    }
}
