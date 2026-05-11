import AVFoundation
import Foundation

@MainActor
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentTrack: MusicTrack?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 0.85 {
        didSet { audioPlayer?.volume = Float(volume) }
    }
    @Published var errorMessage: String?

    var onFinished: (() -> Void)?

    var boundedCurrentTime: TimeInterval {
        clampedTime(currentTime)
    }

    var boundedDuration: TimeInterval {
        Self.validDuration(duration)
    }

    var preciseCurrentTime: TimeInterval {
        guard let audioPlayer else { return clampedTime(currentTime) }
        return clampedTime(audioPlayer.currentTime)
    }

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    func play(_ track: MusicTrack) {
        stopProgressTimer()
        audioPlayer?.stop()
        currentTrack = track
        currentTime = 0
        duration = Self.validDuration(track.duration)

        do {
            let player = try AVAudioPlayer(contentsOf: track.fileURL)
            player.delegate = self
            player.volume = Float(volume)
            player.prepareToPlay()

            audioPlayer = player
            duration = Self.validDuration(player.duration) > 0
                ? Self.validDuration(player.duration)
                : Self.validDuration(track.duration)
            errorMessage = nil

            player.play()
            isPlaying = true
            startProgressTimer()
        } catch {
            audioPlayer = nil
            isPlaying = false
            errorMessage = "无法播放：\(error.localizedDescription)"
        }
    }

    func togglePlayback() {
        guard let audioPlayer else { return }
        if isPlaying {
            audioPlayer.pause()
            syncCurrentTimeFromPlayer()
            stopProgressTimer()
            isPlaying = false
        } else {
            audioPlayer.play()
            startProgressTimer()
            isPlaying = true
        }
    }

    func pause() {
        audioPlayer?.pause()
        syncCurrentTimeFromPlayer()
        stopProgressTimer()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        let target = clampedTime(time)
        guard let audioPlayer else {
            currentTime = target
            return
        }
        audioPlayer.currentTime = target
        currentTime = target
        syncCurrentTimeFromPlayer()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTrack = nil
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            currentTime = boundedDuration
            isPlaying = false
            stopProgressTimer()
            onFinished?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error.map { "播放解码失败：\($0.localizedDescription)" }
        Task { @MainActor [weak self] in
            guard let self else { return }
            isPlaying = false
            stopProgressTimer()
            if let message {
                errorMessage = message
            }
        }
    }

    private func clampedTime(_ time: TimeInterval) -> TimeInterval {
        let value = time.isFinite ? max(0, time) : 0
        let upperBound = boundedDuration
        guard upperBound > 0 else { return value }
        return min(value, upperBound)
    }

    private static func validDuration(_ time: TimeInterval) -> TimeInterval {
        time.isFinite && time > 0 ? time : 0
    }

    private func syncCurrentTimeFromPlayer() {
        guard let audioPlayer else {
            currentTime = clampedTime(currentTime)
            return
        }
        let playerDuration = Self.validDuration(audioPlayer.duration)
        if playerDuration > 0 {
            duration = playerDuration
        }
        currentTime = clampedTime(audioPlayer.currentTime)
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncCurrentTimeFromPlayer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
