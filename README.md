# zihusic

**zihusic** is a beautiful, lightweight local music player for macOS.

It is designed for people who keep their music files locally and want a clean player that opens directly into the library, artwork, lyrics, and playback controls. zihusic does not copy your music into its own storage. It keeps only lightweight library metadata and artwork cache, so your files stay where they are.

中文说明见下方。

## Download

Download the latest build from [GitHub Releases](https://github.com/zihenyag/zihusic/releases).

The app is currently distributed as a zipped macOS app:

```text
zihusic.app.zip
```

Unzip it, move `zihusic.app` to `Applications`, and open it. Because this early build is not notarized with an Apple Developer ID, macOS may ask for confirmation the first time you launch it. If that happens, right-click the app and choose **Open**.

## What It Does

- Plays local music with a focused native macOS interface.
- Supports FLAC, MP3, M4A, AAC, WAV, AIFF, AIF, CAF, and ALAC.
- Shows album artwork, title, artist, album, duration, and audio details.
- Displays matching `.ass` and `.lrc` lyrics next to the current track.
- Scans `~/Music` by default, with folder import available from the **Music** menu.
- Keeps your audio files in place and only caches metadata/artwork.
- Supports search, shuffle, repeat one, and repeat all.
- Follows the system light/dark appearance automatically.

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

zihusic will load it automatically when the track is selected.

## Build From Source

Requirements:

- macOS 14 or later
- Xcode Command Line Tools
- Swift 5.9 or later

Optional metadata helpers:

```bash
brew install flac ffmpeg
```

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
ditto -c -k --sequesterRsrc --keepParent dist/zihusic.app dist/zihusic.app.zip
```

## License

MIT License. See [LICENSE](LICENSE).

---

# zihusic 中文说明

**zihusic** 是一个好看的、特别轻量的 macOS 本地音乐播放器。

它适合已经把音乐文件放在本地的人：打开应用后直接进入播放页面，左侧是音乐列表，右侧是封面、歌曲信息和歌词，底部是播放控制。zihusic 不会把你的音乐复制到自己的目录里，只会保存轻量的资料库信息和封面缓存，所以不会额外占用大量空间。

## 下载

在 [GitHub Releases](https://github.com/zihenyag/zihusic/releases) 下载最新版本。

当前发布形式是压缩后的 macOS app：

```text
zihusic.app.zip
```

解压后把 `zihusic.app` 放到 `Applications` 中即可。当前早期版本还没有做 Apple Developer ID notarization，所以第一次打开时 macOS 可能会提示拦截。如果遇到这种情况，右键应用并选择 **打开**。

## 功能

- 使用原生 macOS 界面播放本地音乐。
- 支持 FLAC、MP3、M4A、AAC、WAV、AIFF、AIF、CAF、ALAC。
- 显示封面、歌曲名、歌手、专辑、时长和音频信息。
- 支持同名 `.ass` 和 `.lrc` 歌词。
- 默认扫描 `~/Music`，也可以在应用的 **音乐** 菜单中导入其他文件夹。
- 不复制音乐文件本体，只缓存资料库信息和封面。
- 支持搜索、随机播放、单曲循环和列表循环。
- 自动跟随系统浅色/深色模式。

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

选中歌曲后，zihusic 会自动读取对应歌词。

## 从源码构建

环境要求：

- macOS 14 或更新版本
- Xcode Command Line Tools
- Swift 5.9 或更新版本

可选的元数据读取工具：

```bash
brew install flac ffmpeg
```

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
ditto -c -k --sequesterRsrc --keepParent dist/zihusic.app dist/zihusic.app.zip
```

## 许可证

MIT License. 详见 [LICENSE](LICENSE)。
