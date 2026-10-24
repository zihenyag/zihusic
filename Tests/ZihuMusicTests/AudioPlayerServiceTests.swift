import AVFoundation
import XCTest
@testable import ZihuMusic

final class AudioPlayerServiceTests: XCTestCase {
    @MainActor
    func testPlaybackPauseAndAccurateSeek() async throws {
        let url = try silentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = AudioPlayerService(airPlay: AirPlayRouting(context: nil, defaults: .standard, startsAutomatically: false))
        player.volume = 0
        defer { player.stop() }
        player.play(track(url))
        try await waitUntil { player.preciseCurrentTime > 0.15 }
        XCTAssertEqual(player.boundedDuration, 3, accuracy: 0.05)
        XCTAssertTrue(player.isPlaying)
        player.pause()
        player.seek(to: 1.25)
        try await waitUntil { abs(player.routingPlayer.currentTime().seconds - 1.25) < 0.03 }
        XCTAssertEqual(player.preciseCurrentTime, 1.25, accuracy: 0.03)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(player.preciseCurrentTime, 1.25, accuracy: 0.03)
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testLatestSeekWinsAndInvalidTimeIsClamped() async throws {
        let url = try silentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = AudioPlayerService(airPlay: AirPlayRouting(context: nil, defaults: .standard, startsAutomatically: false))
        player.volume = 0
        defer { player.stop() }
        player.play(track(url))
        try await waitUntil { player.routingPlayer.currentItem?.status == .readyToPlay }
        player.pause()
        player.seek(to: 2)
        player.seek(to: 0.5)
        XCTAssertEqual(player.preciseCurrentTime, 0.5, accuracy: 0.001)
        try await waitUntil { abs(player.routingPlayer.currentTime().seconds - 0.5) < 0.03 }
        player.seek(to: .nan)
        XCTAssertEqual(player.preciseCurrentTime, 0)
        try await waitUntil { abs(player.routingPlayer.currentTime().seconds) < 0.03 }
        player.seek(to: -10)
        XCTAssertEqual(player.preciseCurrentTime, 0)
    }

    @MainActor
    func testSwitchingTracksPreservesPlayerAndAudioContext() async throws {
        let url = try silentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = AudioPlayerService(airPlay: AirPlayRouting(context: nil, defaults: .standard, startsAutomatically: false))
        player.volume = 0
        defer { player.stop() }
        let engine = player.routingPlayer
        let context = player.airPlayContext
        player.play(track(url))
        try await waitUntil { player.routingPlayer.currentItem?.status == .readyToPlay }
        let oldItem = try XCTUnwrap(player.routingPlayer.currentItem)
        var completed = 0
        player.onFinished = { completed += 1 }
        player.play(track(url))
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(completed, 0)
        XCTAssertTrue(engine === player.routingPlayer)
        XCTAssertTrue(context === player.airPlayContext)
        XCTAssertTrue(player.isPlaying)
    }

    @MainActor
    func testMissingFileReportsFailureAndStopClearsState() async throws {
        let player = AudioPlayerService(airPlay: AirPlayRouting(context: nil, defaults: .standard, startsAutomatically: false))
        player.volume = 0
        player.play(track(URL(fileURLWithPath: "/tmp/zihusic-missing-\(UUID().uuidString).wav")))
        try await waitUntil { player.errorMessage != nil }
        XCTAssertFalse(player.isPlaying)
        player.stop()
        XCTAssertNil(player.currentTrack)
        XCTAssertNil(player.routingPlayer.currentItem)
        XCTAssertEqual(player.boundedCurrentTime, 0)
        XCTAssertEqual(player.boundedDuration, 0)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 6)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(condition(), "Audio operation timed out")
    }

    private func track(_ url: URL) -> ZihuMusic.MusicTrack {
        ZihuMusic.MusicTrack(filePath: url.path, title: "Playback test", duration: 3, format: "WAV")
    }

    private func silentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zihusic-test-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 144_000))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(format.channelCount) {
            buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(buffer.frameLength))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
