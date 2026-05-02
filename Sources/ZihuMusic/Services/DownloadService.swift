import Foundation

enum DownloadServiceError: LocalizedError {
    case emptyQuery
    case challengePage
    case noResults
    case invalidURL
    case unsupportedDownload(URL)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "请输入搜索关键词。"
        case .challengePage:
            return "站点返回了 SafeLine 验证页，原生搜索被拦截。请使用内置网页完成验证后下载，或粘贴直链下载。"
        case .noResults:
            return "没有解析到可下载的音乐链接。"
        case .invalidURL:
            return "链接无效。"
        case .unsupportedDownload(let url):
            return "不是支持的音乐下载链接：\(url.absoluteString)"
        }
    }
}

struct DownloadService {
    private let baseURL = URL(string: "https://flac.music.hi.cn/")!

    func search(query: String) async throws -> [DownloadResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DownloadServiceError.emptyQuery }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let candidates = [
            "https://flac.music.hi.cn/?s=\(encoded)",
            "https://flac.music.hi.cn/search?keyword=\(encoded)",
            "https://flac.music.hi.cn/search?q=\(encoded)",
            "https://flac.music.hi.cn/api/search?keyword=\(encoded)"
        ].compactMap(URL.init(string:))

        var sawChallenge = false
        var parsed: [DownloadResult] = []

        for url in candidates {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 ZihuMusic", forHTTPHeaderField: "User-Agent")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let text = String(data: data, encoding: .utf8) else {
                    continue
                }
                if text.contains("SafeLineChallenge") || text.contains("challenge.rivers.chaitin.cn") {
                    sawChallenge = true
                    continue
                }
                parsed.append(contentsOf: parseResults(from: text, sourceURL: url))
            } catch {
                continue
            }
        }

        let unique = Array(Dictionary(grouping: parsed, by: { $0.downloadURL }).compactMap { $0.value.first })
        if !unique.isEmpty { return unique.sorted { $0.title < $1.title } }
        if sawChallenge { throw DownloadServiceError.challengePage }
        throw DownloadServiceError.noResults
    }

    func download(from url: URL, to folder: URL, preferredName: String? = nil) async throws -> URL {
        guard Self.isSupportedAudioURL(url) else {
            throw DownloadServiceError.unsupportedDownload(url)
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let responseName = response.suggestedFilename
        let fallbackName = url.lastPathComponent.isEmpty ? "download.\(url.pathExtension)" : url.lastPathComponent
        let rawName = preferredName?.isEmpty == false ? preferredName! : (responseName ?? fallbackName)
        let sanitized = DisplayFormatters.sanitizedFileName(rawName, fallback: fallbackName)
        let destination = availableDestination(in: folder, fileName: sanitized, extensionFallback: url.pathExtension)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    func parseResults(from text: String, sourceURL: URL) -> [DownloadResult] {
        var results: [DownloadResult] = []
        let pattern = #"<a[^>]+href=["']([^"']+\.(?:flac|mp3|m4a|aac|wav|aiff|aif|caf)(?:\?[^"']*)?)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard
                let hrefRange = Range(match.range(at: 1), in: text),
                let titleRange = Range(match.range(at: 2), in: text)
            else { continue }

            let href = String(text[hrefRange]).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: href, relativeTo: sourceURL)?.absoluteURL else { continue }
            let title = stripHTML(String(text[titleRange]))
            let format = url.pathExtension.lowercased()
            results.append(
                DownloadResult(
                    title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
                    artist: "",
                    album: "",
                    format: format,
                    sizeDescription: "",
                    downloadURL: url,
                    sourcePageURL: sourceURL
                )
            )
        }

        return results
    }

    static func isSupportedAudioURL(_ url: URL) -> Bool {
        MetadataService.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func availableDestination(in folder: URL, fileName: String, extensionFallback: String) -> URL {
        var name = fileName
        if URL(fileURLWithPath: name).pathExtension.isEmpty, !extensionFallback.isEmpty {
            name += ".\(extensionFallback)"
        }

        let destination = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }

        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        for index in 2...999 {
            let candidateName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return destination
    }

    private func stripHTML(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
