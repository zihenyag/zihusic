# zihusic Release Notes

## v0.4.0

### 中文

- 新增 AirPlay 多设备播放，自动接入同一网络中的接收器；每次启动默认只开启本机声音。
- 每台扬声器可独立停止、恢复和调节音量。停止播放保留连接；支持本机延迟校准和“播放 → AirPlay 全同步”。
- 歌词固定字号，仅用颜色强调当前行；改善翻译与多行排版，滚轮浏览后 3 秒回到播放位置。
- 缓存并预取歌词，改善启动和切歌加载；修复换歌、跳转时旧音频时钟导致的高亮错位。
- 精简悬浮控制条，加入明暗模式边缘模糊；重整“音乐 / 窗口 / 播放”菜单，修复闪烁并支持原生全屏。
- 更新 GitHub Pages 展示页和安装说明。

下载 `zihusic_app_v0.4.0.zip`，解压后将 `zihusic.app` 放入 Applications。要求 macOS 14 或更新版本，当前构建为 Apple Silicon。发布包采用临时签名，未做 Developer ID 公证。

AirPlay 自动接入需在“系统设置 → 隐私与安全性 → 辅助功能”中允许已安装的 zihusic。更新后若旧授权失效，请移除旧条目，再添加 Applications 中的新版本。普通本机播放不需要此权限。

AirPlay 多设备功能仍为实验性实现，使用受可用性检查保护的非公开 AVFoundation 接口。已在 Mac mini 与 MacBook Air 之间验证歌曲基本同步、独立停止/恢复和设备后上线自动接入；其他接收器、多远端组合和不同网络仍需验证。iPad 不作为接收端支持。

### English

- Add automatic AirPlay receiver enrollment, independent speaker playback/volume, local delay calibration, and manual timeline resynchronization. Each launch starts with only this Mac audible.
- Keep lyrics at a fixed size with color-only highlighting, measured translated/wrapped rows, smooth line transitions, and a 3-second return after wheel browsing.
- Cache and prefetch lyrics. Fix stale playback clocks and lyric animations after track changes or seeks.
- Refine floating controls and appearance-aware edge blur. Rebuild the Music / Window / Playback menus, fix menu flicker, and support native fullscreen.
- Refresh the project website and installation instructions.

Requires macOS 14+, Apple Silicon. The app is ad-hoc signed and not notarized. Accessibility consent is required only for automatic AirPlay enrollment. Grouped AirPlay uses guarded private AVFoundation interfaces and remains experimental; the tested Mac mini / MacBook Air pair does not establish compatibility with all receivers.

## v0.3.0

### English

Download `zihusic_app_v0.3.0.zip`, unzip it, move `zihusic.app` to Applications, and open it. If macOS still says the app is damaged, run:

```bash
xattr -dr com.apple.quarantine /Applications/zihusic.app
```

This release focuses on making zihusic feel better with real local libraries: faster rescans, a denser sidebar, smoother search and positioning, improved lyric interaction, and more reliable local-file seeking.

- Reworked the sidebar into a compact five-column native table with smaller artwork and better scrolling performance for larger libraries.
- Added a floating auto-hidden sidebar scrollbar and a manual locate button for the selected/current track.
- Refined the custom top chrome so search, locate, sidebar toggle, and window buttons stay aligned across collapsed and expanded states.
- Added hover search and `Command-F` search behavior, including first-result selection and automatic positioning after leaving search when a song was selected.
- Added folder rescan progress, metadata-cache reuse for unchanged files, concurrent metadata loading, and stale-track cleanup.
- Restored the last selected song and playback mode on launch.
- Switched local playback to `AVAudioPlayer` for more accurate progress-bar scrubbing and lyric click-to-seek on local files.
- Improved lyric behavior with active-line emphasis, intro-line handling, manual mouse scrolling, click-to-jump, and automatic return to the current lyric after idle time.
- Replaced hard ellipses in key text areas with marquee scrolling for long titles, artists, albums, technical summaries, and sidebar text.
- Kept metadata editing in the main player: double-click title, artist, album, or artwork to edit and optionally write tags back when helper tools are available.

### 中文

下载 `zihusic_app_v0.3.0.zip` 后解压，把 `zihusic.app` 放到 Applications 中再打开。如果 macOS 仍提示应用“已损坏”，执行：

```bash
xattr -dr com.apple.quarantine /Applications/zihusic.app
```

这个版本主要改善真实本地曲库下的使用体验：重新扫描更快，侧边栏更紧凑，搜索和定位更稳定，歌词交互更完整，本地音频 seek 更准确。

- 将侧边栏改为更紧凑的五列表格，小封面布局更适合一百首以上的曲库。
- 增加悬浮自动隐藏的侧边栏滚动条，以及手动定位当前/选中歌曲的按钮。
- 调整顶部红绿灯、搜索、定位、侧边栏按钮的位置，收起和展开时不再明显错位。
- 增加悬停搜索和 `Command-F` 搜索；搜索时自动选中第一首结果，搜索中选歌后退出会自动定位。
- 重新扫描增加进度显示；未变化文件复用缓存，变更文件并发读取，并清理已经删除的歌曲记录。
- 启动时恢复上次选中的歌曲和播放模式。
- 本地播放切换到 `AVAudioPlayer`，修复进度条拖动和歌词点击跳转后 UI 时间与真实声音不一致的问题。
- 改进歌词滚动：当前行强调、正式歌词前介绍行处理、鼠标自由滚动、点击跳转、空闲后自动回到当前歌词。
- 长歌名、歌手、专辑、音频信息和侧边栏文字改为走马灯显示，减少生硬省略。
- 主播放界面保留元数据编辑：双击歌名、歌手、专辑或封面即可编辑；安装辅助工具后可写回音频标签。

## v0.2.0

### English

Download `zihusic_app_v0.2.0.zip`, unzip it, move `zihusic.app` to Applications, and open it. If macOS still says the app is damaged, run:

```bash
xattr -dr com.apple.quarantine /Applications/zihusic.app
```

### 中文

下载 `zihusic_app_v0.2.0.zip` 后解压，把 `zihusic.app` 放到 Applications 中再打开。如果 macOS 仍提示应用“已损坏”，执行：

```bash
xattr -dr com.apple.quarantine /Applications/zihusic.app
```

## v0.1.1

### English

Packaging hotfix for the public macOS build.

- Build release binaries instead of debug binaries.
- Remove local extended attributes before packaging.
- Ad-hoc sign the app bundle so macOS can validate the bundle structure.
- Add troubleshooting notes for macOS download quarantine.

### 中文

公开 macOS 构建包的打包修复版本。

- 改为构建 release 二进制。
- 打包前移除本地扩展属性。
- 对整个 app bundle 做 ad-hoc 签名，让 macOS 能验证 bundle 结构。
- 增加 macOS 下载隔离提示的处理说明。

## v0.1.0

### English

Initial public version of zihusic, a lightweight local music player for macOS.

- Native SwiftUI player UI with automatic light/dark mode.
- Local folder scanning without copying music files.
- FLAC, MP3, M4A, AAC, WAV, AIFF, CAF, and ALAC support.
- Matching `.ass` and `.lrc` lyric display.
- Artwork and metadata reading/editing.
- Search, shuffle, repeat one, and repeat all.
- Adjustable sidebar/list layout.

The app is currently unsigned and not notarized. If macOS blocks the first launch, right-click `zihusic.app` and choose **Open**.

### 中文

zihusic 的首个公开版本，一个轻量的 macOS 本地音乐播放器。

- 原生 SwiftUI 播放页面，自动跟随系统浅色/深色模式。
- 扫描本地音乐文件夹，不复制音乐文件本体。
- 支持 FLAC、MP3、M4A、AAC、WAV、AIFF、CAF、ALAC。
- 支持同名 `.ass` 和 `.lrc` 歌词显示。
- 支持封面和元数据读取/编辑。
- 支持搜索、随机播放、单曲循环、列表循环。
- 左侧列表布局可调节。

当前应用没有做 Apple Developer ID 签名和 notarization。如果 macOS 第一次拦截启动，可以右键 `zihusic.app`，选择 **打开**。
