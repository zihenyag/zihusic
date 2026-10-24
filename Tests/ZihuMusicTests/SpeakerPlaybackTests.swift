import XCTest
@testable import ZihuMusic

final class SpeakerPlaybackTests: XCTestCase {
    func testMutedReadbackPreservesPreferredLevelUntilResume() {
        let now = Date(timeIntervalSince1970: 100)
        var state = SpeakerPlaybackState(volume: 0.6)
        state.setPlaying(false, now: now)
        state.observeVolume(0, now: now.addingTimeInterval(60))
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.volume, 0.6)
        XCTAssertEqual(state.volumeWhenPlaying, 0)
        state.setVolume(0.8, now: now)
        XCTAssertEqual(state.volumeWhenPlaying, 0)
        state.setPlaying(true, now: now)
        state.observeVolume(0, now: now.addingTimeInterval(1))
        XCTAssertEqual(state.volumeWhenPlaying, 0.8)
        state.observeVolume(0.4, now: now.addingTimeInterval(6))
        XCTAssertEqual(state.volume, 0.4)
    }

    @MainActor
    func testDiscoveryAutomaticallyJoinsAllDevicesAndPlaybackNeverRemovesRoutes() async throws {
        let suite = "zihusic.route-tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = DeviceStub(id: "a", volume: 0.46)
        let b = DeviceStub(id: "b", volume: 0.7)
        let context = ContextStub()
        let routing = AirPlayRouting(context: context, defaults: defaults, startsAutomatically: false,
                                     initialDiscovery: DiscoveryStub(devices: [a, b]))
        routing.refresh()
        try await waitUntil(routing) { routing.speakers.filter { !$0.isLocal && $0.isConnected }.count == 2 }
        XCTAssertEqual(context.identifiers, ["a", "b"])
        var additions = context.additions
        XCTAssertTrue(routing.speakers.filter { !$0.isLocal }.allSatisfy { !$0.isPlaying })
        XCTAssertTrue(routing.localEnabled)
        XCTAssertFalse(routing.hasPlayingRemoteOutputs)
        try await waitUntil(routing) { a.volume == 0 && b.volume == 0 }
        routing.setPlaybackEnabled(true, id: "a")
        routing.setPlaybackEnabled(true, id: "b")
        try await waitUntil(routing) { abs(a.volume - 0.46) < 0.001 }
        XCTAssertTrue(routing.hasPlayingRemoteOutputs)
        routing.setPlaybackEnabled(false, id: "a")
        XCTAssertFalse(try XCTUnwrap(routing.speakers.first { $0.id == "a" }).isPlaying)
        XCTAssertTrue(routing.pendingIDs.isEmpty)
        try await waitUntil(routing) { a.volume == 0 }
        XCTAssertEqual(context.identifiers, ["a", "b"])
        XCTAssertEqual(try XCTUnwrap(routing.speakers.first { $0.id == "a" }).volume, 0.46, accuracy: 0.001)
        routing.setVolume(0.72, id: "a")
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(a.volume, 0)
        routing.setPlaybackEnabled(true, id: "a")
        routing.setPlaybackEnabled(false, id: "a")
        routing.setPlaybackEnabled(true, id: "a")
        try await waitUntil(routing) { abs(a.volume - 0.72) < 0.001 }
        XCTAssertEqual(context.additions, additions)
        XCTAssertEqual(context.identifiers, ["a", "b"])
        XCTAssertTrue(routing.hasRemoteOutputs)
        XCTAssertTrue(routing.pendingIDs.isEmpty)

        routing.setPlaybackEnabled(false, id: "a")
        routing.setPlaybackEnabled(false, id: "b")
        routing.setPlaybackEnabled(false, id: AirPlayRouting.localID)
        XCTAssertTrue(routing.speakers.allSatisfy { !$0.isPlaying })
        try await waitUntil(routing) { a.volume == 0 && b.volume == 0 }
        XCTAssertTrue(routing.hasRemoteOutputs)
        XCTAssertTrue(routing.speakers.allSatisfy(\.isConnected))

        // A dropped session auto-rejoins without changing any playback intent.
        context.outputDevices = []
        routing.refresh()
        try await waitUntil(routing) { context.additions == additions + 2 && routing.hasRemoteOutputs }
        try await waitUntil(routing) { routing.speakers.filter { !$0.isLocal && $0.isConnected }.count == 2 }
        XCTAssertTrue(routing.speakers.allSatisfy { !$0.isPlaying })
        XCTAssertEqual(context.identifiers, ["a", "b"])
        additions = context.additions

        var resynchronizations = 0
        routing.onResynchronize = { resynchronizations += 1 }
        routing.resynchronize()
        XCTAssertEqual(resynchronizations, 1)
        XCTAssertEqual(context.identifiers, ["a", "b"])
        XCTAssertEqual(context.additions, additions)

        let restored = AirPlayRouting(context: context, defaults: defaults, startsAutomatically: false)
        restored.refresh()
        try await waitUntil(restored) { restored.speakers.count == 3 }
        XCTAssertTrue(restored.speakers.filter { !$0.isLocal }.allSatisfy { !$0.isPlaying })
        XCTAssertTrue(restored.localEnabled)
        XCTAssertEqual(try XCTUnwrap(restored.speakers.first { $0.id == "a" }).volume, 0.72, accuracy: 0.001)
    }

    @MainActor
    func testNativeMuteRetainsLevelAndVolumeSliderWorksWhileStopped() async throws {
        let suite = "zihusic.route-tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = DeviceStub(id: "native-mute", volume: 0.5, canMute: true)
        let context = ContextStub()
        context.outputDevices = [device]
        let routing = AirPlayRouting(context: context, defaults: defaults, startsAutomatically: false)
        routing.refresh()
        try await waitUntil(routing) { routing.speakers.count == 2 }
        try await waitUntil(routing) { device.isMuted }
        XCTAssertFalse(routing.hasPlayingRemoteOutputs)
        routing.setVolume(0.3, id: device.deviceID)
        try await waitUntil(routing) { abs(device.volume - 0.3) < 0.001 }
        XCTAssertTrue(device.isMuted)
        routing.setPlaybackEnabled(true, id: device.deviceID)
        try await waitUntil(routing) { !device.isMuted }
        XCTAssertEqual(device.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(context.identifiers, [device.deviceID])
        XCTAssertEqual(context.additions, 0)
    }

    @MainActor
    private func waitUntil(_ routing: AirPlayRouting, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !condition(), Date() < deadline {
            routing.refresh()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "Routing operation timed out", file: file, line: line)
    }
}

private final class DeviceStub: NSObject {
    @objc let deviceID: String
    @objc var deviceName: String { deviceID }
    @objc let canSetVolume = true
    @objc let canMute: Bool
    private let lock = NSLock()
    private var level: Float
    private var muted = false
    @objc dynamic var volume: Float {
        get { lock.withLock { level } }
        set { lock.withLock { level = newValue } }
    }
    @objc var isMuted: Bool { lock.withLock { muted } }
    @objc func setMuted(_ value: Bool) { lock.withLock { muted = value } }
    init(id: String, volume: Float, canMute: Bool = false) {
        deviceID = id; level = volume; self.canMute = canMute
    }
}

private final class ContextStub: NSObject {
    private let lock = NSLock()
    private var devices: [NSObject] = []
    private var count = 0
    var additions: Int { lock.withLock { count } }
    var identifiers: Set<String> { Set(outputDevices.compactMap { ($0 as? DeviceStub)?.deviceID }) }
    @objc dynamic var outputDevices: [NSObject] {
        get { lock.withLock { devices } }
        set { lock.withLock { devices = newValue } }
    }
    @objc func addOutputDevice(_ device: NSObject) {
        lock.withLock {
            count += 1
            if !devices.contains(where: { $0 === device }) { devices.append(device) }
        }
    }
}

private final class DiscoveryStub: NSObject {
    @objc let availableOutputDevices: [NSObject]
    init(devices: [NSObject]) { availableOutputDevices = devices }
}
