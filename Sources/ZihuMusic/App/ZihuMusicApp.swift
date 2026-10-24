import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menus: AppMenuController?
    private var window: NSWindow?
    private var library: MusicLibraryStore?
    private var player: AudioPlayerService?
    private var downloads: DownloadStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let library = MusicLibraryStore()
        let player = AudioPlayerService()
        let downloads = DownloadStore()
        self.library = library
        self.player = player
        self.downloads = downloads
        menus = AppMenuController(library: library, player: player)

        let content = ContentView()
            .environmentObject(library)
            .environmentObject(player)
            .environmentObject(downloads)
            .frame(minWidth: 1180, minHeight: 760)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 788),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "zihusic"
        window.contentMinSize = NSSize(width: 1180, height: 760)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.setFrameAutosaveName("zihusic.main")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }
}

/// AppKit owns the window and main menu. A SwiftUI WindowGroup also owns its
/// command menu and would repeatedly replace a separately installed NSMenu.
@main
struct ZihuMusicApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
