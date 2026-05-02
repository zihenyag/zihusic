import SwiftUI
import WebKit

struct DownloadBrowserView: NSViewRepresentable {
    var url: URL
    var onAudioLink: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAudioLink: onAudioLink)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onAudioLink = onAudioLink
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onAudioLink: (URL) -> Void

        init(onAudioLink: @escaping (URL) -> Void) {
            self.onAudioLink = onAudioLink
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, DownloadService.isSupportedAudioURL(url) {
                onAudioLink(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
