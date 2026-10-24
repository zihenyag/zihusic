import AppKit

/// One native menu hierarchy, shared with the dock's playback actions/state.
@MainActor
final class AppMenuController: NSObject, NSMenuDelegate {
    enum Theme: String, CaseIterable {
        case system, light, dark
        var title: String { switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" } }
        var appearance: NSAppearance? {
            switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
        }
    }

    private let library: MusicLibraryStore
    private let player: AudioPlayerService
    private let main = PlayerMainMenu()
    private var rescan: NSMenuItem!
    private var playback: NSMenuItem!
    private var previous: NSMenuItem!
    private var next: NSMenuItem!
    private var synchronize: NSMenuItem!
    private var fullscreen: NSMenuItem!
    private var sidebar: NSMenuItem!
    private var themes: [NSMenuItem] = []

    init(library: MusicLibraryStore, player: AudioPlayerService) {
        self.library = library
        self.player = player
        super.init()
        buildMenus()
        applyTheme()
        install()
    }

    func install() {
        if NSApp.mainMenu !== main { NSApp.mainMenu = main }
        NSApp.windowsMenu = nil
        NSApp.helpMenu = nil
    }

    private func menu(_ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.delegate = self
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    @discardableResult
    private func item(_ title: String, in menu: NSMenu, action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    private func buildMenus() {
        let app = menu("zihusic")
        item("关于 zihusic", in: app, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        item("隐藏 zihusic", in: app, action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp)
        item("退出 zihusic", in: app, action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)

        let music = menu("音乐")
        item("选择文件夹…", in: music, action: #selector(importFolder), key: "o")
        rescan = item("重新扫描该文件夹", in: music, action: #selector(rescanFolder), key: "r")
        music.addItem(.separator())
        item("搜索", in: music, action: #selector(search), key: "f")

        let window = menu("窗口")
        let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "主题")
        themeMenu.autoenablesItems = false
        themeMenu.delegate = self
        for (index, theme) in Theme.allCases.enumerated() {
            let choice = item(theme.title, in: themeMenu, action: #selector(changeTheme(_:)))
            choice.tag = index
            themes.append(choice)
        }
        themeItem.submenu = themeMenu
        window.addItem(themeItem)
        fullscreen = item("全屏模式", in: window, action: #selector(toggleFullscreen), key: "f", modifiers: [.command, .control])
        sidebar = item("收缩侧边栏", in: window, action: #selector(toggleSidebar), key: "s", modifiers: [.command, .option])

        let play = menu("播放")
        playback = item("播放", in: play, action: #selector(togglePlayback), key: " ", modifiers: [])
        previous = item("上一首", in: play, action: #selector(previousTrack), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        next = item("下一首", in: play, action: #selector(nextTrack), key: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        play.addItem(.separator())
        synchronize = item("AirPlay 全同步", in: play, action: #selector(resynchronize))
        menuNeedsUpdate(main)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rescan.isEnabled = library.hasImportFolder
        playback.title = player.isPlaying ? "暂停" : "播放"
        playback.isEnabled = player.currentTrack != nil || !library.tracks.isEmpty
        previous.isEnabled = !library.tracks.isEmpty
        next.isEnabled = !library.tracks.isEmpty
        synchronize.isEnabled = player.airPlay.hasRemoteOutputs && player.currentTrack != nil
        let visible = UserDefaults.standard.object(forKey: "isSidebarVisible") as? Bool ?? true
        sidebar.title = visible ? "收缩侧边栏" : "展开侧边栏"
        fullscreen.state = NSApp.mainWindow?.styleMask.contains(.fullScreen) == true ? .on : .off
        let selected = UserDefaults.standard.string(forKey: "appTheme") ?? Theme.system.rawValue
        for (index, item) in themes.enumerated() { item.state = Theme.allCases[index].rawValue == selected ? .on : .off }
    }

    private func applyTheme() {
        let theme = Theme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "") ?? .system
        NSApp.appearance = theme.appearance
    }

    @objc private func importFolder() { Task { await library.chooseAndImportFolder() } }
    @objc private func rescanFolder() { Task { await library.rescanLastImportFolder() } }
    @objc private func search() { NotificationCenter.default.post(name: .toggleZihuSearch, object: nil) }
    @objc private func togglePlayback() { NotificationCenter.default.post(name: .toggleZihuPlayback, object: nil) }
    @objc private func previousTrack() { NotificationCenter.default.post(name: .previousZihuTrack, object: nil) }
    @objc private func nextTrack() { NotificationCenter.default.post(name: .nextZihuTrack, object: nil) }
    @objc private func resynchronize() { player.airPlay.resynchronize() }
    @objc private func toggleSidebar() {
        let visible = UserDefaults.standard.object(forKey: "isSidebarVisible") as? Bool ?? true
        UserDefaults.standard.set(!visible, forKey: "isSidebarVisible")
    }
    @objc private func toggleFullscreen() { (NSApp.mainWindow ?? NSApp.keyWindow)?.toggleFullScreen(nil) }

    @objc private func changeTheme(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Theme.allCases[sender.tag].rawValue, forKey: "appTheme")
        applyTheme()
    }
}

/// Typing a space in search/metadata must not trigger the playback shortcut.
private final class PlayerMainMenu: NSMenu {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.charactersIgnoringModifiers == " ",
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }
}
