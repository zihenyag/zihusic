import AVFoundation
import XCTest
@testable import ZihuMusic

final class GroupedAudioOutputTests: XCTestCase {
    @MainActor
    func testChangingTracksNeverPublishesThePreviousTracksClock() async throws {
        let first = try silentWAV(seconds: 4)
        let second = try silentWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let output = GroupedAudioOutput(context: nil, deviceUID: nil)
        output.setOutputs(localEnabled: true, localVolume: 0, masterVolume: 0, delay: 0)
        defer { output.reset() }
        output.load(first, at: 2.5, playing: false)
        try await waitUntil { output.isReady && abs(output.currentTime - 2.5) < 0.02 }
        try await Task.sleep(nanoseconds: 200_000_000)
        var times: [Double] = []
        output.onProgress = { times.append(output.currentTime) }
        output.load(second, at: 0, playing: false)
        try await waitUntil { output.isReady }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(times.isEmpty)
        XCTAssertTrue(times.allSatisfy { abs($0) < 0.03 }, "Previous track time leaked after switching: \(times)")
    }

    @MainActor
    func testSilentJoinedReceiversKeepTheTimelineWhenEnabled() async throws {
        let url = try silentWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = GroupedAudioOutput(context: nil, deviceUID: nil)
        output.setOutputs(localEnabled: true, localVolume: 0, masterVolume: 0, delay: 0, remoteEnabled: false)
        var failure: Error?
        output.onError = { failure = $0 }
        defer { output.reset() }
        output.load(url, at: 0, playing: true)
        try await waitUntil { output.currentTime > 0.3 || failure != nil }
        XCTAssertNil(failure)
        let position = output.currentTime
        output.setOutputs(localEnabled: true, localVolume: 0, masterVolume: 0, delay: 0, remoteEnabled: true)
        try await waitUntil { output.currentTime > position + 0.25 || failure != nil }
        XCTAssertNil(failure)
        XCTAssertTrue(output.isPlaying)
        XCTAssertGreaterThan(output.currentTime, position)
        XCTAssertLessThan(output.currentTime, position + 1)
    }

    @MainActor
    func testSharedPacketsSupportPauseSeekResumeAndFinishOnce() async throws {
        let url = try silentWAV(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = GroupedAudioOutput(context: nil, deviceUID: nil)
        output.setOutputs(localEnabled: true, localVolume: 0, masterVolume: 0, delay: 0)
        var failure: Error?
        var finished = 0
        output.onError = { failure = $0 }
        output.onFinished = { finished += 1 }
        defer { output.reset() }
        output.load(url, at: 0, playing: true)
        try await waitUntil { output.currentTime > 0.15 || failure != nil }
        XCTAssertNil(failure)
        XCTAssertTrue(output.isPlaying)
        output.pause()
        try await Task.sleep(nanoseconds: 200_000_000)
        let paused = output.currentTime
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(output.currentTime, paused, accuracy: 0.025)
        output.seek(to: 1.2)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(output.currentTime, 1.2, accuracy: 0.03)
        XCTAssertFalse(output.isPlaying)
        output.play()
        try await waitUntil { finished > 0 || failure != nil }
        XCTAssertNil(failure)
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(output.currentTime, 2, accuracy: 0.04)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(finished, 1)
    }

    @MainActor
    func testRapidSeeksKeepLatestPositionAndResetCancelsCallbacks() async throws {
        let url = try silentWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = GroupedAudioOutput(context: nil, deviceUID: nil)
        output.setOutputs(localEnabled: true, localVolume: 0, masterVolume: 0, delay: 0)
        var failure: Error?
        output.onError = { failure = $0 }
        defer { output.reset() }
        output.load(url, at: 0, playing: false)
        try await waitUntil { output.isReady || failure != nil }
        XCTAssertNil(failure)
        output.seek(to: 1.8)
        output.seek(to: 0.5)
        output.play()
        try await waitUntil { output.currentTime > 0.65 || failure != nil }
        XCTAssertNil(failure)
        XCTAssertLessThan(output.currentTime, 1.2)
        output.reset()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(output.currentTime, 0)
        XCTAssertFalse(output.isPlaying)
        XCTAssertFalse(output.isReady)
        XCTAssertEqual(output.duration, 0)
    }

    @MainActor
    func testStoppedPreparationCannotReportMissingFileErrorLater() async throws {
        let output = GroupedAudioOutput(context: nil, deviceUID: nil)
        var failed = false
        output.onError = { _ in failed = true }
        output.load(URL(fileURLWithPath: "/tmp/zihusic-missing-\(UUID()).flac"), at: 0, playing: true)
        output.reset()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(failed)
        XCTAssertFalse(output.isReady)
    }

    func testNativeAACPreparationCachesAndInvalidatesChangedSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zihusic-asset-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try silentWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try await AirPlayAudioAsset.prepare(url, cacheDirectory: directory)
        let cached = try await AirPlayAudioAsset.prepare(url, cacheDirectory: directory)
        XCTAssertEqual(first.asset.url, cached.asset.url)
        XCTAssertEqual(first.duration, 1, accuracy: 0.04)
        let replacement = try silentWAV(seconds: 2)
        defer { try? FileManager.default.removeItem(at: replacement) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: replacement, to: url)
        let changed = try await AirPlayAudioAsset.prepare(url, cacheDirectory: directory)
        XCTAssertNotEqual(first.asset.url, changed.asset.url)
        XCTAssertEqual(changed.duration, 2, accuracy: 0.04)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 6)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), "Shared audio operation timed out")
    }

    private func silentWAV(seconds: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zihusic-shared-\(UUID()).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(48_000 * seconds)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 { buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(buffer.frameLength)) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }
}
