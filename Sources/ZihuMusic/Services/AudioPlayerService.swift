import AVFoundation
import Foundation

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published var currentTrack: MusicTrack?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 0.85 {
        didSet { player?.volume = Float(volume) }
    }
    @Published var errorMessage: String?

    var onFinished: (() -> Void)?

    var preciseCurrentTime: TimeInterval {
        guard let player else { return currentTime }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : currentTime
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func play(_ track: MusicTrack) {
        stopObservers()
        currentTrack = track
        currentTime = 0
        duration = track.duration

        let item = AVPlayerItem(url: track.fileURL)
        let player = AVPlayer(playerItem: item)
        player.volume = Float(volume)
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
                if let itemDuration = self?.player?.currentItem?.duration {
                    let seconds = CMTimeGetSeconds(itemDuration)
                    if seconds.isFinite && seconds > 0 {
                        self?.duration = seconds
                    }
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.onFinished?()
            }
        }

        player.play()
        isPlaying = true
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentTrack = nil
        currentTime = 0
        stopObservers()
    }

    private func stopObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
