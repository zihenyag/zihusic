# zihusic Release Notes

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

## English

Initial public version of zihusic, a beautiful and lightweight local music player for macOS.

- Native SwiftUI player UI with automatic light/dark mode.
- Local folder scanning without copying music files.
- FLAC, MP3, M4A, AAC, WAV, AIFF, CAF, and ALAC support.
- Matching `.ass` and `.lrc` lyric display.
- Artwork and metadata reading/editing.
- Search, shuffle, repeat one, and repeat all.
- Adjustable sidebar/list layout.

The app is currently unsigned and not notarized. If macOS blocks the first launch, right-click `zihusic.app` and choose **Open**.

## 中文

zihusic 的首个公开版本，一个好看的、特别轻量的 macOS 本地音乐播放器。

- 原生 SwiftUI 播放页面，自动跟随系统浅色/深色模式。
- 扫描本地音乐文件夹，不复制音乐文件本体。
- 支持 FLAC、MP3、M4A、AAC、WAV、AIFF、CAF、ALAC。
- 支持同名 `.ass` 和 `.lrc` 歌词显示。
- 支持封面和元数据读取/编辑。
- 支持搜索、随机播放、单曲循环、列表循环。
- 左侧列表布局可调节。

当前应用没有做 Apple Developer ID 签名和 notarization。如果 macOS 第一次拦截启动，可以右键 `zihusic.app`，选择 **打开**。
