import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ZihuMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = MusicLibraryStore()
    @StateObject private var player = AudioPlayerService()
    @StateObject private var downloads = DownloadStore()

    var body: some Scene {
        WindowGroup("zihusic") {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(downloads)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("音乐") {
                Button("选择文件夹...") {
                    Task { await library.chooseAndImportFolder() }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("重新扫描该文件夹") {
                    Task { await library.rescanLastImportFolder() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!library.hasImportFolder)

                Divider()

                Button("搜索") {
                    NotificationCenter.default.post(name: .toggleZihuSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button(player.isPlaying ? "暂停" : "播放") {
                    if player.currentTrack == nil {
                        library.playSelected(using: player)
                    } else {
                        player.togglePlayback()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("下一首") {
                    library.playNext(using: player)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button("上一首") {
                    library.playPrevious(using: player)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
        }
    }
}
