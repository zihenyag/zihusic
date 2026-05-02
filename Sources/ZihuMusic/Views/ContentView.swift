import AppKit
import SwiftUI

private extension Notification.Name {
    static let collapseZihuSearch = Notification.Name("collapseZihuSearch")
}

private extension Color {
    static func adaptive(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                red: value.0,
                green: value.1,
                blue: value.2,
                alpha: value.3
            )
        })
    }
}

private enum AppColors {
    static let background = Color.adaptive(
        light: (0.97, 0.94, 0.985, 1),
        dark: (0.085, 0.070, 0.125, 1)
    )
    static let sidebarBackground = Color.adaptive(
        light: (0.94, 0.89, 0.98, 1),
        dark: (0.120, 0.095, 0.175, 1)
    )
    static let primaryText = Color.adaptive(
        light: (0.16, 0.14, 0.31, 1),
        dark: (0.88, 0.84, 0.97, 1)
    )
    static let secondaryText = Color.adaptive(
        light: (0.32, 0.28, 0.50, 1),
        dark: (0.74, 0.68, 0.88, 1)
    )
    static let tertiaryText = Color.adaptive(
        light: (0.45, 0.40, 0.60, 1),
        dark: (0.58, 0.52, 0.72, 1)
    )
    static let mutedText = Color.adaptive(
        light: (0.53, 0.48, 0.66, 1),
        dark: (0.50, 0.45, 0.62, 1)
    )
    static let accent = Color.adaptive(
        light: (0.43, 0.30, 0.82, 1),
        dark: (0.67, 0.52, 1.00, 1)
    )
    static let accentStrong = Color.adaptive(
        light: (0.38, 0.25, 0.76, 1),
        dark: (0.74, 0.59, 1.00, 1)
    )
    static let selectedRow = Color.adaptive(
        light: (0.47, 0.34, 0.86, 0.18),
        dark: (0.58, 0.41, 1.00, 0.24)
    )
    static let separator = Color.adaptive(
        light: (0.48, 0.33, 0.84, 0.28),
        dark: (0.72, 0.55, 1.00, 0.28)
    )
    static let controlFill = Color.adaptive(
        light: (0.50, 0.50, 0.50, 0.08),
        dark: (1.00, 1.00, 1.00, 0.08)
    )
    static let searchStroke = Color.adaptive(
        light: (0.58, 0.51, 0.83, 0.24),
        dark: (0.77, 0.66, 1.00, 0.28)
    )
    static let shadow = Color.adaptive(
        light: (0.23, 0.15, 0.42, 0.12),
        dark: (0.00, 0.00, 0.00, 0.35)
    )
}

enum PlaybackMode: String, CaseIterable, Identifiable {
    case shuffle = "随机播放"
    case singleLoop = "单曲循环"
    case listLoop = "列表循环"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .shuffle: "随机"
        case .singleLoop: "单曲"
        case .listLoop: "列表"
        }
    }

    var systemImage: String {
        switch self {
        case .shuffle: "shuffle"
        case .singleLoop: "repeat.1"
        case .listLoop: "repeat"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    @AppStorage("leftPaneWidth") private var leftPaneWidth = 430.0
    @AppStorage("artistColumnWidth") private var artistColumnWidth = 104.0
    @AppStorage("durationColumnWidth") private var durationColumnWidth = 74.0
    @State private var leftDragStart: CGFloat?
    @State private var playbackMode: PlaybackMode = .listLoop

    private let minLeftWidth: CGFloat = 320
    private let minRightWidth: CGFloat = 720

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let leftWidth = clampedLeftWidth(total: geometry.size.width)

                    HStack(spacing: 0) {
                        LibraryPane(
                            tracks: visibleTracks,
                            artistColumnWidth: $artistColumnWidth,
                            durationColumnWidth: $durationColumnWidth,
                            selectedTrackID: $library.selectedTrackID,
                            play: play
                        )
                        .frame(width: leftWidth)
                        .overlay(alignment: .trailing) {
                            InvisibleResizeHandle()
                                .offset(x: InvisibleResizeHandle.hitWidth / 2)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if leftDragStart == nil { leftDragStart = leftWidth }
                                            let next = (leftDragStart ?? leftWidth) + value.translation.width
                                            leftPaneWidth = clampedLeftWidth(total: geometry.size.width, proposed: next)
                                        }
                                        .onEnded { _ in leftDragStart = nil }
                                )
                        }
                        .zIndex(2)

                        PlaybackPane(track: activeTrack)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture {
                                NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
                            }
                    }
                }

                Divider().opacity(0.42)

                PlayerDock(
                    playbackMode: $playbackMode,
                    previous: playPrevious,
                    toggle: togglePlayback,
                    next: playNext
                )
                .frame(height: 118)
                .onTapGesture {
                    NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
                }
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .onAppear {
            player.onFinished = { handleFinished() }
            if library.selectedTrackID == nil {
                library.selectedTrackID = visibleTracks.first?.id
            }
        }
    }

    private var activeTrack: MusicTrack? {
        player.currentTrack ?? library.selectedTrack ?? visibleTracks.first
    }

    private var visibleTracks: [MusicTrack] {
        let query = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? library.tracks : library.tracks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.displayArtist.localizedCaseInsensitiveContains(query)
                || $0.displayAlbum.localizedCaseInsensitiveContains(query)
        }

        return filtered.sorted {
            let left = sortKey($0.displayTitle)
            let right = sortKey($1.displayTitle)
            if left == right {
                return $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending
            }
            return left < right
        }
    }

    private func play(_ track: MusicTrack) {
        library.selectedTrackID = track.id
        player.play(track)
    }

    private func togglePlayback() {
        if player.currentTrack == nil, let track = activeTrack {
            play(track)
        } else {
            player.togglePlayback()
        }
    }

    private func playNext() {
        switch playbackMode {
        case .shuffle:
            playRandom()
        case .singleLoop:
            if let track = activeTrack { play(track) }
        case .listLoop:
            playOffset(1)
        }
    }

    private func playPrevious() {
        playbackMode == .shuffle ? playRandom() : playOffset(-1)
    }

    private func handleFinished() {
        switch playbackMode {
        case .shuffle:
            playRandom()
        case .singleLoop:
            if let track = player.currentTrack { player.play(track) }
        case .listLoop:
            playOffset(1)
        }
    }

    private func playOffset(_ offset: Int) {
        guard !visibleTracks.isEmpty else { return }
        let currentID = player.currentTrack?.id ?? library.selectedTrackID
        let currentIndex = visibleTracks.firstIndex { $0.id == currentID } ?? 0
        let nextIndex = (currentIndex + offset + visibleTracks.count) % visibleTracks.count
        play(visibleTracks[nextIndex])
    }

    private func playRandom() {
        guard let random = visibleTracks.filter({ $0.id != player.currentTrack?.id }).randomElement() ?? visibleTracks.first else {
            return
        }
        play(random)
    }

    private func clampedLeftWidth(total: CGFloat, proposed: CGFloat? = nil) -> CGFloat {
        let maximum = max(minLeftWidth, total - minRightWidth)
        return min(max(proposed ?? CGFloat(leftPaneWidth), minLeftWidth), maximum)
    }

    private func sortKey(_ value: String) -> String {
        let mutable = NSMutableString(string: value) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

private struct AppBackdrop: View {
    var body: some View {
        AppColors.background
        .ignoresSafeArea()
    }
}

private struct InvisibleResizeHandle: View {
    static let hitWidth: CGFloat = 12

    var body: some View {
        Color.clear
        .frame(width: Self.hitWidth)
        .contentShape(Rectangle())
        .help("拖动调整宽度")
    }
}

private enum TrackListMetrics {
    static let rowHorizontalPadding: CGFloat = 10
    static let artworkColumnWidth: CGFloat = 72
    static let minArtistWidth: CGFloat = 72
    static let maxArtistWidth: CGFloat = 170
    static let minDurationWidth: CGFloat = 58
    static let maxDurationWidth: CGFloat = 104
}

private struct LibraryPane: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    let tracks: [MusicTrack]
    @Binding var artistColumnWidth: Double
    @Binding var durationColumnWidth: Double
    @Binding var selectedTrackID: MusicTrack.ID?
    var play: (MusicTrack) -> Void

    var body: some View {
        ZStack {
            AppColors.sidebarBackground
                .ignoresSafeArea(edges: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
                }

            VStack(spacing: 0) {
                LibraryHeader(
                    searchText: $library.searchText,
                    artistColumnWidth: $artistColumnWidth,
                    durationColumnWidth: $durationColumnWidth
                )
                .padding(.horizontal, TrackListMetrics.rowHorizontalPadding * 2)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(tracks) { track in
                            LibraryRow(
                                track: track,
                                isSelected: selectedTrackID == track.id,
                                isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
                                artworkURL: library.artworkURL(for: track),
                                artistColumnWidth: CGFloat(artistColumnWidth),
                                durationColumnWidth: CGFloat(durationColumnWidth)
                            ) {
                                play(track)
                            }
                        }
                    }
                    .padding(.horizontal, TrackListMetrics.rowHorizontalPadding)
                    .padding(.bottom, 12)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
        }
    }
}

private struct LibraryHeader: View {
    @Binding var searchText: String
    @Binding var artistColumnWidth: Double
    @Binding var durationColumnWidth: Double
    @State private var artistDragStart: Double?
    @State private var durationDragStart: Double?

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Text("歌曲")
                    .frame(maxWidth: .infinity, alignment: .center)
                HeaderSearchBox(text: $searchText)
                    .padding(.leading, 6)
            }
            ResizableHeaderSeparator()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if artistDragStart == nil { artistDragStart = artistColumnWidth }
                            let next = (artistDragStart ?? artistColumnWidth) - value.translation.width
                            artistColumnWidth = clamped(next, min: TrackListMetrics.minArtistWidth, max: TrackListMetrics.maxArtistWidth)
                        }
                        .onEnded { _ in artistDragStart = nil }
                )
            Text("歌手")
                .frame(width: CGFloat(artistColumnWidth), alignment: .center)
            ResizableHeaderSeparator()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if durationDragStart == nil { durationDragStart = durationColumnWidth }
                            let next = (durationDragStart ?? durationColumnWidth) - value.translation.width
                            durationColumnWidth = clamped(next, min: TrackListMetrics.minDurationWidth, max: TrackListMetrics.maxDurationWidth)
                        }
                        .onEnded { _ in durationDragStart = nil }
                )
            Text("时长")
                .frame(width: CGFloat(durationColumnWidth), alignment: .center)
        }
        .frame(height: 52)
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(AppColors.secondaryText)
    }

    private func clamped(_ value: Double, min minimum: CGFloat, max maximum: CGFloat) -> Double {
        Swift.min(Swift.max(value, Double(minimum)), Double(maximum))
    }
}

private struct ResizableHeaderSeparator: View {
    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(AppColors.separator)
                .frame(width: 1, height: 24)
        }
        .frame(width: 14, height: 42)
        .contentShape(Rectangle())
        .help("拖动调整列宽")
    }
}

private struct HeaderSearchBox: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var expanded: Bool {
        hovering || focused || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Button {
                focused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle().inset(by: -6))

            if expanded {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)

                    TextField("搜索歌曲、歌手或专辑", text: $text)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .font(.system(size: 15, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(width: 232, height: 40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppColors.searchStroke, lineWidth: 1)
                )
                .shadow(color: AppColors.shadow, radius: 14, y: 8)
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .frame(width: 38, height: 38, alignment: .leading)
        .contentShape(Rectangle().inset(by: -6))
        .onHover { hovering = $0 }
        .onTapGesture { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .collapseZihuSearch)) { _ in
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focused = false
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }
}

private struct LibraryRow: View {
    let track: MusicTrack
    let isSelected: Bool
    let isPlaying: Bool
    let artworkURL: URL?
    let artistColumnWidth: CGFloat
    let durationColumnWidth: CGFloat
    var play: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(url: artworkURL, size: 44)
                .frame(width: TrackListMetrics.artworkColumnWidth, alignment: .leading)

            Text(track.displayTitle)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AppColors.accentStrong : AppColors.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.displayArtist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
                .frame(width: artistColumnWidth, alignment: .leading)

            HStack(spacing: 7) {
                    Text(DisplayFormatters.time(track.duration))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.tertiaryText)
                if isPlaying {
                    EqualizerGlyph()
                        .frame(width: 15, height: 16)
                }
            }
            .frame(width: durationColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppColors.selectedRow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
            play()
        }
    }
}

private struct EqualizerGlyph: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Capsule().frame(width: 3, height: 9)
            Capsule().frame(width: 3, height: 15)
            Capsule().frame(width: 3, height: 12)
        }
        .foregroundStyle(AppColors.accent)
    }
}

private struct PlaybackPane: View {
    let track: MusicTrack?

    var body: some View {
        GeometryReader { geometry in
            let heroWidth = min(max(geometry.size.width * 0.32, 320), 410)
            let lyricsWidth = min(
                min(max(geometry.size.width * 0.50, 360), 760),
                max(340, geometry.size.width - heroWidth - 12)
            )

            HStack(spacing: 12) {
                SongHeroPane(track: track)
                    .frame(width: heroWidth)
                    .frame(maxHeight: .infinity)

                LyricsSidePane(track: track)
                    .frame(width: lyricsWidth, height: geometry.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SongHeroPane: View {
    @EnvironmentObject private var library: MusicLibraryStore
    let track: MusicTrack?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            ArtworkView(url: track.flatMap { library.artworkURL(for: $0) }, size: 276)
                .shadow(color: AppColors.shadow, radius: 22, y: 16)

            VStack(spacing: 9) {
                Text(track?.displayTitle ?? "未播放")
                    .font(.system(size: 33, weight: .heavy))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .padding(.top, 30)

                Text(track?.displayArtist ?? "选择左侧歌曲")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text("专辑：\(track?.displayAlbum ?? "-")")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.tertiaryText)
                    .lineLimit(1)

                if let track {
                    Text(DisplayFormatters.technicalSummary(for: track))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 54)
        }
        .padding(.horizontal, 30)
    }
}

private struct LyricsSidePane: View {
    let track: MusicTrack?

    var body: some View {
        SmoothLyricsPane(track: track)
            .padding(.top, 24)
    }
}

private struct SmoothLyricsPane: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    let track: MusicTrack?
    @State private var lines: [LyricsLine] = []

    private let service = LyricsService()
    private let rowHeight: CGFloat = 86
    private let lyricLead: TimeInterval = 0.15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { _ in
            let time = player.preciseCurrentTime + lyricLead

            GeometryReader { geometry in
                ZStack {
                    if lines.isEmpty {
                        Text("未找到同名 .ass 歌词")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.mutedText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        let activeIndex = currentIndex(for: time)
                        let range = visibleRange(around: activeIndex)

                        VStack(spacing: 0) {
                            ForEach(range, id: \.self) { index in
                                let line = lines[index]

                                LyricLineView(
                                    text: line.text,
                                    isCurrent: index == activeIndex,
                                    isNear: abs(index - activeIndex) <= 2
                                )
                                .frame(minHeight: rowHeight)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .offset(y: lyricOffset(in: geometry.size.height, time: time) + CGFloat(range.lowerBound) * rowHeight)
                        .clipped()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .onAppear { reloadLyrics() }
        .onChange(of: track?.id) { _, _ in reloadLyrics() }
    }

    private func currentIndex(for time: TimeInterval) -> Int {
        service.currentIndex(in: lines, time: time) ?? 0
    }

    private func visibleRange(around index: Int) -> Range<Int> {
        let lower = max(0, index - 8)
        let upper = min(lines.count, index + 10)
        return lower..<upper
    }

    private func lyricOffset(in height: CGFloat, time: TimeInterval) -> CGFloat {
        let position = continuousPosition(time: time)
        return height / 2 - rowHeight / 2 - CGFloat(position) * rowHeight
    }

    private func continuousPosition(time: TimeInterval) -> Double {
        guard !lines.isEmpty else { return 0 }
        let index = currentIndex(for: time)
        guard lines.indices.contains(index + 1) else { return Double(index) }
        let start = lines[index].time
        let end = lines[index + 1].time
        let span = max(end - start, 0.8)
        let progress = min(max((time - start) / span, 0), 1)
        return Double(index) + smoothstep(progress)
    }

    private func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private func reloadLyrics() {
        guard let track else {
            lines = []
            return
        }
        lines = library.lyrics(for: track)
    }
}

private struct LyricLineView: View {
    let text: String
    let isCurrent: Bool
    let isNear: Bool

    var body: some View {
        Text(text)
            .font(.system(size: isCurrent ? 24 : 16, weight: isCurrent ? .heavy : .semibold))
            .foregroundStyle(
                isCurrent
                    ? AppColors.accentStrong
                    : AppColors.tertiaryText.opacity(isNear ? 0.86 : 0.58)
            )
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
    }
}

private struct PlayerDock: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    @Binding var playbackMode: PlaybackMode
    var previous: () -> Void
    var toggle: () -> Void
    var next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NowPlayingMini(track: player.currentTrack ?? library.selectedTrack)
                .frame(width: 240, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                HStack(spacing: 22) {
                    TransportButton(systemImage: "backward.fill", action: previous, help: "上一首")

                    Button(action: toggle) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(
                                Circle()
                                    .fill(AppColors.accent)
                                    .shadow(color: AppColors.accent.opacity(0.35), radius: 12, y: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle().inset(by: -10))
                    .help(player.isPlaying ? "暂停" : "播放")

                    TransportButton(systemImage: "forward.fill", action: next, help: "下一首")
                }

                HStack(spacing: 12) {
                    Text(DisplayFormatters.time(player.currentTime))
                        .frame(width: 46, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    .tint(AppColors.accent)
                    .frame(width: 520)

                    Text(DisplayFormatters.time(player.duration))
                        .frame(width: 46, alignment: .leading)
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(AppColors.tertiaryText)
            }
            .frame(width: 640)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                ModeCluster(selectedMode: $playbackMode)
                VolumeControl()
            }
            .frame(width: 260)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

private struct TransportButton: View {
    let systemImage: String
    var action: () -> Void
    let help: String

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -8))
        .help(help)
    }
}

private struct ModeCluster: View {
    @Binding var selectedMode: PlaybackMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlaybackMode.allCases) { mode in
                ModeButton(mode: mode, selectedMode: $selectedMode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct VolumeControl: View {
    @EnvironmentObject private var player: AudioPlayerService

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(AppColors.accent)
            Slider(value: $player.volume, in: 0...1)
                .tint(AppColors.accent)
        }
    }
}

private struct NowPlayingMini: View {
    @EnvironmentObject private var library: MusicLibraryStore
    let track: MusicTrack?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.flatMap { library.artworkURL(for: $0) }, size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(track?.displayTitle ?? "未播放")
                    .font(.system(size: 16, weight: .heavy))
                    .lineLimit(1)
                Text("\(track?.displayArtist ?? "-") - \(track?.displayAlbum ?? "-")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

private struct ModeButton: View {
    let mode: PlaybackMode
    @Binding var selectedMode: PlaybackMode

    var body: some View {
        Button {
            selectedMode = mode
        } label: {
            VStack(spacing: 3) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 18, weight: .bold))
                Text(mode.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(width: 62, height: 42)
            .foregroundStyle(selectedMode == mode ? AppColors.accent : AppColors.mutedText)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedMode == mode ? AppColors.accent.opacity(0.12) : AppColors.controlFill)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -6))
    }
}
