import AppKit
import Foundation

@MainActor
final class DownloadStore: ObservableObject {
    @Published var query = ""
    @Published var directURLText = ""
    @Published var results: [DownloadResult] = []
    @Published var targetFolder = AppDirectories.defaultMusicFolder.path
    @Published var isSearching = false
    @Published var isDownloading = false
    @Published var statusMessage = ""

    private let service = DownloadService()

    var targetFolderURL: URL {
        URL(fileURLWithPath: targetFolder, isDirectory: true)
    }

    func chooseTargetFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择下载保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = targetFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        targetFolder = url.path
    }

    func search() async {
        isSearching = true
        statusMessage = "正在搜索..."
        defer { isSearching = false }

        do {
            results = try await service.search(query: query)
            statusMessage = "找到 \(results.count) 个结果"
        } catch {
            results = []
            statusMessage = error.localizedDescription
        }
    }

    func download(_ result: DownloadResult) async -> URL? {
        isDownloading = true
        statusMessage = "正在下载 \(result.title)"
        defer { isDownloading = false }

        do {
            let name = result.title.isEmpty ? nil : "\(result.title).\(result.format)"
            let file = try await service.download(from: result.downloadURL, to: targetFolderURL, preferredName: name)
            statusMessage = "已下载：\(file.lastPathComponent)"
            return file
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func downloadDirectURL() async -> URL? {
        guard let url = URL(string: directURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = DownloadServiceError.invalidURL.localizedDescription
            return nil
        }

        isDownloading = true
        statusMessage = "正在下载直链..."
        defer { isDownloading = false }

        do {
            let file = try await service.download(from: url, to: targetFolderURL)
            statusMessage = "已下载：\(file.lastPathComponent)"
            return file
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }
}
