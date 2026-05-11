# zihusic

🌐 **App Showcase/展示页：** [zihusic for macOS](https://zihenyag.github.io/zihusic/)

**zihusic** is a lightweight native macOS player for local music libraries.

It is built for people who keep music files on disk and want a clean player that opens directly into the library, artwork, lyrics, and playback controls. zihusic does not copy your music into its own storage. It keeps lightweight library metadata and an artwork cache while your audio files stay where they are.

Current version: **v0.3.0**

中文说明见下方。

## Download

Download the latest build from [GitHub Releases](https://github.com/zihenyag/zihusic/releases).

The app is distributed as a zipped macOS app, for example:

```text
zihusic_app_v0.3.0.zip
```

Unzip it, move `zihusic.app` to `Applications`, and open it. This build is not notarized with an Apple Developer ID, so macOS may ask for confirmation the first time you launch it. If that happens, right-click the app and choose **Open**.

If macOS says the app is damaged after downloading it, remove the download quarantine flag and open it again:

```bash
xattr -dr com.apple.quarantine /Applications/zihusic.app
```

## Features

- Native single-window macOS music player with automatic light/dark appearance.
- Local folder import and rescan without copying audio files.
- Faster rescans using file modification checks, concurrent metadata loading, stale-record cleanup, and an in-app scan progress overlay.
- Compact high-density sidebar for larger libraries, with small artwork thumbnails, a floating auto-hidden scrollbar, and optimized native table scrolling.
- Sidebar search with hover expansion, `Command-F`, close behavior, first-result selection, and a locate button for the selected/current track.
- Playback modes: list loop, repeat one, and shuffle. The selected track and playback mode are restored across launches.
- Accurate local-file playback and seeking through `AVAudioPlayer`, including progress-bar scrubbing and lyric click-to-seek.
- Supports FLAC, MP3, M4A, AAC, WAV, AIFF, AIF, CAF, and ALAC files.
- Reads artwork, title, artist, album, duration, sample rate, bit depth, channel count, and embedded lyrics where available.
- Displays `.ass`, `.lrc`, and embedded LRC lyrics.
- Lyric panel supports active-line emphasis, intro lines before formal lyrics, manual mouse scrolling, click-to-jump, and automatic return to the current line after idle time.
- Long titles, artists, albums, technical summaries, and sidebar text use marquee scrolling instead of hard ellipses.
- Double-click the main title, artist, or album to edit metadata. Double-click artwork to replace the cover.
- Can write updated tags back to FLAC, MP3, M4A, and AAC files when the optional helper tools are available.

## Lyrics

Place a lyric file next to the audio file with the same base name:

```text
Song.flac
Song.ass
```

or:

```text
Song.mp3
Song.lrc
```

zihusic also checks common `Artist - Title` lyric filenames and falls back to embedded LRC lyrics when no matching sidecar file exists.

## Build From Source

Requirements:

- macOS 14 or later
- Xcode Command Line Tools
- Swift 5.9 or later

Optional metadata helpers:

```bash
brew install flac ffmpeg
```

`metaflac` improves FLAC metadata/artwork reading and writing. `ffmpeg` is used for writing tags to MP3, M4A, and AAC files.

Build and run:

```bash
./script/build_and_run.sh
```

Build, run, and verify the process started:

```bash
./script/build_and_run.sh --verify
```

Create a zipped app artifact:

```bash
./script/build_and_run.sh --verify
ditto -c -k --sequesterRsrc --keepParent dist/zihusic.app dist/zihusic_app_v0.3.0.zip
```

## License

MIT License. See [LICENSE](LICENSE).

---

# zihusic 中文说明

**zihusic** 是一个轻量的原生 macOS 本地音乐播放器。

它适合已经把音乐文件保存在本地的人：打开应用后直接进入播放页面，左侧是音乐列表，右侧是封面、歌曲信息和歌词，底部是播放控制。zihusic 不会把音乐复制到自己的目录里，只会保存轻量的资料库信息和封面缓存。

当前版本：**v0.3.0**

## 下载

在 [GitHub Releases](https://github.com/zihenyag/zihusic/releases) 下载最新版本。

当前发布形式是压缩后的 macOS app，例如：

```text
zihusic_app_v0.3.0.zip
```

解压后把 `zihusic.app` 放到 `Applications` 中即可。当前版本还没有做 Apple Developer ID notarization，所以第一次打开时 macOS 可能会提示拦截。如果遇到这种情况，右键应用并选择 **打开**。

如果下载后 macOS 提示应用“已损坏”，可以先移除下载隔离标记，再重新打开：

```bash
xattr -dr com.apple.quarantine /Applications/zihusic.app
```

## 功能

- 原生单窗口 macOS 播放界面，自动跟随系统浅色/深色外观。
- 支持导入和重新扫描本地音乐文件夹，不复制音乐文件本体。
- 重新扫描会复用未变化文件的缓存，并发读取变更文件，清理失效记录，并显示扫描进度。
- 高密度侧边栏适合更大的曲库：小封面、紧凑五列布局、悬浮自动隐藏滚动条，以及更顺滑的原生表格滚动。
- 支持悬停展开搜索、`Command-F` 搜索、关闭搜索、搜索后选中第一首结果，以及手动定位当前/选中歌曲。
- 支持列表循环、单曲循环、随机播放，并记住上次选中的歌曲和播放模式。
- 使用本地文件播放器处理播放和 seek，进度条拖动、歌词点击跳转会直接映射到真实播放时间。
- 支持 FLAC、MP3、M4A、AAC、WAV、AIFF、AIF、CAF、ALAC。
- 读取封面、歌曲名、歌手、专辑、时长、采样率、位深、声道数和可用的内嵌歌词。
- 支持 `.ass`、`.lrc` 和内嵌 LRC 歌词。
- 歌词区支持当前行放大强调、正式歌词前的介绍行、鼠标自由滚动、点击歌词跳转、空闲后自动回到当前歌词。
- 歌名、歌手、专辑、音频信息和侧边栏长文本会用走马灯滚动显示。
- 双击主界面的歌名、歌手或专辑可编辑元数据；双击封面可替换封面。
- 在安装可选工具后，可把标签写回 FLAC、MP3、M4A 和 AAC 文件。

## 歌词

把歌词文件放在音乐文件旁边，并保持同名：

```text
Song.flac
Song.ass
```

或者：

```text
Song.mp3
Song.lrc
```

zihusic 也会尝试匹配常见的 `歌手 - 歌名` 歌词文件名；如果没有找到同名歌词文件，则会回退读取内嵌 LRC 歌词。

## 从源码构建

环境要求：

- macOS 14 或更新版本
- Xcode Command Line Tools
- Swift 5.9 或更新版本

可选的元数据工具：

```bash
brew install flac ffmpeg
```

`metaflac` 用于更完整地读取和写入 FLAC 元数据/封面；`ffmpeg` 用于写入 MP3、M4A 和 AAC 标签。

构建并运行：

```bash
./script/build_and_run.sh
```

构建、运行并确认进程已启动：

```bash
./script/build_and_run.sh --verify
```

生成可上传到 Release 的 app 压缩包：

```bash
./script/build_and_run.sh --verify
ditto -c -k --sequesterRsrc --keepParent dist/zihusic.app dist/zihusic_app_v0.3.0.zip
```

## 许可证

MIT License. 详见 [LICENSE](LICENSE)。
