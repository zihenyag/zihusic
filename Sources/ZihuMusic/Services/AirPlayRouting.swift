import AVFoundation
import CoreAudio
import ObjectiveC

/// Opaque native handles cross queues; route IPC never blocks the main actor.
private struct RoutingTransfer<Value>: @unchecked Sendable {
    let value: Value
}

/// Guarded macOS audio-group SPI. Connection membership and playback preference
/// are deliberately independent: a checkbox never removes an output device.
@MainActor
final class AirPlayRouting: ObservableObject {
    struct Speaker: Identifiable, Equatable {
        let id: String
        let name: String
        let isLocal: Bool
        let isPlaying: Bool
        let isConnected: Bool
        let volume: Double
        let canSetVolume: Bool
        let canControlPlayback: Bool
    }

    private struct DeviceInfo {
        let name: String
        var volume: Double
        var canSetVolume: Bool
        var canMute: Bool
        let isMuted: Bool
    }

    @Published private(set) var speakers: [Speaker] = []
    @Published private(set) var pendingIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var enrollmentNeedsPermission = false
    @Published private(set) var isEnrolling = false
    @Published private(set) var localDelay: TimeInterval
    static let localID = "zihusic.local-output"
    let context: NSObject?
    let localDeviceUID: String?
    private let localName: String
    private let defaults: UserDefaults
    private var playback: [String: SpeakerPlaybackState]
    private var controlsRevision: UInt64 = 0
    private var knownDevices: [String: NSObject] = [:]
    private var deviceInfo: [String: DeviceInfo] = [:]
    private var selection = AirPlaySelection()
    private var retryAfter: [String: Date] = [:]
    private var outputSignature = ""
    private var isMonitoring = false
    private var monitoringRevision: UInt64 = 0
    private let detector = AVRouteDetector()
    private var discovery: NSObject?
    private var timer: Timer?
    private var contextObserver: NSObjectProtocol?
    private let routingQueue = DispatchQueue(label: "com.local.zihusic.airplay.routes", qos: .userInitiated)
    // Volume/mute commands must not wait behind device discovery/connection IPC.
    private let controlsQueue = DispatchQueue(label: "com.local.zihusic.airplay.levels", qos: .userInitiated)
    private var refreshInFlight = false
    private var refreshCompletions: [() -> Void] = []
    private struct LevelTarget: Equatable {
        let device: ObjectIdentifier
        let playing: Bool
        let volume: Double
        let nativeMute: Bool
    }
    private var levelWrites: [String: DispatchWorkItem] = [:]
    private var levelTargets: [String: LevelTarget] = [:]

    var supportsGroups: Bool { context != nil }
    var hasRemoteOutputs: Bool { !selection.observed.isEmpty }
    var hasKnownReceivers: Bool { !knownDevices.isEmpty }
    var hasPlayingRemoteOutputs: Bool { selection.observed.contains { playback[$0]?.isPlaying == true } }
    var localEnabled: Bool { playback[Self.localID]?.isPlaying ?? true }
    var localVolume: Double { playback[Self.localID]?.volume ?? 1 }
    var onOutputsChanged: (() -> Void)?
    var onResynchronize: (() -> Void)?
    var onCheckEnrollment: (() -> Void)?
    func checkAutomaticEnrollment() { onCheckEnrollment?() }

    convenience init() {
        self.init(context: Self.makeAudioContext(), defaults: .standard, startsAutomatically: true)
    }

    /// Injection keeps regression tests independent of real speakers and routing.
    init(context: NSObject?, defaults: UserDefaults, startsAutomatically: Bool, initialDiscovery: NSObject? = nil) {
        self.context = context
        self.defaults = defaults
        discovery = initialDiscovery
        let local = Self.localAudioDevice()
        localDeviceUID = local.uid
        localName = Host.current().localizedName ?? local.name
        localDelay = min(max(defaults.double(forKey: "airplay.localDelay"), -3), 3)
        playback = defaults.data(forKey: "airplay.speakerPlayback")
            .flatMap { try? JSONDecoder().decode([String: SpeakerPlaybackState].self, from: $0) } ?? [:]
        // Every launch starts with this Mac audible; receiver sessions may join
        // silently. Keep saved levels, but never auto-enable external speakers.
        for id in Array(playback.keys) { playback[id]?.setPlaying(id == Self.localID) }
        if playback[Self.localID] == nil { playback[Self.localID] = SpeakerPlaybackState() }
        if let context {
            contextObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("AVOutputContextOutputDevicesDidChangeNotification"),
                object: context, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        publishSnapshot()
        if startsAutomatically {
            startMonitoring()
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Discovery stays active when the popover closes, including between songs.
    func startMonitoring() {
        guard supportsGroups, !isMonitoring else { return }
        isMonitoring = true
        detector.isRouteDetectionEnabled = true
        monitoringRevision &+= 1
        let revision = monitoringRevision
        routingQueue.async { [weak self] in
            let discovery = Self.discoverySession()
            if let discovery, discovery.responds(to: NSSelectorFromString("setDiscoveryMode:")) {
                discovery.setValue(2, forKey: "discoveryMode")
            }
            let session = RoutingTransfer(value: discovery)
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoring, self.monitoringRevision == revision else { return }
                self.discovery = session.value
                self.refresh()
            }
        }
        refresh()
    }

    private func tick() {
        if selection.expire() {
            errorMessage = "设备未响应，稍后会自动重试。"
            publishSnapshot()
        }
        refresh()
    }

    // The system menu is needed for first authorization on OSes which restrict
    // third-party enumeration. Already-known routes are joined automatically.
    func prepareToAddDevice() { startMonitoring() }
    func finishAddingDevice() { refresh() }

    func setPlaybackEnabled(_ enabled: Bool, id: String) {
        guard id == Self.localID || knownDevices[id] != nil else { return }
        var state = playback[id] ?? SpeakerPlaybackState(isPlaying: false, volume: deviceInfo[id]?.volume ?? 1)
        state.setPlaying(enabled)
        playback[id] = state
        controlsRevision &+= 1
        savePreferences()
        publishSnapshot()
        if id != Self.localID { writeLevel(id: id) }
    }

    func setVolume(_ volume: Double, id: String) {
        guard id == Self.localID || deviceInfo[id]?.canSetVolume == true else { return }
        var state = playback[id] ?? SpeakerPlaybackState(isPlaying: id == Self.localID)
        state.setVolume(volume)
        playback[id] = state
        controlsRevision &+= 1
        savePreferences()
        publishSnapshot()
        // A muted device's slider edits the level to restore, without unmuting.
        if id != Self.localID { writeLevel(id: id) }
    }

    /// Flush/re-anchor the shared timeline; preserve all receiver sessions.
    func resynchronize() { onResynchronize?() }
    func clearError() { errorMessage = nil }
    func setEnrollmentNeedsPermission(_ needed: Bool) { if enrollmentNeedsPermission != needed { enrollmentNeedsPermission = needed } }
    func setEnrolling(_ active: Bool) { if isEnrolling != active { isEnrolling = active } }
    func reportEnrollmentError(_ message: String) { errorMessage = message }

    func setLocalDelay(_ seconds: TimeInterval) {
        localDelay = min(max(seconds.isFinite ? seconds : 0, -3), 3)
        defaults.set(localDelay, forKey: "airplay.localDelay")
        publishSnapshot()
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(playback) {
            defaults.set(data, forKey: "airplay.speakerPlayback")
        }
    }

    private func writeLevel(id: String) {
        guard selection.observed.contains(id), let device = knownDevices[id],
              let info = deviceInfo[id], let state = playback[id] else { return }
        let target = LevelTarget(device: ObjectIdentifier(device), playing: state.isPlaying,
                                 volume: state.volume, nativeMute: info.canMute)
        // Repeated route notifications must not keep postponing the same mute.
        guard levelTargets[id] != target else { return }
        levelTargets[id] = target
        let output = RoutingTransfer(value: device)
        levelWrites[id]?.cancel()
        let write = DispatchWorkItem { [weak self] in
            if info.canMute, output.value.responds(to: NSSelectorFromString("setMuted:")) {
                // Set mute before the level to avoid an audible burst on stop.
                if !state.isPlaying { output.value.setValue(true, forKey: "muted") }
                if info.canSetVolume, output.value.responds(to: NSSelectorFromString("setVolume:")) {
                    output.value.setValue(Float(state.volume), forKey: "volume")
                }
                if state.isPlaying { output.value.setValue(false, forKey: "muted") }
            } else if info.canSetVolume, output.value.responds(to: NSSelectorFromString("setVolume:")) {
                output.value.setValue(Float(state.volumeWhenPlaying), forKey: "volume")
            }
            Task { @MainActor [weak self] in
                guard let self, self.levelTargets[id] == target else { return }
                self.levelTargets[id] = nil
                self.levelWrites[id] = nil
            }
        }
        levelWrites[id] = write
        controlsQueue.asyncAfter(deadline: .now() + 0.025, execute: write)
    }

    /// Add-only reconciliation. Playback toggles never call any routing API.
    private func joinAvailableDevices() {
        guard selection.pending.isEmpty, let context else { return }
        let now = Date()
        let missing = Set(knownDevices.keys).subtracting(selection.observed)
            .filter { now >= (retryAfter[$0] ?? .distantPast) }
        guard !missing.isEmpty else { return }
        let desired = selection.observed.union(missing)
        selection.request(desired)
        for id in missing { retryAfter[id] = now.addingTimeInterval(30) }
        publishSnapshot()
        let request = RoutingTransfer(value: (context, missing.compactMap { knownDevices[$0] }))
        routingQueue.async { [weak self] in
            let (context, devices) = request.value
            let add = NSSelectorFromString("addOutputDevice:")
            if context.responds(to: add) {
                for device in devices { context.perform(add, with: device) }
            }
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Main actor receives immutable snapshots, and never waits for route IPC.
    func refresh(after completion: (() -> Void)? = nil) {
        if let completion { refreshCompletions.append(completion) }
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let request = RoutingTransfer(value: (context, discovery, knownDevices, deviceInfo))
        let revision = selection.revision
        let levelsRevision = controlsRevision
        routingQueue.async { [weak self] in
            let (context, discovery, known, previousInfo) = request.value
            let connected = Self.objects(context, "outputDevices")
            var devices = known
            for device in Self.objects(discovery, "availableOutputDevices") + connected {
                if let id = Self.identifier(device) { devices[id] = device }
            }
            var info: [String: DeviceInfo] = [:]
            for (id, device) in devices {
                guard let name = Self.value(device, "deviceName") as? String ?? Self.value(device, "name") as? String else { continue }
                let previous = previousInfo[id]
                let raw = (Self.value(device, "volume") as? NSNumber)?.doubleValue
                let volume = raw.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? previous?.volume ?? 1
                info[id] = DeviceInfo(name: name, volume: volume,
                    canSetVolume: previous?.canSetVolume == true || Self.bool(device, "canSetVolume"),
                    canMute: previous?.canMute == true || Self.bool(device, "canMute"),
                    isMuted: Self.bool(device, "isMuted"))
            }
            let snapshot = RoutingTransfer(value: (Set(connected.compactMap(Self.identifier)), devices, info))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshInFlight = false
                let (actual, devices, info) = snapshot.value
                let previousInfo = self.deviceInfo
                self.knownDevices.merge(devices, uniquingKeysWith: { _, new in new })
                self.deviceInfo.merge(info, uniquingKeysWith: { _, new in new })
                let previous = self.selection.observed
                let accepted = self.selection.receive(actual, revision: revision)
                let joined = accepted ? actual.subtracting(previous) : []
                for id in joined { self.retryAfter[id] = nil }
                for (id, item) in info {
                    if self.playback[id] == nil {
                        self.playback[id] = SpeakerPlaybackState(isPlaying: false, volume: item.volume)
                    } else if joined.contains(id) {
                        // Reapply the preference before accepting any reconnect echo.
                        if var state = self.playback[id] {
                            state.setPlaying(state.isPlaying)
                            self.playback[id] = state
                        }
                    } else if self.controlsRevision == levelsRevision, actual.contains(id) {
                        self.playback[id]?.observeVolume(item.volume)
                    }
                }
                for (id, item) in info where actual.contains(id) {
                    let gainedControl = (item.canSetVolume && previousInfo[id]?.canSetVolume != true)
                        || (item.canMute && previousInfo[id]?.canMute != true)
                    let shouldMute = self.playback[id]?.isPlaying == false
                        && (item.canMute ? !item.isMuted : item.canSetVolume && item.volume > 0.001)
                    if joined.contains(id) || gainedControl || shouldMute { self.writeLevel(id: id) }
                }
                if accepted, !actual.isEmpty, Set(self.knownDevices.keys).isSubset(of: actual) {
                    self.errorMessage = nil
                }
                self.publishSnapshot()
                if accepted {
                    let completions = self.refreshCompletions
                    self.refreshCompletions = []
                    completions.forEach { $0() }
                    self.joinAvailableDevices()
                } else {
                    self.refresh()
                }
            }
        }
    }

    private func publishSnapshot() {
        let actual = selection.observed
        pendingIDs = selection.pending
        var updated: [Speaker] = deviceInfo.map { id, info -> Speaker in
            let state = playback[id] ?? SpeakerPlaybackState(isPlaying: false, volume: info.volume)
            return Speaker(id: id, name: info.name, isLocal: false,
                isPlaying: state.isPlaying, isConnected: actual.contains(id),
                volume: state.volume, canSetVolume: info.canSetVolume,
                canControlPlayback: info.canMute || info.canSetVolume)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        updated.insert(Speaker(id: Self.localID, name: localName, isLocal: true,
            isPlaying: localEnabled, isConnected: true, volume: localVolume, canSetVolume: true, canControlPlayback: true), at: 0)
        if updated != speakers { speakers = updated }
        let signature = actual.sorted().joined(separator: ",") + "|\(localEnabled)|\(localVolume)|\(localDelay)|\(hasPlayingRemoteOutputs)"
        if signature != outputSignature {
            outputSignature = signature
            onOutputsChanged?()
        }
    }

    private static func localAudioDevice() -> (uid: String?, name: String) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return (nil, "本机扬声器")
        }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = devices.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return (nil, "本机扬声器") }
        for device in devices {
            var transport: UInt32 = 0
            var bytes = UInt32(MemoryLayout<UInt32>.size)
            address.mSelector = kAudioDevicePropertyTransportType
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBuiltIn else { continue }
            address.mSelector = kAudioDevicePropertyStreams
            address.mScope = kAudioDevicePropertyScopeOutput
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }
            return (audioString(device, kAudioDevicePropertyDeviceUID), audioString(device, kAudioObjectPropertyName) ?? "本机扬声器")
        }
        return (nil, "本机扬声器")
    }

    private static func audioString(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value as String? : nil
    }

    private nonisolated static func identifier(_ device: NSObject) -> String? {
        value(device, "deviceID") as? String ?? value(device, "ID") as? String
    }

    private static func makeAudioContext() -> NSObject? {
        guard let context = classObject("AVOutputContext", "iTunesAudioContext"),
              bool(context, "supportsMultipleOutputDevices"),
              context.responds(to: NSSelectorFromString("outputDevices")),
              context.responds(to: NSSelectorFromString("setOutputDevices:")) else { return nil }
        return context
    }

    private nonisolated static func discoverySession() -> NSObject? {
        guard let cls = NSClassFromString("AVOutputDeviceDiscoverySession"),
              let allocMethod = class_getClassMethod(cls, NSSelectorFromString("alloc")),
              let initMethod = class_getInstanceMethod(cls, NSSelectorFromString("initWithDeviceFeatures:")) else { return nil }
        typealias Allocate = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, UInt) -> UnsafeMutableRawPointer?
        guard let allocated = unsafeBitCast(method_getImplementation(allocMethod), to: Allocate.self)(cls, NSSelectorFromString("alloc")),
              let initialized = unsafeBitCast(method_getImplementation(initMethod), to: Initialize.self)(allocated, NSSelectorFromString("initWithDeviceFeatures:"), 1) else { return nil }
        return Unmanaged<NSObject>.fromOpaque(initialized).takeRetainedValue()
    }

    private static func classObject(_ name: String, _ methodName: String, retained: Bool = false) -> NSObject? {
        let selector = NSSelectorFromString(methodName)
        guard let cls = NSClassFromString(name), let method = class_getClassMethod(cls, selector),
              method_getNumberOfArguments(method) == 2,
              let encoding = method_getTypeEncoding(method), encoding.pointee == 64 else { return nil }
        typealias Factory = @convention(c) (AnyClass, Selector) -> Unmanaged<NSObject>?
        let result = unsafeBitCast(method_getImplementation(method), to: Factory.self)(cls, selector)
        return retained ? result?.takeRetainedValue() : result?.takeUnretainedValue()
    }

    private nonisolated static func value(_ object: NSObject?, _ key: String) -> Any? {
        guard let object, object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }

    private nonisolated static func bool(_ object: NSObject, _ key: String) -> Bool {
        (value(object, key) as? NSNumber)?.boolValue ?? false
    }

    private nonisolated static func objects(_ object: NSObject?, _ key: String) -> [NSObject] {
        value(object, key) as? [NSObject] ?? []
    }

    deinit {
        timer?.invalidate()
        levelWrites.values.forEach { $0.cancel() }
        if let contextObserver { NotificationCenter.default.removeObserver(contextObserver) }
        if let discovery, discovery.responds(to: NSSelectorFromString("setDiscoveryMode:")) {
            let session = RoutingTransfer(value: discovery)
            routingQueue.async { session.value.setValue(0, forKey: "discoveryMode") }
        }
    }
}
