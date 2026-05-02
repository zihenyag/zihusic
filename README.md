# zihusic

**zihusic** is a beautiful, lightweight local music player for macOS. It is built with SwiftUI and AVFoundation, opens straight into the player, and keeps the interface focused on local albums, artwork, lyrics, and playback.

**zihusic** 是一个好看的、特别轻量的 macOS 本地音乐播放器。它使用 SwiftUI 和 AVFoundation 编写，打开后直接进入播放页面，专注于本地歌曲、封面、歌词和播放体验。

## Highlights

- Native macOS SwiftUI interface with automatic light and dark mode.
- Local-first library: scan a folder, cache only metadata/artwork, never copy the music files.
- Lossless playback for FLAC and common formats through AVFoundation.
- Smooth lyric view for matching `.ass` and `.lrc` lyric files.
- Artwork, title, artist, album, duration, sample rate, bit depth, and channel metadata.
- Search by title, artist, and album.
- Playback modes: shuffle, repeat one, and repeat all.
- Adjustable sidebar/list layout with remembered widths.

## 功能亮点

- 原生 macOS SwiftUI 界面，自动跟随系统浅色/深色模式。
- 本地优先：扫描文件夹，只缓存歌曲信息和封面，不复制音乐文件本体。
- 支持 FLAC 无损播放，也支持常见音频格式。
- 支持同名 `.ass` 和 `.lrc` 歌词文件，并显示平滑滚动歌词。
- 读取封面、歌曲名、歌手、专辑、时长、采样率、位深、声道等信息。
- 支持按歌曲名、歌手、专辑搜索。
- 支持随机播放、单曲循环、列表循环。
- 左侧列表布局可调节，并会记忆宽度。

## Supported Formats / 支持格式

`flac`, `mp3`, `m4a`, `aac`, `wav`, `aiff`, `aif`, `caf`, `alac`

## Requirements / 环境要求

- macOS 14 or later / macOS 14 或更新版本
- Xcode Command Line Tools / Xcode 命令行工具
- Swift 5.9 or later / Swift 5.9 或更新版本

Optional tools improve metadata reading:

可选工具可以增强元数据读取：

```bash
brew install flac ffmpeg
```

## Run From Source / 从源码运行

```bash
./script/build_and_run.sh
```

To verify the app process starts successfully:

确认应用进程能正常启动：

```bash
./script/build_and_run.sh --verify
```

The script builds the SwiftPM target, creates `dist/zihusic.app`, generates the app icon, and launches the app.

脚本会构建 SwiftPM target，生成 `dist/zihusic.app`，生成应用图标，并启动应用。

## Download Builds / 下载版本

For public sharing, the simplest release artifact is:

对外分享时，最简单的发布文件是：

```text
zihusic.app.zip
```

Build it locally:

本地生成方式：

```bash
./script/build_and_run.sh --verify
ditto -c -k --sequesterRsrc --keepParent dist/zihusic.app dist/zihusic.app.zip
```

Then upload `dist/zihusic.app.zip` to a GitHub Release.

然后把 `dist/zihusic.app.zip` 上传到 GitHub Release。

This project is currently unsigned and not notarized. On another Mac, the first launch may require right-clicking the app and choosing **Open**.

当前版本没有做 Apple Developer ID 签名和 notarization。在其他 Mac 上第一次打开时，可能需要右键应用并选择 **打开**。

## Release vs DMG / Release 和 DMG 是什么

A GitHub **Release** is the place where users download a finished version of the app. The repository stores source code; Releases store packaged builds such as `zihusic.app.zip` or `zihusic.dmg`.

GitHub **Release** 可以理解成“给用户下载正式版本的地方”。代码仓库放源码，Release 放已经打包好的应用，比如 `zihusic.app.zip` 或 `zihusic.dmg`。

A **DMG** is the common macOS installer image. It is useful for polished distribution, but it is not required for a lightweight personal/open-source app. A zipped `.app` is enough for the first public version.

**DMG** 是 macOS 常见安装镜像，适合更正式的分发，但不是轻量个人/开源应用的必需项。首个公开版本用压缩后的 `.app` 就够了。

## Default Music Folder / 默认音乐目录

zihusic uses `/Volumes/disk/download/music` when that folder exists. Otherwise it falls back to the current user's `~/Music` folder.

如果 `/Volumes/disk/download/music` 存在，zihusic 会优先使用它；否则会使用当前用户的 `~/Music` 文件夹。

The value is defined in:

路径定义在：

```text
Sources/ZihuMusic/Support/AppDirectories.swift
```

## Project Structure / 项目结构

```text
Package.swift                  SwiftPM package
script/build_and_run.sh         Build, package, and run script
Sources/ZihuMusic/App           App entry
Sources/ZihuMusic/Models        Data models
Sources/ZihuMusic/Stores        Library and download state
Sources/ZihuMusic/Services      Playback, metadata, lyrics, and writing services
Sources/ZihuMusic/Support       Paths and utilities
Sources/ZihuMusic/Views         SwiftUI views
Sources/ZihuMusic/Icon/icon.png App icon source
```

## License / 许可证

MIT License. See `LICENSE`.
