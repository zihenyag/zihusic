import AVFoundation
import ObjectiveC

/// Owns one packet source and one remote-led timeline. UI methods only submit
/// work; decoding, buffer operations and AirPlay negotiation use the audio queue.
@MainActor
final class GroupedAudioOutput {
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isReady = false
    private(set) var isPlaying = false
    var onProgress: (() -> Void)?
    var onFinished: (() -> Void)?
    var onError: ((Error) -> Void)?
    private let context: NSObject?
    private let deviceUID: String?
    private var worker: GroupedAudioWorker?
    private var preparation: Task<Void, Never>?
    private var prepared: AirPlayPreparedAsset?
    private var revision: UInt64 = 0
    private var wantsPlayback = false
    private var remoteEnabled = true
    private var localEnabled = true
    private var localVolume: Double = 1
    private var masterVolume: Double = 1
    private var localDelay: Double = 0

    init(context: NSObject?, deviceUID: String?) {
        self.context = context
        self.deviceUID = deviceUID
    }

    func load(_ url: URL, at time: Double, playing: Bool) {
        reset()
        currentTime = max(0, time)
        wantsPlayback = playing
        let revision = revision
        preparation = Task { [weak self] in
            do {
                let asset = try await AirPlayAudioAsset.prepare(url)
                try Task.checkCancellation()
                guard let self, self.revision == revision else { return }
                self.prepared = asset
                self.duration = asset.duration
                self.isReady = true
                self.startReader(at: self.currentTime)
            } catch is CancellationError {
            } catch {
                guard let self, self.revision == revision, !Task.isCancelled else { return }
                self.onError?(error)
            }
        }
    }

    func play() {
        wantsPlayback = true
        worker?.setPlaying(true)
    }

    func pause() {
        wantsPlayback = false
        isPlaying = false
        worker?.setPlaying(false)
    }

    func seek(to time: Double) {
        currentTime = min(max(time.isFinite ? time : 0, 0), duration > 0 ? duration : .greatestFiniteMagnitude)
        isPlaying = false
        if prepared != nil {
            revision &+= 1
            startReader(at: currentTime)
        }
        // During preparation, load's task remains valid and uses the new time.
        onProgress?()
    }

    func setOutputs(localEnabled: Bool, localVolume: Double, masterVolume: Double, delay: Double, remoteEnabled: Bool = true) {
        self.remoteEnabled = remoteEnabled
        self.localEnabled = localEnabled
        self.localVolume = localVolume
        self.masterVolume = masterVolume
        let changedDelay = abs(self.localDelay - delay) > 0.001
        self.localDelay = delay
        worker?.setLevels(localEnabled: localEnabled, local: localVolume, master: masterVolume, remoteEnabled: remoteEnabled)
        if changedDelay, prepared != nil { seek(to: currentTime) }
    }

    func reset() {
        preparation?.cancel()
        preparation = nil
        revision &+= 1
        worker?.stop(revision: revision)
        prepared = nil
        isReady = false
        isPlaying = false
        wantsPlayback = false
        currentTime = 0
        duration = 0
    }

    private func startReader(at time: Double) {
        guard let prepared else { return }
        if worker == nil {
            worker = GroupedAudioWorker(context: context, deviceUID: deviceUID) { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self, self.revision == snapshot.revision else { return }
                    self.currentTime = snapshot.time
                    self.isPlaying = self.wantsPlayback && snapshot.playing
                    if let error = snapshot.error { self.onError?(error); return }
                    self.onProgress?()
                    if snapshot.finished { self.wantsPlayback = false; self.onFinished?() }
                }
            }
        }
        worker?.setLevels(localEnabled: localEnabled, local: localVolume, master: masterVolume, remoteEnabled: remoteEnabled)
        worker?.load(prepared, at: time, playing: wantsPlayback, delay: localDelay, revision: revision)
    }

    deinit { preparation?.cancel(); worker?.shutdown() }
}

private struct GroupedAudioSnapshot: Sendable {
    let revision: UInt64
    let time: Double
    let playing: Bool
    var finished = false
    var error: AirPlayAudioAsset.AudioError?
}

/// Legacy AVFoundation objects are confined to queue, including their callbacks.
private final class GroupedAudioWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.local.zihusic.airplay.audio", qos: .userInitiated)
    private let remote = AVSampleBufferAudioRenderer()
    private let local = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let update: @Sendable (GroupedAudioSnapshot) -> Void
    private var timer: DispatchSourceTimer?
    private var reader: AVAssetReader?
    private var source: AVAssetReaderTrackOutput?
    private var buffers: [CMSampleBuffer] = []
    private var baseIndex = 0
    private var cursors = [0, 0]
    private var reachedEnd = false
    private var completed = false
    private var duration: Double = 0
    private var delay: Double = 0
    private var revision: UInt64 = 0
    private var loaded = false
    private var wantsPlayback = false
    private var pendingClockAnchor: (time: Double, requested: TimeInterval, previous: Double)?

    init(context: NSObject?, deviceUID: String?, update: @escaping @Sendable (GroupedAudioSnapshot) -> Void) {
        self.update = update
        let handle = OpaqueAudioHandle(value: context)
        queue.async { [self] in
            for renderer in [remote, local] {
                renderer.audioTimePitchAlgorithm = .varispeed
                let selector = NSSelectorFromString("setIsUnaccompaniedByVisuals:")
                if let method = class_getInstanceMethod(AVSampleBufferAudioRenderer.self, selector) {
                    typealias SetAudioOnly = @convention(c) (NSObject, Selector, Bool) -> Void
                    unsafeBitCast(method_getImplementation(method), to: SetAudioOnly.self)(renderer, selector, true)
                }
            }
            if let deviceUID { local.audioOutputDeviceUniqueID = deviceUID }
            if let context = handle.value, remote.responds(to: NSSelectorFromString("setOutputContext:")) {
                remote.setValue(context, forKey: "outputContext")
            }
            // The AirPlay renderer must own the initial device clock.
            synchronizer.addRenderer(remote)
            synchronizer.addRenderer(local)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func load(_ asset: AirPlayPreparedAsset, at time: Double, playing: Bool, delay: Double, revision: UInt64) {
        queue.async { [self] in
            clearBuffers()
            self.revision = revision
            self.duration = asset.duration
            self.delay = delay
            self.wantsPlayback = playing
            self.completed = false
            do {
                let reader = try AVAssetReader(asset: asset.asset)
                let output = AVAssetReaderTrackOutput(track: asset.track, outputSettings: nil)
                reader.add(output)
                let start = min(max(time, 0), asset.duration)
                reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 48_000),
                    duration: CMTime(seconds: max(0, asset.duration - start), preferredTimescale: 48_000))
                guard reader.startReading() else { throw reader.error ?? AirPlayAudioAsset.AudioError("无法读取音频") }
                self.reader = reader
                self.source = output
                loaded = true
                for renderer in [remote, local] {
                    renderer.requestMediaDataWhenReady(on: queue) { [weak self] in self?.pump() }
                }
                pump()
                // A fixed host deadline races the receiver's buffer handshake.
                // Let AirPlay confirm the anchor and move the shared timeline.
                pendingClockAnchor = (start, ProcessInfo.processInfo.systemUptime, synchronizer.currentTime().seconds)
                synchronizer.setRate(playing ? 1 : 0, time: CMTime(seconds: start, preferredTimescale: 48_000))
                tick()
            } catch { fail(error) }
        }
    }

    func setPlaying(_ playing: Bool) {
        queue.async { [self] in
            wantsPlayback = playing
            guard loaded, !completed else { return }
            synchronizer.setRate(playing ? 1 : 0, time: .invalid)
            tick()
        }
    }

    func setLevels(localEnabled: Bool, local: Double, master: Double, remoteEnabled: Bool) {
        queue.async { [self] in
            remote.isMuted = !remoteEnabled
            remote.volume = Float(min(max(master, 0), 1))
            self.local.volume = Float(min(max(local * master, 0), 1))
            self.local.isMuted = !localEnabled
        }
    }

    func stop(revision: UInt64) {
        queue.async { [self] in self.revision = revision; clearBuffers() }
    }

    func shutdown() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            clearBuffers()
        }
    }

    private func clearBuffers() {
        pendingClockAnchor = nil
        loaded = false
        wantsPlayback = false
        synchronizer.setRate(0, time: .invalid)
        remote.stopRequestingMediaData()
        local.stopRequestingMediaData()
        reader?.cancelReading()
        reader = nil
        source = nil
        remote.flush()
        local.flush()
        buffers = []
        baseIndex = 0
        cursors = [0, 0]
        reachedEnd = false
    }

    private func pump() {
        guard loaded, !completed else { return }
        for (index, renderer) in [remote, local].enumerated() {
            while renderer.isReadyForMoreMediaData {
                let offset = cursors[index] - baseIndex
                if offset == buffers.count {
                    guard !reachedEnd else { renderer.stopRequestingMediaData(); break }
                    // Bound fan-out memory if one renderer is still negotiating.
                    guard buffers.count < 16 else { break }
                    guard let buffer = source?.copyNextSampleBuffer() else {
                        reachedEnd = true
                        if reader?.status == .failed { fail(reader?.error); return }
                        renderer.stopRequestingMediaData()
                        break
                    }
                    buffers.append(buffer)
                }
                let buffer = buffers[offset]
                if index == 1, abs(delay) > 0.001 {
                    do { renderer.enqueue(try Self.offset(buffer, by: delay)) }
                    catch { fail(error); return }
                } else { renderer.enqueue(buffer) }
                cursors[index] += 1
                if renderer.status == .failed { fail(renderer.error); return }
            }
        }
        let consumed = min(cursors[0], cursors[1]) - baseIndex
        if consumed > 0 {
            buffers.removeFirst(consumed)
            baseIndex += consumed
        }
    }

    private func tick() {
        guard loaded, !completed else { return }
        pump()
        guard loaded else { return }
        let time = synchronizer.currentTime().seconds
        // setRate updates its rate synchronously but moves the rendering
        // timebase asynchronously. Never label the previous song's clock with
        // the new generation while AVFoundation is applying this anchor.
        if let anchor = pendingClockAnchor {
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - anchor.requested)
            let allowance = 0.15 + (wantsPlayback ? elapsed : 0)
            let unchangedOldClock = abs(anchor.previous - anchor.time) > 0.03 && abs(time - anchor.previous) < 0.001
            guard time.isFinite, !unchangedOldClock,
                  time >= anchor.time - 0.03, time <= anchor.time + allowance else { return }
            pendingClockAnchor = nil
        }
        let value = min(max(time.isFinite ? time : 0, 0), duration)
        if reachedEnd, time >= duration + max(0, delay), wantsPlayback {
            completed = true
            synchronizer.setRate(0, time: .invalid)
            update(GroupedAudioSnapshot(revision: revision, time: duration, playing: false, finished: true))
        } else {
            update(GroupedAudioSnapshot(revision: revision, time: value,
                playing: wantsPlayback && CMTimebaseGetEffectiveRate(synchronizer.timebase) > 0))
        }
    }

    private func fail(_ error: Error?) {
        let time = synchronizer.currentTime().seconds
        clearBuffers()
        update(GroupedAudioSnapshot(revision: revision, time: time.isFinite ? max(0, time) : 0, playing: false,
            error: AirPlayAudioAsset.AudioError(error?.localizedDescription ?? "AirPlay 音频播放失败")))
    }

    private static func offset(_ buffer: CMSampleBuffer, by seconds: Double) throws -> CMSampleBuffer {
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        var status = CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: nil)
        guard status == noErr else { throw AirPlayAudioAsset.AudioError("无法校准音频时间") }
        let delta = CMTime(seconds: seconds, preferredTimescale: 48_000)
        for index in timing.indices {
            timing[index].presentationTimeStamp = timing[index].presentationTimeStamp + delta
            if timing[index].decodeTimeStamp.isNumeric { timing[index].decodeTimeStamp = timing[index].decodeTimeStamp + delta }
        }
        var result: CMSampleBuffer?
        status = CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer,
            sampleTimingEntryCount: timing.count, sampleTimingArray: &timing, sampleBufferOut: &result)
        guard status == noErr, let result else { throw AirPlayAudioAsset.AudioError("无法校准音频时间") }
        return result
    }
}

private struct OpaqueAudioHandle: @unchecked Sendable {
    let value: NSObject?
}
