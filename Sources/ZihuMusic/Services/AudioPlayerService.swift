import AVFoundation
import Foundation

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    @Published var currentTrack: MusicTrack?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 1 {
        didSet { configureOutputs() }
    }
    @Published var errorMessage: String?

    // Keep the route context and both transports alive across track changes.
    let routingPlayer = AVPlayer()
    let airPlay: AirPlayRouting
    var airPlayContext: NSObject? { airPlay.context }
    var onFinished: (() -> Void)?

    var boundedCurrentTime: TimeInterval { clampedTime(currentTime) }
    var boundedDuration: TimeInterval { Self.validDuration(duration) }
    var preciseCurrentTime: TimeInterval {
        pendingSeek ?? clampedTime(usingGroupedOutput ? groupedOutput.currentTime : routingPlayer.currentTime().seconds)
    }
    var isActuallyPlaying: Bool {
        isPlaying && pendingSeek == nil && (usingGroupedOutput ? groupedOutput.isPlaying : routingPlayer.timeControlStatus == .playing)
    }

    private let groupedOutput: GroupedAudioOutput
    private var usingGroupedOutput = false
    private var progressObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var pendingSeek: TimeInterval?
    private var seekRevision = 0

    override convenience init() {
        self.init(airPlay: AirPlayRouting())
    }

    init(airPlay: AirPlayRouting) {
        self.airPlay = airPlay
        groupedOutput = GroupedAudioOutput(context: airPlay.context, deviceUID: airPlay.localDeviceUID)
        super.init()
        routingPlayer.audioOutputDeviceUniqueID = airPlay.localDeviceUID
        routingPlayer.allowsExternalPlayback = false
        routingPlayer.volume = Float(volume)
        airPlay.onOutputsChanged = { [weak self] in self?.outputsChanged() }
        airPlay.onResynchronize = { [weak self] in
            guard let self, self.usingGroupedOutput else { return }
            self.groupedOutput.seek(to: self.preciseCurrentTime)
        }
        groupedOutput.onProgress = { [weak self] in
            guard let self, self.usingGroupedOutput else { return }
            self.syncCurrentTimeFromPlayer()
        }
        groupedOutput.onFinished = { [weak self] in
            guard let self, self.usingGroupedOutput else { return }
            self.currentTime = self.boundedDuration
            self.isPlaying = false
            self.onFinished?()
        }
        groupedOutput.onError = { [weak self] error in
            guard let self, self.usingGroupedOutput else { return }
            self.fail(error)
        }
        progressObserver = routingPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncCurrentTimeFromPlayer() }
        }
    }

    func play(_ track: MusicTrack) {
        removeItemObservers()
        routingPlayer.pause()
        groupedOutput.reset()
        seekRevision += 1
        pendingSeek = nil
        currentTrack = track
        currentTime = 0
        duration = Self.validDuration(track.duration)
        errorMessage = nil
        usingGroupedOutput = airPlay.hasRemoteOutputs
        let item = AVPlayerItem(url: track.fileURL)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.routingPlayer.currentItem === item, !self.usingGroupedOutput else { return }
                if item.status == .failed { self.fail(item.error) }
                else if item.status == .readyToPlay { self.syncCurrentTimeFromPlayer() }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.routingPlayer.currentItem === item, !self.usingGroupedOutput else { return }
                self.currentTime = self.boundedDuration
                self.isPlaying = false
                self.onFinished?()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self, self.routingPlayer.currentItem === item, !self.usingGroupedOutput else { return }
                self.fail(error)
            }
        }
        routingPlayer.replaceCurrentItem(with: item)
        configureOutputs()
        isPlaying = true
        if usingGroupedOutput { groupedOutput.load(track.fileURL, at: 0, playing: true) }
        else { routingPlayer.play() }
    }

    func togglePlayback() {
        guard let track = currentTrack else { return }
        if isPlaying { pause(); return }
        if errorMessage != nil {
            play(track)
            return
        }
        errorMessage = nil
        isPlaying = true
        if boundedDuration > 0, preciseCurrentTime >= boundedDuration - 0.05 { seek(to: 0) }
        if usingGroupedOutput { groupedOutput.play() }
        else { routingPlayer.play() }
    }

    func pause() {
        isPlaying = false
        routingPlayer.pause()
        groupedOutput.pause()
        syncCurrentTimeFromPlayer()
    }

    func seek(to time: TimeInterval) {
        let target = clampedTime(time)
        currentTime = target
        seekRevision += 1
        if usingGroupedOutput {
            pendingSeek = nil
            groupedOutput.seek(to: target)
            return
        }
        guard routingPlayer.currentItem != nil else { return }
        let revision = seekRevision
        pendingSeek = target
        routingPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 60_000),
            toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekRevision == revision, !self.usingGroupedOutput else { return }
                self.pendingSeek = nil
                self.syncCurrentTimeFromPlayer()
            }
        }
    }

    func stop() {
        routingPlayer.pause()
        groupedOutput.reset()
        removeItemObservers()
        routingPlayer.replaceCurrentItem(with: nil)
        seekRevision += 1
        pendingSeek = nil
        isPlaying = false
        currentTrack = nil
        currentTime = 0
        duration = 0
    }

    private func outputsChanged() {
        configureOutputs()
        guard let track = currentTrack else { return }
        let remote = airPlay.hasRemoteOutputs
        guard remote != usingGroupedOutput else { return }
        let position = preciseCurrentTime
        seekRevision += 1
        pendingSeek = nil
        usingGroupedOutput = remote
        if remote {
            routingPlayer.pause()
            groupedOutput.load(track.fileURL, at: position, playing: isPlaying)
        } else {
            groupedOutput.reset()
            seek(to: position)
            if isPlaying { routingPlayer.play() }
        }
    }

    private func configureOutputs() {
        routingPlayer.isMuted = !airPlay.localEnabled
        routingPlayer.volume = Float(min(max(volume * airPlay.localVolume, 0), 1))
        groupedOutput.setOutputs(localEnabled: airPlay.localEnabled,
            localVolume: airPlay.localVolume, masterVolume: volume, delay: airPlay.localDelay,
            remoteEnabled: airPlay.hasPlayingRemoteOutputs)
    }

    private func removeItemObservers() {
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }

    private func fail(_ error: Error?) {
        routingPlayer.pause()
        groupedOutput.pause()
        isPlaying = false
        errorMessage = "无法播放：\(error?.localizedDescription ?? "音频解码失败")"
    }

    private func clampedTime(_ time: TimeInterval) -> TimeInterval {
        let value = time.isFinite ? max(0, time) : 0
        return boundedDuration > 0 ? min(value, boundedDuration) : value
    }

    private static func validDuration(_ time: TimeInterval) -> TimeInterval {
        time.isFinite && time > 0 ? time : 0
    }

    private func syncCurrentTimeFromPlayer() {
        if usingGroupedOutput {
            if groupedOutput.duration > 0 { duration = groupedOutput.duration }
        } else if let item = routingPlayer.currentItem {
            let itemDuration = Self.validDuration(item.duration.seconds)
            if itemDuration > 0 { duration = itemDuration }
        }
        currentTime = preciseCurrentTime
    }

    deinit {
        if let progressObserver { routingPlayer.removeTimeObserver(progressObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}
