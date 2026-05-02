import SwiftUI

private struct TrackEditDraft: Equatable {
    var title = ""
    var artist = ""
    var album = ""
}

struct TrackDetailView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    @State private var draft = TrackEditDraft()
    @State private var lyrics: [LyricsLine] = []

    var body: some View {
        Group {
            if let track = library.selectedTrack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(for: track)
                        Divider()
                        metadataEditor(for: track)
                        LyricsView(lines: lyrics, currentTime: currentLyricTime(for: track))
                    }
                    .padding(24)
                    .frame(maxWidth: 980, alignment: .leading)
                }
                .onAppear { load(track) }
                .onChange(of: track.id) { _ in load(track) }
                .navigationTitle(track.displayTitle)
            } else {
                ContentUnavailableView("选择一首音乐", systemImage: "music.note", description: Text("从左侧资料库选择或导入本地文件夹。"))
            }
        }
    }

    private func header(for track: MusicTrack) -> some View {
        HStack(alignment: .top, spacing: 24) {
            ArtworkView(url: library.artworkURL(for: track))

            VStack(alignment: .leading, spacing: 12) {
                Text(track.displayTitle)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(2)
                Text(track.displayArtist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(track.displayAlbum)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(DisplayFormatters.technicalSummary(for: track), systemImage: "waveform")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        player.play(track)
                    } label: {
                        Label("播放", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        library.chooseArtwork(for: track)
                    } label: {
                        Label("封面", systemImage: "photo")
                    }

                    Button {
                        revealInFinder(track)
                    } label: {
                        Label("定位", systemImage: "folder")
                    }
                }
            }
        }
    }

    private func metadataEditor(for track: MusicTrack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("音乐信息")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("名称")
                        .foregroundStyle(.secondary)
                    TextField("音乐名", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }
                GridRow {
                    Text("作者")
                        .foregroundStyle(.secondary)
                    TextField("作者", text: $draft.artist)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }
                GridRow {
                    Text("专辑")
                        .foregroundStyle(.secondary)
                    TextField("专辑", text: $draft.album)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }
            }

            HStack(spacing: 10) {
                Button {
                    saveDraft(track)
                } label: {
                    Label("保存到资料库", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    var updated = track
                    updated.title = draft.title
                    updated.artist = draft.artist
                    updated.album = draft.album
                    library.updateTrack(updated)
                    Task { await library.writeTags(for: updated) }
                } label: {
                    Label("写入音频标签", systemImage: "square.and.pencil")
                }

                if !library.statusMessage.isEmpty {
                    Text(library.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(track.filePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func load(_ track: MusicTrack) {
        draft = TrackEditDraft(title: track.title, artist: track.artist, album: track.album)
        lyrics = library.lyrics(for: track)
    }

    private func saveDraft(_ track: MusicTrack) {
        var updated = track
        updated.title = draft.title
        updated.artist = draft.artist
        updated.album = draft.album
        library.updateTrack(updated)
    }

    private func currentLyricTime(for track: MusicTrack) -> TimeInterval {
        player.currentTrack?.id == track.id ? player.currentTime : 0
    }

    private func revealInFinder(_ track: MusicTrack) {
        NSWorkspace.shared.activateFileViewerSelecting([track.fileURL])
    }
}
