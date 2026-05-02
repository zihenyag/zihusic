import SwiftUI

struct DownloadView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var library: MusicLibraryStore
    @State private var webURL = URL(string: "https://flac.music.hi.cn/")!

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    nativeSearch
                    directDownload
                    Divider()
                    browser
                }
                .padding(24)
            }
        }
        .navigationTitle("下载")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("音乐下载")
                .font(.largeTitle.weight(.semibold))
            Text("下载文件保存到本地音乐文件夹，应用只缓存曲目信息和封面，不复制音乐本体。")
                .foregroundStyle(.secondary)
        }
    }

    private var nativeSearch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("搜索歌曲、作者", text: $downloads.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await downloads.search() }
                    }

                Button {
                    Task { await downloads.search() }
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloads.isSearching)

                Button {
                    downloads.chooseTargetFolder()
                } label: {
                    Label("保存位置", systemImage: "folder")
                }
            }

            if !downloads.statusMessage.isEmpty {
                Text(downloads.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !downloads.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(downloads.results) { result in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text([result.artist, result.album, result.format.uppercased(), result.sizeDescription]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Task {
                                    if let file = await downloads.download(result) {
                                        await library.importFile(file, source: .downloaded)
                                    }
                                }
                            } label: {
                                Label("下载", systemImage: "arrow.down")
                            }
                            .disabled(downloads.isDownloading)
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var directDownload: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("直链下载")
                .font(.headline)
            HStack(spacing: 10) {
                TextField("https://.../song.flac", text: $downloads.directURLText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        if let file = await downloads.downloadDirectURL() {
                            await library.importFile(file, source: .downloaded)
                        }
                    }
                } label: {
                    Label("下载直链", systemImage: "link.badge.plus")
                }
                .disabled(downloads.isDownloading)
            }
            Text(downloads.targetFolder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("站点浏览")
                    .font(.headline)
                Spacer()
                Button {
                    let encoded = downloads.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    webURL = URL(string: "https://flac.music.hi.cn/?s=\(encoded)") ?? URL(string: "https://flac.music.hi.cn/")!
                } label: {
                    Label("用网页搜索", systemImage: "safari")
                }
            }

            DownloadBrowserView(url: webURL) { url in
                downloads.directURLText = url.absoluteString
                Task {
                    if let file = await downloads.downloadDirectURL() {
                        await library.importFile(file, source: .downloaded)
                    }
                }
            }
            .frame(minHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator, lineWidth: 1)
            )
        }
    }
}
