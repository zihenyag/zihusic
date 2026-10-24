import Foundation

/// Playback preference is independent of whether the AirPlay route is joined.
/// Muting never changes the saved volume or requests a route removal.
struct SpeakerPlaybackState: Equatable, Codable {
    private enum CodingKeys: CodingKey { case isPlaying, volume }
    private(set) var isPlaying: Bool
    private(set) var volume: Double
    private var keepVolumeUntil = Date.distantPast

    init(isPlaying: Bool = true, volume: Double = 1) {
        self.isPlaying = isPlaying
        self.volume = Self.level(volume)
    }

    mutating func setPlaying(_ playing: Bool, now: Date = Date()) {
        isPlaying = playing
        keepVolumeUntil = now.addingTimeInterval(5)
    }

    mutating func setVolume(_ volume: Double, now: Date = Date()) {
        self.volume = Self.level(volume)
        keepVolumeUntil = now.addingTimeInterval(5)
    }

    mutating func observeVolume(_ volume: Double, now: Date = Date()) {
        // A device without native mute is kept joined at zero gain. Its zero
        // read-back must not replace the preferred level used when resuming.
        guard isPlaying, now >= keepVolumeUntil else { return }
        self.volume = Self.level(volume)
    }

    var volumeWhenPlaying: Double { isPlaying ? volume : 0 }

    private static func level(_ value: Double) -> Double { min(max(value.isFinite ? value : 0, 0), 1) }
}
