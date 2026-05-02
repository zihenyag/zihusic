import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(url: player.currentTrack.flatMap { library.artworkURL(for: $0) }, size: 54)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentTrack?.displayTitle ?? "未播放")
                            .font(.headline)
                            .lineLimit(1)
                        Text(player.currentTrack?.displayArtist ?? "选择一首音乐开始播放")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(DisplayFormatters.time(player.currentTime)) / \(DisplayFormatters.time(player.duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
            }

            HStack(spacing: 8) {
                Button {
                    library.playPrevious(using: player)
                } label: {
                    Image(systemName: "backward.fill")
                }
                .help("上一首")

                Button {
                    if player.currentTrack == nil {
                        library.playSelected(using: player)
                    } else {
                        player.togglePlayback()
                    }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderedProminent)
                .help(player.isPlaying ? "暂停" : "播放")

                Button {
                    library.playNext(using: player)
                } label: {
                    Image(systemName: "forward.fill")
                }
                .help("下一首")
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 96)
            }
        }
        .padding(.horizontal, 16)
    }
}
