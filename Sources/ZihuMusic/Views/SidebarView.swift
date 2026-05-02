import SwiftUI

enum MainPage: String, CaseIterable, Identifiable {
    case library = "资料库"
    case downloads = "下载"

    var id: String { rawValue }
}

struct SidebarView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @Binding var page: MainPage

    var body: some View {
        VStack(spacing: 12) {
            Picker("视图", selection: $page) {
                ForEach(MainPage.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)

            switch page {
            case .library:
                libraryList
            case .downloads:
                downloadSummary
            }
        }
    }

    private var libraryList: some View {
        List(selection: $library.selectedTrackID) {
            Section {
                ForEach(library.filteredTracks) { track in
                    TrackSidebarRow(track: track)
                    .tag(track.id)
                    .contextMenu {
                        Button("播放") {
                            library.selectedTrackID = track.id
                        }
                    }
                }
            } header: {
                Text("\(library.filteredTracks.count) 首音乐")
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $library.searchText, placement: .sidebar, prompt: "搜索音乐、作者、专辑")
        .overlay {
            if library.tracks.isEmpty && !library.isImporting {
                ContentUnavailableView("没有音乐", systemImage: "music.note.list", description: Text("导入文件夹后会在这里显示。"))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await library.chooseAndImportFolder() }
                } label: {
                    Label("导入文件夹", systemImage: "folder.badge.plus")
                }

                Button {
                    Task { await library.importDefaultFolder() }
                } label: {
                    Label("扫描默认文件夹", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var downloadSummary: some View {
        VStack {
            VStack(alignment: .leading, spacing: 14) {
                Label("下载中心", systemImage: "arrow.down.circle")
                    .font(.headline)
                Text("搜索 flac.music.hi.cn，下载到本地文件夹后自动加入资料库。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("默认保存位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppDirectories.defaultMusicFolder.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            .padding(16)
            Spacer()
        }
    }
}

private struct TrackSidebarRow: View {
    let track: MusicTrack

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: track.isAvailable ? "music.note" : "exclamationmark.triangle")
                .foregroundColor(track.isAvailable ? .secondary : .orange)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
