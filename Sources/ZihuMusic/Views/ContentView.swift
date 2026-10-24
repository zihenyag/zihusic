import AppKit
import ImageIO
import SwiftUI

extension Notification.Name {
    static let collapseZihuSearch = Notification.Name("collapseZihuSearch")
    static let toggleZihuSearch = Notification.Name("toggleZihuSearch")
    static let toggleZihuPlayback = Notification.Name("toggleZihuPlayback")
    static let nextZihuTrack = Notification.Name("nextZihuTrack")
    static let previousZihuTrack = Notification.Name("previousZihuTrack")
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
    static let shadow = Color.adaptive(
        light: (0.23, 0.15, 0.42, 0.12),
        dark: (0.00, 0.00, 0.00, 0.35)
    )
    static let searchStroke = Color.adaptive(
        light: (0.58, 0.51, 0.83, 0.24),
        dark: (0.77, 0.66, 1.00, 0.28)
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
    @AppStorage("playbackMode") private var playbackMode: PlaybackMode = .listLoop
    @AppStorage("isSidebarVisible") private var isSidebarVisible = true
    @State private var locateRequestID = 0
    @State private var hasResolvedInitialSelection = false
    @State private var wasSearching = false
    @State private var selectedDuringSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackdrop()

            HStack(spacing: 0) {
                if isSidebarVisible {
                    LibraryPane(
                        tracks: visibleTracks,
                        tracksRevision: library.visibleTracksRevision,
                        locateRequestID: locateRequestID,
                        selectedTrackID: $library.selectedTrackID,
                        play: play
                    )
                    .frame(width: TrackListMetrics.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(2)
                }

                PlaybackPane(track: activeTrack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
                    }
            }
            .animation(.easeInOut(duration: 0.25), value: isSidebarVisible)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                WindowEdgeBlur(edge: .top)
                    .frame(height: 68)
                Spacer(minLength: 0)
                WindowEdgeBlur(edge: .bottom)
                    .frame(height: 100)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(10)

            PlayerDock(
                playbackMode: $playbackMode,
                previous: playPrevious,
                toggle: togglePlayback,
                next: playNext
            )
            .frame(maxWidth: 950)
            .frame(height: TrackListMetrics.bottomGlassHeight)
            .padding(.horizontal, TrackListMetrics.bottomGlassInset)
            .padding(.bottom, TrackListMetrics.bottomGlassInset)
            .onTapGesture {
                NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
            }
            .zIndex(20)
        }
        .overlay(alignment: .topLeading) {
            UnifiedAppChrome(
                isSidebarVisible: $isSidebarVisible,
                searchText: $library.searchText,
                locateSelection: locateSelectedTrack
            )
            .padding(.leading, TrackListMetrics.chromeHorizontalInset)
            .padding(.top, TrackListMetrics.chromeTopInset)
            .zIndex(40)
            .ignoresSafeArea(edges: .top)
        }
        .foregroundStyle(AppColors.primaryText)
        .background(WindowStandardButtonHider())
        .alert("播放失败", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("好") { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZihuPlayback)) { _ in togglePlayback() }
        .onReceive(NotificationCenter.default.publisher(for: .nextZihuTrack)) { _ in playNext() }
        .onReceive(NotificationCenter.default.publisher(for: .previousZihuTrack)) { _ in playPrevious() }
        .onAppear {
            player.onFinished = { handleFinished() }
            resolveInitialOrSearchSelection()
        }
        .onChange(of: library.visibleTracksRevision) { _, _ in
            resolveInitialOrSearchSelection()
        }
        .onChange(of: library.selectedTrackID) { _, selectedTrackID in
            guard !normalizedSearchText.isEmpty, selectedTrackID != nil else { return }
            selectedDuringSearch = true
        }
    }

    private var activeTrack: MusicTrack? {
        player.currentTrack ?? library.selectedTrack ?? visibleTracks.first
    }

    private var visibleTracks: [MusicTrack] {
        library.visibleTracks
    }

    private var normalizedSearchText: String {
        library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func play(_ track: MusicTrack) {
        library.selectedTrackID = track.id
        player.play(track)
    }

    private func locateSelectedTrack() {
        NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
        locateRequestID += 1
    }

    private func resolveInitialOrSearchSelection() {
        guard let firstVisibleTrack = visibleTracks.first else { return }

        if !normalizedSearchText.isEmpty {
            wasSearching = true
            if library.selectedTrackID != firstVisibleTrack.id {
                library.selectedTrackID = firstVisibleTrack.id
            }
            selectedDuringSearch = true
            locateRequestID += 1
            return
        }

        if wasSearching {
            let shouldLocateSearchSelection = selectedDuringSearch
                && library.selectedTrackID.map { selectedID in
                    visibleTracks.contains { $0.id == selectedID }
                } == true
            wasSearching = false
            selectedDuringSearch = false

            if shouldLocateSearchSelection {
                locateRequestID += 1
                return
            }
        }

        guard !hasResolvedInitialSelection else { return }
        hasResolvedInitialSelection = true

        if let selectedTrackID = library.selectedTrackID,
           visibleTracks.contains(where: { $0.id == selectedTrackID }) {
            locateRequestID += 1
            return
        }

        library.selectedTrackID = firstVisibleTrack.id
        locateRequestID += 1
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

}

/// Fade the backdrop blur toward the content, keeping both floating control
/// layers above it. A material mask samples the live content beneath the edge.
private struct WindowEdgeBlur: View {
    @Environment(\.colorScheme) private var colorScheme
    let edge: VerticalEdge

    var body: some View {
        ZStack {
            AdaptiveBackdropBlur(isDark: colorScheme == .dark)
            if colorScheme == .dark {
                Color.black.opacity(0.78)
            } else {
                Color.white.opacity(0.12)
            }
        }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.85), location: 0.25),
                        .init(color: .white.opacity(0.35), location: 0.65),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: edge == .top ? .top : .bottom,
                    endPoint: edge == .top ? .bottom : .top
                )
            }
    }
}

private struct AdaptiveBackdropBlur: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        view.material = .hudWindow
        view.isEmphasized = false
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

private struct AppBackdrop: View {
    var body: some View {
        AppColors.background
        .ignoresSafeArea()
    }
}

private enum TrackListMetrics {
    static let tableHorizontalInset: CGFloat = 8
    static let tableRowHeight: CGFloat = 34
    static let topBlankRowHeight: CGFloat = 40
    static let bottomGlassHeight: CGFloat = 94
    static let bottomGlassInset: CGFloat = 16
    static let bottomContentInset: CGFloat = bottomGlassHeight + bottomGlassInset * 2
    static let bottomGlassCornerRadius: CGFloat = 25
    static let artworkSize: CGFloat = 22
    static let columnUnit: CGFloat = 34
    static let coverColumnWidth: CGFloat = columnUnit
    static let titleColumnWidth: CGFloat = columnUnit * 3
    static let artistColumnWidth: CGFloat = columnUnit * 2
    static let durationColumnWidth: CGFloat = columnUnit * 1.5
    static let columnTextInset: CGFloat = 4
    static let playingColumnWidth: CGFloat = columnUnit * 0.8
    static let tableContentWidth: CGFloat = coverColumnWidth
        + titleColumnWidth
        + artistColumnWidth
        + durationColumnWidth
        + playingColumnWidth
    static let sidebarWidth: CGFloat = tableContentWidth + tableHorizontalInset * 2
    static let chromeTopInset: CGFloat = 10
    static let chromeHeight: CGFloat = 34
    static var autoScrollTopPadding: CGFloat {
        topBlankRowHeight
    }
    static let chromeHorizontalInset: CGFloat = 14
    static let chromeWidth: CGFloat = sidebarWidth - chromeHorizontalInset * 2
    static let chromeContentInset: CGFloat = 8
    static let chromeControlGap: CGFloat = 8
    static let trafficLightsWidth: CGFloat = 48
    static let locateButtonWidth: CGFloat = 30
    static let sidebarToggleWidth: CGFloat = 30
    static let collapsedChromeWidth: CGFloat = chromeContentInset * 2
        + trafficLightsWidth
        + chromeControlGap
        + sidebarToggleWidth
    static let searchExpandedLeadingX: CGFloat = chromeContentInset
        + trafficLightsWidth
        + chromeControlGap
        + 4
    static let searchTrailingInset: CGFloat = chromeContentInset
    static let searchCollapsedWidth: CGFloat = 30
    static var searchExpandedWidth: CGFloat {
        max(0, chromeWidth - searchExpandedLeadingX - searchTrailingInset)
    }
    static var sidebarToggleCenterX: CGFloat {
        chromeWidth - chromeContentInset - sidebarToggleWidth / 2
    }
    static var locateButtonCenterX: CGFloat {
        sidebarToggleCenterX - sidebarToggleWidth / 2 - chromeControlGap - locateButtonWidth / 2
    }
    static var greenLightCenterX: CGFloat {
        chromeContentInset + 42
    }
    static var searchCollapsedCenterX: CGFloat {
        (greenLightCenterX + locateButtonCenterX) / 2
    }
}

private struct LibraryPane: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    let tracks: [MusicTrack]
    let tracksRevision: Int
    let locateRequestID: Int
    @Binding var selectedTrackID: MusicTrack.ID?
    var play: (MusicTrack) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.sidebarBackground
                .ignoresSafeArea(edges: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
                }

            LibraryTrackTableView(
                tracks: tracks,
                tracksRevision: tracksRevision,
                locateRequestID: locateRequestID,
                selectedTrackID: $selectedTrackID,
                playingTrackID: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                artworkURL: { library.artworkURL(for: $0) },
                play: play
            )

            if let progress = library.importProgress {
                LibraryImportProgressOverlay(progress: progress)
                    .padding(.horizontal, 18)
                    .padding(.top, 82)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: library.importProgress)
    }
}

private struct LibraryImportProgressOverlay: View {
    let progress: LibraryImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(progress.phase)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(AppColors.accent)

            MarqueeText(
                text: progress.detail,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: AppNSColors.tertiaryText
            )
            .frame(height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.separator.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: AppColors.shadow.opacity(0.35), radius: 14, y: 8)
    }
}

private extension NSColor {
    static func zihuAdaptive(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                red: value.0,
                green: value.1,
                blue: value.2,
                alpha: value.3
            )
        }
    }
}

private enum AppNSColors {
    static let selectedRow = NSColor.zihuAdaptive(
        light: (0.47, 0.34, 0.86, 0.18),
        dark: (0.58, 0.41, 1.00, 0.24)
    )
    static let primaryText = NSColor.zihuAdaptive(
        light: (0.16, 0.14, 0.31, 1),
        dark: (0.88, 0.84, 0.97, 1)
    )
    static let secondaryText = NSColor.zihuAdaptive(
        light: (0.32, 0.28, 0.50, 1),
        dark: (0.74, 0.68, 0.88, 1)
    )
    static let tertiaryText = NSColor.zihuAdaptive(
        light: (0.45, 0.40, 0.60, 1),
        dark: (0.58, 0.52, 0.72, 1)
    )
    static let accent = NSColor.zihuAdaptive(
        light: (0.38, 0.25, 0.76, 1),
        dark: (0.74, 0.59, 1.00, 1)
    )
    static let placeholderFill = NSColor.zihuAdaptive(
        light: (0.50, 0.45, 0.72, 0.18),
        dark: (0.74, 0.62, 1.00, 0.18)
    )
}

private final class LibraryScrollView: NSScrollView {
    private let floatingIndicator = FloatingScrollIndicatorView()
    private var boundsObserver: NSObjectProtocol?
    private var fadeWorkItem: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScroller?.isHidden = true
        verticalScroller?.controlSize = .small
        horizontalScroller?.isHidden = true
        setupFloatingIndicatorIfNeeded()
        observeContentBounds()
        updateFloatingIndicator(animated: false)
    }

    override func layout() {
        super.layout()
        updateFloatingIndicator(animated: false)
    }

    override func scrollWheel(with event: NSEvent) {
        showFloatingIndicator()
        super.scrollWheel(with: event)
        updateFloatingIndicator(animated: false)
        scheduleIndicatorFade()
    }

    private func setupFloatingIndicatorIfNeeded() {
        guard floatingIndicator.superview == nil else { return }
        floatingIndicator.alphaValue = 0
        floatingIndicator.isHidden = true
        addSubview(floatingIndicator)
    }

    private func observeContentBounds() {
        guard boundsObserver == nil else { return }
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.showFloatingIndicator()
            self?.updateFloatingIndicator(animated: false)
            self?.scheduleIndicatorFade()
        }
    }

    private func updateFloatingIndicator(animated: Bool) {
        guard let documentView else {
            floatingIndicator.isHidden = true
            return
        }

        let viewportHeight = max(contentView.bounds.height, 1)
        let contentHeight = max(documentView.bounds.height, viewportHeight)
        guard contentHeight > viewportHeight + 1 else {
            floatingIndicator.isHidden = true
            return
        }

        let trackTop: CGFloat = 12
        let trackBottom: CGFloat = 12
        let trackHeight = max(bounds.height - trackTop - trackBottom, 1)
        let thumbHeight = max(32, trackHeight * viewportHeight / contentHeight)
        let maxThumbY = max(trackHeight - thumbHeight, 0)
        let scrollY = min(max(contentView.bounds.minY, 0), contentHeight - viewportHeight)
        let progress = scrollY / max(contentHeight - viewportHeight, 1)
        let thumbY = trackBottom + progress * maxThumbY
        let frame = NSRect(
            x: bounds.width - 9,
            y: thumbY,
            width: 4,
            height: thumbHeight
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                floatingIndicator.animator().frame = frame
            }
        } else {
            floatingIndicator.frame = frame
        }
        floatingIndicator.needsDisplay = true
    }

    private func showFloatingIndicator() {
        updateFloatingIndicator(animated: false)
        guard !floatingIndicator.isHidden || documentView != nil else { return }
        floatingIndicator.isHidden = false
        fadeWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            floatingIndicator.animator().alphaValue = 1
        }
    }

    private func scheduleIndicatorFade() {
        fadeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                self.floatingIndicator.animator().alphaValue = 0
            } completionHandler: {
                self.floatingIndicator.isHidden = true
            }
        }
        fadeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72, execute: item)
    }
}

private final class FloatingScrollIndicatorView: NSView {
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.34)
                : NSColor.black.withAlphaComponent(0.24)
        }
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.width / 2, yRadius: bounds.width / 2).fill()
    }
}

private final class LibraryTableView: NSTableView {
    override var acceptsFirstResponder: Bool { true }
}

private enum LibraryTableColumn: String, CaseIterable {
    case cover
    case title
    case artist
    case duration
    case playing

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("zihu.\(rawValue)")
    }

    init?(identifier: NSUserInterfaceItemIdentifier) {
        self.init(rawValue: identifier.rawValue.replacingOccurrences(of: "zihu.", with: ""))
    }
}

private struct LibraryTrackTableView: NSViewRepresentable {
    let tracks: [MusicTrack]
    let tracksRevision: Int
    let locateRequestID: Int
    @Binding var selectedTrackID: MusicTrack.ID?
    let playingTrackID: MusicTrack.ID?
    let isPlaying: Bool
    let artworkURL: (MusicTrack) -> URL?
    let play: (MusicTrack) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> LibraryScrollView {
        let scrollView = LibraryScrollView()
        configure(scrollView)

        let tableView = LibraryTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.enclosingScrollView?.drawsBackground = false
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = TrackListMetrics.tableRowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.tableClicked(_:))

        LibraryTableColumn.allCases.forEach { tableColumn in
            let column = NSTableColumn(identifier: tableColumn.identifier)
            column.title = ""
            column.resizingMask = []
            column.isEditable = false
            tableView.addTableColumn(column)
        }

        scrollView.documentView = tableView
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: TrackListMetrics.tableHorizontalInset,
            bottom: 0,
            right: TrackListMetrics.tableHorizontalInset
        )
        scrollView.scrollerInsets = NSEdgeInsetsZero

        context.coordinator.tableView = tableView
        context.coordinator.resizeColumns()
        context.coordinator.reloadAndSyncSelection(centerSelected: true, animatedScroll: false)
        return scrollView
    }

    func updateNSView(_ scrollView: LibraryScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded()
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller?.isHidden = true
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.isHidden = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let rowIdentifier = NSUserInterfaceItemIdentifier("trackRow")
        private static let spacerIdentifier = NSUserInterfaceItemIdentifier("spacerCell")
        private static let artworkCellIdentifier = NSUserInterfaceItemIdentifier("artworkCell")
        private static let titleCellIdentifier = NSUserInterfaceItemIdentifier("titleCell")
        private static let artistCellIdentifier = NSUserInterfaceItemIdentifier("artistCell")
        private static let durationCellIdentifier = NSUserInterfaceItemIdentifier("durationCell")
        private static let playingCellIdentifier = NSUserInterfaceItemIdentifier("playingCell")

        var parent: LibraryTrackTableView
        weak var tableView: NSTableView?
        private var lastSnapshot: RenderSnapshot?
        private var suppressAutoLocateForTrackID: MusicTrack.ID?

        init(_ parent: LibraryTrackTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.tracks.count + 2
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if row == 0 {
                return TrackListMetrics.topBlankRowHeight
            }
            if row == bottomSpacerRow {
                return TrackListMetrics.bottomContentInset
            }
            return TrackListMetrics.tableRowHeight
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = tableView.makeView(withIdentifier: Self.rowIdentifier, owner: self) as? LibraryTrackRowView
                ?? LibraryTrackRowView()
            rowView.identifier = Self.rowIdentifier
            return rowView
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            trackIndex(forTableRow: row) != nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn,
                  let column = LibraryTableColumn(identifier: tableColumn.identifier) else {
                return nil
            }

            guard let trackIndex = trackIndex(forTableRow: row) else {
                return tableView.makeView(withIdentifier: Self.spacerIdentifier, owner: self) ?? spacerView()
            }
            guard parent.tracks.indices.contains(trackIndex) else { return nil }

            switch column {
            case .cover:
                let cell = tableView.makeView(withIdentifier: Self.artworkCellIdentifier, owner: self) as? LibraryArtworkCellView
                    ?? LibraryArtworkCellView()
                cell.identifier = Self.artworkCellIdentifier
                configure(cell, trackIndex: trackIndex)
                return cell
            case .title:
                let cell = tableView.makeView(withIdentifier: Self.titleCellIdentifier, owner: self) as? LibraryTextCellView
                    ?? LibraryTextCellView()
                cell.identifier = Self.titleCellIdentifier
                configure(cell, column: .title, trackIndex: trackIndex)
                return cell
            case .artist:
                let cell = tableView.makeView(withIdentifier: Self.artistCellIdentifier, owner: self) as? LibraryTextCellView
                    ?? LibraryTextCellView()
                cell.identifier = Self.artistCellIdentifier
                configure(cell, column: .artist, trackIndex: trackIndex)
                return cell
            case .duration:
                let cell = tableView.makeView(withIdentifier: Self.durationCellIdentifier, owner: self) as? LibraryTextCellView
                    ?? LibraryTextCellView()
                cell.identifier = Self.durationCellIdentifier
                configure(cell, column: .duration, trackIndex: trackIndex)
                return cell
            case .playing:
                let cell = tableView.makeView(withIdentifier: Self.playingCellIdentifier, owner: self) as? LibraryPlayingCellView
                    ?? LibraryPlayingCellView()
                cell.identifier = Self.playingCellIdentifier
                configure(cell, trackIndex: trackIndex)
                return cell
            }
        }

        @objc func tableClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard let trackIndex = trackIndex(forTableRow: row),
                  parent.tracks.indices.contains(trackIndex) else { return }
            let track = parent.tracks[trackIndex]
            NotificationCenter.default.post(name: .collapseZihuSearch, object: nil)
            parent.selectedTrackID = track.id
            sender.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            reloadVisibleCells()
            lastSnapshot = currentSnapshot()
            suppressAutoLocateForTrackID = track.id
            parent.play(track)
        }

        func syncIfNeeded() {
            let snapshot = currentSnapshot()
            guard let previous = lastSnapshot, snapshot != previous else { return }

            let locateRequested = snapshot.locateRequestID != previous.locateRequestID
            let playingTrackChanged = snapshot.playingTrackID != previous.playingTrackID
            let clickPlayShouldStayPut = playingTrackChanged
                && snapshot.playingTrackID == suppressAutoLocateForTrackID

            if clickPlayShouldStayPut {
                suppressAutoLocateForTrackID = nil
            }

            let shouldCenterSelected = locateRequested || (playingTrackChanged && !clickPlayShouldStayPut)
            reloadAndSyncSelection(centerSelected: shouldCenterSelected, animatedScroll: lastSnapshot != nil)
        }

        func reloadAndSyncSelection(centerSelected: Bool = false, animatedScroll: Bool = false) {
            guard let tableView else { return }
            if tableView.numberOfRows != parent.tracks.count + 2 {
                tableView.reloadData()
            } else {
                reloadVisibleCells()
            }

            if let selectedTrackID = parent.selectedTrackID,
               let trackIndex = parent.tracks.firstIndex(where: { $0.id == selectedTrackID }) {
                let tableRow = trackIndex + 1
                tableView.selectRowIndexes(IndexSet(integer: tableRow), byExtendingSelection: false)
                if centerSelected {
                    centerRowInViewport(tableRow, animated: animatedScroll)
                }
            } else {
                tableView.deselectAll(nil)
            }
            lastSnapshot = currentSnapshot()
        }

        private var bottomSpacerRow: Int {
            parent.tracks.count + 1
        }

        private func trackIndex(forTableRow row: Int) -> Int? {
            guard row > 0, row < bottomSpacerRow else { return nil }
            return row - 1
        }

        private func spacerView() -> NSView {
            let view = NSView(frame: .zero)
            view.identifier = Self.spacerIdentifier
            return view
        }

        private func centerRowInViewport(_ row: Int, animated: Bool) {
            guard let tableView,
                  row >= 0,
                  row < tableView.numberOfRows,
                  let scrollView = tableView.enclosingScrollView else {
                return
            }

            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            guard rowRect.height > 0 else { return }

            let clipView = scrollView.contentView
            let viewportHeight = clipView.bounds.height
            guard viewportHeight > 0 else {
                DispatchQueue.main.async { [weak self] in
                    self?.centerRowInViewport(row, animated: animated)
                }
                return
            }

            let maxY = max(0, tableView.bounds.height - viewportHeight)
            let centeredY = rowRect.midY - viewportHeight / 2
            let targetY = min(max(0, centeredY), maxY)
            guard abs(clipView.bounds.origin.y - targetY) > 1 else {
                ensureRowTopPadding(row)
                scheduleRowTopPaddingCorrection(row)
                return
            }

            let targetPoint = NSPoint(x: clipView.bounds.origin.x, y: targetY)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    clipView.animator().setBoundsOrigin(targetPoint)
                } completionHandler: {
                    scrollView.reflectScrolledClipView(clipView)
                    self.ensureRowTopPadding(row)
                    self.scheduleRowTopPaddingCorrection(row)
                }
            } else {
                clipView.scroll(to: targetPoint)
                scrollView.reflectScrolledClipView(clipView)
                ensureRowTopPadding(row)
                scheduleRowTopPaddingCorrection(row)
            }
        }

        private func scheduleRowTopPaddingCorrection(_ row: Int) {
            DispatchQueue.main.async { [weak self] in
                self?.ensureRowTopPadding(row)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.ensureRowTopPadding(row)
            }
        }

        private func ensureRowTopPadding(_ row: Int) {
            guard let tableView,
                  row >= 0,
                  row < tableView.numberOfRows,
                  let scrollView = tableView.enclosingScrollView else {
                return
            }

            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            let visibleRect = tableView.visibleRect
            let topGap = currentTopGap(rowRect: rowRect, visibleRect: visibleRect)
            let topPadding = TrackListMetrics.autoScrollTopPadding
            guard topGap < topPadding - 0.5 else { return }

            let maxY = max(0, tableView.bounds.height - visibleRect.height)
            let targetY = min(max(0, topPaddingScrollY(rowRect: rowRect, visibleHeight: visibleRect.height)), maxY)
            let clipView = scrollView.contentView
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func currentTopGap(rowRect: NSRect, visibleRect: NSRect) -> CGFloat {
            if tableView?.isFlipped == true {
                return rowRect.minY - visibleRect.minY
            }
            return visibleRect.maxY - rowRect.maxY
        }

        private func topPaddingScrollY(rowRect: NSRect, visibleHeight: CGFloat) -> CGFloat {
            let topPadding = TrackListMetrics.autoScrollTopPadding
            if tableView?.isFlipped == true {
                return rowRect.minY - topPadding
            }
            return rowRect.maxY + topPadding - visibleHeight
        }

        private func reloadVisibleCells() {
            guard let tableView else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }

            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard let trackIndex = trackIndex(forTableRow: row) else { continue }

                for columnIndex in 0..<tableView.numberOfColumns {
                    guard let column = LibraryTableColumn(identifier: tableView.tableColumns[columnIndex].identifier) else {
                        continue
                    }

                    let view = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: false)
                    configure(view, column: column, trackIndex: trackIndex)
                }
            }
        }

        private func configure(_ view: NSView?, column: LibraryTableColumn, trackIndex: Int) {
            switch (view, column) {
            case let (cell as LibraryArtworkCellView, .cover):
                configure(cell, trackIndex: trackIndex)
            case let (cell as LibraryTextCellView, .title):
                configure(cell, column: .title, trackIndex: trackIndex)
            case let (cell as LibraryTextCellView, .artist):
                configure(cell, column: .artist, trackIndex: trackIndex)
            case let (cell as LibraryTextCellView, .duration):
                configure(cell, column: .duration, trackIndex: trackIndex)
            case let (cell as LibraryPlayingCellView, .playing):
                configure(cell, trackIndex: trackIndex)
            default:
                break
            }
        }

        private func configure(_ cell: LibraryArtworkCellView, trackIndex: Int) {
            let track = parent.tracks[trackIndex]
            cell.configure(artworkURL: parent.artworkURL(track))
        }

        private func configure(_ cell: LibraryTextCellView, column: LibraryTableColumn, trackIndex: Int) {
            let track = parent.tracks[trackIndex]
            let isSelected = parent.selectedTrackID == track.id

            switch column {
            case .title:
                cell.configure(
                    text: track.displayTitle,
                    font: .systemFont(ofSize: 13, weight: .medium),
                    color: isSelected ? AppNSColors.accent : AppNSColors.primaryText,
                    alignment: .left
                )
            case .artist:
                cell.configure(
                    text: track.displayArtist,
                    font: .systemFont(ofSize: 12, weight: .medium),
                    color: AppNSColors.secondaryText,
                    alignment: .left
                )
            case .duration:
                cell.configure(
                    text: DisplayFormatters.time(track.duration),
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    color: isSelected ? AppNSColors.accent : AppNSColors.tertiaryText,
                    alignment: .right
                )
            case .cover, .playing:
                break
            }
        }

        private func configure(_ cell: LibraryPlayingCellView, trackIndex: Int) {
            let track = parent.tracks[trackIndex]
            cell.configure(isPlaying: parent.playingTrackID == track.id && parent.isPlaying)
        }

        func resizeColumns() {
            guard tableView != nil else { return }
            setColumn(.cover, width: TrackListMetrics.coverColumnWidth)
            setColumn(.title, width: TrackListMetrics.titleColumnWidth)
            setColumn(.artist, width: TrackListMetrics.artistColumnWidth)
            setColumn(.duration, width: TrackListMetrics.durationColumnWidth)
            setColumn(.playing, width: TrackListMetrics.playingColumnWidth)
        }

        private func setColumn(_ tableColumn: LibraryTableColumn, width: CGFloat) {
            guard let column = tableView?.tableColumn(withIdentifier: tableColumn.identifier) else { return }
            let adjustedWidth = max(1, width)
            column.maxWidth = .greatestFiniteMagnitude
            column.minWidth = 0
            column.width = adjustedWidth
            column.minWidth = adjustedWidth
            column.maxWidth = adjustedWidth
        }

        private func currentSnapshot() -> RenderSnapshot {
            RenderSnapshot(
                tracksRevision: parent.tracksRevision,
                locateRequestID: parent.locateRequestID,
                rowCount: parent.tracks.count,
                selectedTrackID: parent.selectedTrackID,
                playingTrackID: parent.playingTrackID,
                isPlaying: parent.isPlaying
            )
        }

        private struct RenderSnapshot: Equatable {
            let tracksRevision: Int
            let locateRequestID: Int
            let rowCount: Int
            let selectedTrackID: MusicTrack.ID?
            let playingTrackID: MusicTrack.ID?
            let isPlaying: Bool
        }
    }
}

private final class LibraryTrackRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }

        AppNSColors.selectedRow.setFill()
        let rect = bounds.insetBy(dx: 0, dy: 1.5)
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawBackground(in: dirtyRect)
    }
}

private final class LibraryArtworkCellView: NSTableCellView {
    private let artworkView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.image = nil
    }

    func configure(artworkURL: URL?) {
        artworkView.image = SidebarArtworkCache.image(for: artworkURL)
    }

    private func setup() {
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.imageScaling = .scaleAxesIndependently
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 4
        artworkView.layer?.masksToBounds = true
        artworkView.layer?.backgroundColor = AppNSColors.placeholderFill.cgColor

        addSubview(artworkView)

        NSLayoutConstraint.activate([
            artworkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: TrackListMetrics.artworkSize),
            artworkView.heightAnchor.constraint(equalToConstant: TrackListMetrics.artworkSize)
        ])
    }
}

private final class LibraryTextCellView: NSTableCellView {
    private let clipView = NSView()
    private let label = NSTextField(labelWithString: "")
    private let textRenderPadding: CGFloat = 8
    private var currentText = ""
    private var currentFont = NSFont.systemFont(ofSize: 13)
    private var currentAlignment: NSTextAlignment = .left

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let changed = currentText != text || currentFont != font || currentAlignment != alignment
        currentText = text
        currentFont = font
        currentAlignment = alignment
        label.stringValue = text
        label.font = font
        label.textColor = color
        label.alignment = alignment
        if changed {
            stopMarquee()
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let inset = TrackListMetrics.columnTextInset
        let availableWidth = max(0, bounds.width - inset * 2)
        let textSize = label.intrinsicContentSize
        let textWidth = ceil(textSize.width)
        let renderPadding = currentAlignment == .right ? 0 : textRenderPadding
        let labelWidth = max(availableWidth, textWidth + renderPadding)
        let labelHeight = ceil(textSize.height)
        let y = max(0, (bounds.height - labelHeight) / 2)
        let x: CGFloat

        switch currentAlignment {
        case .right:
            x = inset + max(0, availableWidth - labelWidth)
        case .center:
            x = inset + max(0, (availableWidth - labelWidth) / 2)
        default:
            x = inset
        }

        clipView.frame = bounds.insetBy(dx: inset, dy: 0)
        label.frame = NSRect(x: x - inset, y: y, width: labelWidth, height: labelHeight)
        updateMarquee(availableWidth: availableWidth, textWidth: textWidth)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        addSubview(clipView)

        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.wantsLayer = true
        clipView.addSubview(label)
    }

    private func updateMarquee(availableWidth: CGFloat, textWidth: CGFloat) {
        guard availableWidth > 0 else { return }
        let overflow = textWidth - availableWidth
        guard overflow > 3, currentAlignment != .right else {
            stopMarquee()
            return
        }

        if label.layer?.animation(forKey: "marquee") != nil {
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -overflow - 14, -overflow - 14, 0]
        animation.keyTimes = [0, 0.18, 0.62, 0.82, 1]
        animation.duration = max(6.0, min(14.0, Double(overflow) / 18.0 + 5.0))
        animation.repeatCount = .infinity
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        label.layer?.add(animation, forKey: "marquee")
    }

    private func stopMarquee() {
        label.layer?.removeAnimation(forKey: "marquee")
    }
}

private final class LibraryPlayingCellView: NSTableCellView {
    private let playingIndicator = PlayingIndicatorView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        playingIndicator.setAnimating(false)
    }

    func configure(isPlaying: Bool) {
        playingIndicator.setAnimating(isPlaying)
        playingIndicator.updateColor()
    }

    private func setup() {
        playingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playingIndicator)

        NSLayoutConstraint.activate([
            playingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            playingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            playingIndicator.widthAnchor.constraint(equalToConstant: 14),
            playingIndicator.heightAnchor.constraint(equalToConstant: 14)
        ])
    }
}

private final class PlayingIndicatorView: NSView {
    private let bars = [CALayer(), CALayer(), CALayer()]
    private var animating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        let barWidth: CGFloat = 2.5
        let gap: CGFloat = 2.5
        let height: CGFloat = min(13, bounds.height)
        let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        let startY = (bounds.height - height) / 2

        for (index, bar) in bars.enumerated() {
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: startY,
                width: barWidth,
                height: height
            )
        }
    }

    func setAnimating(_ active: Bool) {
        guard active != animating else { return }
        animating = active
        isHidden = !active
        active ? startAnimation() : stopAnimation()
    }

    func updateColor() {
        bars.forEach { $0.backgroundColor = AppNSColors.accent.cgColor }
    }

    private func setup() {
        wantsLayer = true
        isHidden = true
        bars.forEach { bar in
            bar.backgroundColor = AppNSColors.accent.cgColor
            bar.cornerRadius = 1.5
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(bar)
        }
    }

    private func startAnimation() {
        updateColor()
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = [0.35, 0.70, 0.48][index]
            animation.toValue = [1.0, 0.42, 0.92][index]
            animation.duration = [0.48, 0.42, 0.54][index]
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.10
            bar.add(animation, forKey: "playing")
        }
    }

    private func stopAnimation() {
        bars.forEach { bar in
            bar.removeAllAnimations()
            bar.transform = CATransform3DIdentity
        }
    }
}

private enum SidebarArtworkCache {
    static let shared = NSCache<NSString, NSImage>()

    static func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        let key = url.path as NSString
        if let cached = shared.object(forKey: key) {
            return cached
        }

        let image = thumbnail(from: url) ?? NSImage(contentsOf: url)
        if let image {
            shared.setObject(image, forKey: key)
        }
        return image
    }

    private static func thumbnail(from url: URL) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 88
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: 44, height: 44))
    }
}

private struct UnifiedAppChrome: View {
    @Binding var isSidebarVisible: Bool
    @Binding var searchText: String
    let locateSelection: () -> Void
    @State private var isSearchExpanded = false

    private var rightButtonOpacity: Double {
        isSidebarVisible && !isSearchExpanded ? 1 : 0
    }

    private var sidebarToggleX: CGFloat {
        if isSidebarVisible {
            return TrackListMetrics.sidebarToggleCenterX
        }
        return TrackListMetrics.chromeContentInset
            + TrackListMetrics.trafficLightsWidth
            + TrackListMetrics.chromeControlGap
            + TrackListMetrics.sidebarToggleWidth / 2
    }

    private var searchWidth: CGFloat {
        isSearchExpanded ? TrackListMetrics.searchExpandedWidth : TrackListMetrics.searchCollapsedWidth
    }

    private var searchCenterX: CGFloat {
        if isSearchExpanded {
            return TrackListMetrics.searchExpandedLeadingX + searchWidth / 2
        }
        return TrackListMetrics.searchCollapsedCenterX
    }

    private func toggleSearchFromShortcut() {
        if isSearchExpanded {
            searchText = ""
            isSearchExpanded = false
        } else {
            if !isSidebarVisible {
                withAnimation(.easeInOut(duration: 0.20)) {
                    isSidebarVisible = true
                }
            }
            isSearchExpanded = true
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 6) {
                WindowDotButton(color: Color(red: 1.00, green: 0.34, blue: 0.31)) {
                    NSApp.keyWindow?.performClose(nil)
                }

                WindowDotButton(color: Color(red: 1.00, green: 0.77, blue: 0.20)) {
                    NSApp.keyWindow?.miniaturize(nil)
                }

                WindowDotButton(color: Color(red: 0.18, green: 0.78, blue: 0.27)) {
                    (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
                }
                .help("进入或退出全屏")
                .accessibilityLabel("全屏")
            }
            .frame(width: TrackListMetrics.trafficLightsWidth, height: 30, alignment: .leading)
            .position(
                x: TrackListMetrics.chromeContentInset + TrackListMetrics.trafficLightsWidth / 2,
                y: TrackListMetrics.chromeHeight / 2
            )

            HoverSearchBar(text: $searchText, width: searchWidth, isExpanded: $isSearchExpanded)
                .opacity(isSidebarVisible ? 1 : 0)
                .allowsHitTesting(isSidebarVisible)
                .position(
                    x: searchCenterX,
                    y: TrackListMetrics.chromeHeight / 2
                )

            Button {
                locateSelection()
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("定位当前歌曲")
            .frame(width: TrackListMetrics.locateButtonWidth, height: 30)
            .opacity(rightButtonOpacity)
            .allowsHitTesting(rightButtonOpacity > 0)
            .position(
                x: TrackListMetrics.locateButtonCenterX,
                y: TrackListMetrics.chromeHeight / 2
            )

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: isSidebarVisible ? "sidebar.leading" : "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(isSidebarVisible ? "收起边栏" : "展开边栏")
            .frame(width: TrackListMetrics.sidebarToggleWidth, height: 30)
            .opacity(isSearchExpanded ? 0 : 1)
            .allowsHitTesting(!isSearchExpanded)
            .position(
                x: sidebarToggleX,
                y: TrackListMetrics.chromeHeight / 2
            )
        }
        .frame(
            width: isSidebarVisible ? TrackListMetrics.chromeWidth : TrackListMetrics.collapsedChromeWidth,
            height: TrackListMetrics.chromeHeight,
            alignment: .leading
        )
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppColors.searchStroke.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: AppColors.shadow.opacity(0.40), radius: 12, y: 5)
        .animation(.easeInOut(duration: 0.18), value: isSidebarVisible)
        .animation(.easeInOut(duration: 0.12), value: isSearchExpanded)
        .onChange(of: isSidebarVisible) { _, visible in
            if !visible {
                isSearchExpanded = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZihuSearch)) { _ in
            toggleSearchFromShortcut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseZihuSearch)) { _ in
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchExpanded = false
            }
        }
    }
}

private struct WindowDotButton: View {
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.16), lineWidth: 0.8)
                }
                .frame(width: 10.5, height: 10.5)
        }
        .buttonStyle(.plain)
        .frame(width: 12, height: 15)
        .contentShape(Rectangle())
    }
}

private struct HoverSearchBar: View {
    @Binding var text: String
    let width: CGFloat
    @Binding var isExpanded: Bool
    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var suppressHoverExpansion = false

    private var fieldWidth: CGFloat {
        max(0, width - TrackListMetrics.searchCollapsedWidth - 31)
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppColors.primaryText)
                .frame(width: TrackListMetrics.searchCollapsedWidth, height: 30)

            if isExpanded {
                TextField("搜索歌曲/歌手/专辑", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .focused($focused)
                    .frame(width: fieldWidth)
                    .transition(.opacity)

                Button {
                    closeSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.78))
                        .frame(width: 18, height: 30)
                }
                .buttonStyle(.plain)
                .help("关闭搜索")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 0)
        .frame(width: width, height: 30, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            openSearch()
        }
        .onHover { inside in
            hovering = inside
            if inside {
                guard !suppressHoverExpansion else { return }
                openSearch()
            } else {
                suppressHoverExpansion = false
                if !hasText {
                    focused = false
                    isExpanded = false
                }
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !hovering && !focused {
                    isExpanded = false
                }
            } else {
                isExpanded = true
            }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                isExpanded = true
            } else if !hovering && !hasText {
                isExpanded = false
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                suppressHoverExpansion = false
                DispatchQueue.main.async {
                    focused = true
                }
            } else {
                if hovering {
                    suppressHoverExpansion = true
                }
                focused = false
            }
        }
        .animation(.easeInOut(duration: 0.10), value: isExpanded)
    }

    private func openSearch() {
        isExpanded = true
        DispatchQueue.main.async {
            focused = true
        }
    }

    private func closeSearch() {
        text = ""
        focused = false
        suppressHoverExpansion = true
        isExpanded = false
    }
}

private struct WindowStandardButtonHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            hideButtons(in: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            hideButtons(in: nsView.window)
        }
    }

    private func hideButtons(in window: NSWindow?) {
        guard let window else { return }
        // Progress updates also update this representable. Reapplying styleMask
        // on every tick can relayout the native lyric viewport mid-transition.
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        if !window.collectionBehavior.contains(.fullScreenPrimary) { window.collectionBehavior.insert(.fullScreenPrimary) }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if window.toolbar != nil { window.toolbar = nil }
        if window.isMovableByWindowBackground { window.isMovableByWindowBackground = false }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type), !button.isHidden { button.isHidden = true }
        }
    }
}

private struct MarqueeText: NSViewRepresentable {
    var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment = .left

    func makeNSView(context: Context) -> MarqueeTextView {
        let view = MarqueeTextView()
        view.configure(text: text, font: font, color: color, alignment: alignment)
        return view
    }

    func updateNSView(_ nsView: MarqueeTextView, context: Context) {
        nsView.configure(text: text, font: font, color: color, alignment: alignment)
    }
}

private final class MarqueeTextView: NSView {
    private let clipView = NSView()
    private let label = NSTextField(labelWithString: "")
    private var currentText = ""
    private var currentFont = NSFont.systemFont(ofSize: 13)
    private var currentAlignment: NSTextAlignment = .left

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        let size = label.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(size.height))
    }

    func configure(text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let changed = currentText != text
            || currentFont.fontName != font.fontName
            || currentFont.pointSize != font.pointSize
            || currentAlignment != alignment
        currentText = text
        currentFont = font
        currentAlignment = alignment
        label.stringValue = text
        label.font = font
        label.textColor = color
        label.alignment = alignment
        if changed {
            stopMarquee()
            invalidateIntrinsicContentSize()
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let availableWidth = max(bounds.width, 0)
        let textSize = label.intrinsicContentSize
        let labelWidth = max(availableWidth, ceil(textSize.width))
        let labelHeight = ceil(textSize.height)
        let y = max(0, (bounds.height - labelHeight) / 2)
        let overflows = labelWidth > availableWidth + 3
        let x: CGFloat

        if overflows {
            x = 0
        } else {
            switch currentAlignment {
            case .right:
                x = max(0, availableWidth - labelWidth)
            case .center:
                x = max(0, (availableWidth - labelWidth) / 2)
            default:
                x = 0
            }
        }

        clipView.frame = bounds
        label.frame = NSRect(x: x, y: y, width: labelWidth, height: labelHeight)
        updateMarquee(availableWidth: availableWidth, labelWidth: labelWidth)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        addSubview(clipView)

        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.wantsLayer = true
        clipView.addSubview(label)
    }

    private func updateMarquee(availableWidth: CGFloat, labelWidth: CGFloat) {
        let overflow = labelWidth - availableWidth
        guard availableWidth > 0, overflow > 3 else {
            stopMarquee()
            return
        }

        if label.layer?.animation(forKey: "marquee") != nil {
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -overflow - 18, -overflow - 18, 0]
        animation.keyTimes = [0, 0.18, 0.62, 0.82, 1]
        animation.duration = max(6.0, min(16.0, Double(overflow) / 18.0 + 5.0))
        animation.repeatCount = .infinity
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        label.layer?.add(animation, forKey: "marquee")
    }

    private func stopMarquee() {
        label.layer?.removeAnimation(forKey: "marquee")
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
    @EnvironmentObject private var player: AudioPlayerService
    let track: MusicTrack?
    @State private var editingField: HeroEditField?
    @State private var draftTitle = ""
    @State private var draftArtist = ""
    @State private var draftAlbum = ""
    @FocusState private var focusedField: HeroEditField?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ArtworkView(url: track.flatMap { library.artworkURL(for: $0) }, size: 276)
                .shadow(color: AppColors.shadow, radius: 22, y: 16)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard let track, let updated = library.chooseArtwork(for: track) else { return }
                    updatePlayerTrack(updated)
                    Task { await library.writeTags(for: updated) }
                }
                .help("双击更换封面")

            VStack(spacing: 9) {
                editableText(
                    field: .title,
                    text: track?.displayTitle ?? "未播放",
                    draft: $draftTitle,
                    font: .system(size: 33, weight: .heavy),
                    color: AppColors.primaryText,
                    marqueeFont: .systemFont(ofSize: 33, weight: .heavy),
                    marqueeColor: AppNSColors.primaryText,
                    displayHeight: 40
                )
                .padding(.top, 30)

                editableText(
                    field: .artist,
                    text: track?.displayArtist ?? "选择左侧歌曲",
                    draft: $draftArtist,
                    font: .system(size: 18, weight: .medium),
                    color: AppColors.secondaryText,
                    marqueeFont: .systemFont(ofSize: 18, weight: .medium),
                    marqueeColor: AppNSColors.secondaryText,
                    displayHeight: 24
                )

                editableText(
                    field: .album,
                    text: track?.displayAlbum ?? "-",
                    draft: $draftAlbum,
                    font: .system(size: 15, weight: .medium),
                    color: AppColors.tertiaryText,
                    marqueeFont: .systemFont(ofSize: 15, weight: .medium),
                    marqueeColor: AppNSColors.tertiaryText,
                    displayHeight: 20
                )

                if let track {
                    MarqueeText(
                        text: DisplayFormatters.technicalSummary(for: track),
                        font: .systemFont(ofSize: 13, weight: .medium),
                        color: AppNSColors.tertiaryText,
                        alignment: .center
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                }
            }

            Spacer(minLength: 90)
        }
        .offset(y: -40)
        .padding(.horizontal, 30)
        .onAppear { syncDrafts(from: track) }
        .onChange(of: track?.id) { _, _ in syncDrafts(from: track) }
        .onChange(of: editingField) { _, field in focusedField = field }
    }

    @ViewBuilder
    private func editableText(
        field: HeroEditField,
        text: String,
        draft: Binding<String>,
        font: Font,
        color: Color,
        marqueeFont: NSFont,
        marqueeColor: NSColor,
        displayHeight: CGFloat
    ) -> some View {
        if editingField == field {
            TextField("", text: draft)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .focused($focusedField, equals: field)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit { saveDraft() }
                .onExitCommand { cancelEditing() }
        } else {
            MarqueeText(text: text, font: marqueeFont, color: marqueeColor, alignment: .center)
                .frame(maxWidth: .infinity)
                .frame(height: displayHeight)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard track != nil else { return }
                    editingField = field
                }
                .help("双击编辑，回车保存")
        }
    }

    private func syncDrafts(from track: MusicTrack?) {
        draftTitle = track?.title ?? ""
        draftArtist = track?.displayArtist ?? ""
        draftAlbum = track?.album ?? ""
        editingField = nil
    }

    private func saveDraft() {
        guard var updated = track else { return }
        updated.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.artist = normalizedArtistInput(draftArtist)
        updated.album = draftAlbum.trimmingCharacters(in: .whitespacesAndNewlines)
        library.updateTrack(updated)
        updatePlayerTrack(updated)
        editingField = nil
        Task { await library.writeTags(for: updated) }
    }

    private func cancelEditing() {
        syncDrafts(from: track)
    }

    private func updatePlayerTrack(_ updated: MusicTrack) {
        if player.currentTrack?.id == updated.id {
            player.currentTrack = updated
        }
    }

    private func normalizedArtistInput(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[;；/／,，|]+"#, with: "、", options: .regularExpression)
            .replacingOccurrences(of: #"、+"#, with: "、", options: .regularExpression)
    }
}

private enum HeroEditField: Hashable {
    case title
    case artist
    case album
}

private struct LyricsSidePane: View {
    let track: MusicTrack?

    var body: some View {
        SteppedLyricsPane(track: track)
    }
}

private struct SteppedLyricsPane: View {
    @EnvironmentObject private var player: AudioPlayerService
    let track: MusicTrack?
    @State private var timeline = LyricsTimeline([])
    @State private var loading = true

    var body: some View {
        LyricsViewport(lines: timeline.lines, currentIndex: timeline.index(at: player.boundedCurrentTime),
                       topExclusion: 68, bottomExclusion: TrackListMetrics.bottomContentInset,
                       accent: AppNSColors.accent, normal: AppNSColors.tertiaryText,
                       hover: AppNSColors.primaryText) { player.seek(to: $0) }
            .overlay {
                if timeline.lines.isEmpty && !loading {
                    Text("未找到歌词")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.mutedText)
                        .allowsHitTesting(false)
                }
            }
            .task(id: track.map(LyricsRepository.Source.init)) {
                guard let track else {
                    timeline = LyricsTimeline([])
                    loading = false
                    return
                }
                let repository = LyricsRepository.shared
                timeline = repository.cached(for: .init(track)) ?? LyricsTimeline([])
                loading = timeline.lines.isEmpty
                if let preview = await repository.preview(for: track), !Task.isCancelled {
                    timeline = preview
                    loading = false
                }
                let loaded = await repository.timeline(for: track)
                guard !Task.isCancelled else { return }
                timeline = loaded
                loading = false
            }
    }
}

private struct PlayerDock: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerService
    @Binding var playbackMode: PlaybackMode
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    var previous: () -> Void
    var toggle: () -> Void
    var next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NowPlayingMini(track: player.currentTrack ?? library.selectedTrack)
                .frame(width: 200, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                HStack(spacing: 18) {
                    TransportButton(systemImage: "backward", action: previous, help: "上一首")

                    Button(action: toggle) {
                        Image(systemName: player.isPlaying ? "pause" : "play")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle().inset(by: -10))
                    .help(player.isPlaying ? "暂停" : "播放")

                    TransportButton(systemImage: "forward", action: next, help: "下一首")
                }

                HStack(spacing: 12) {
                    Text(DisplayFormatters.time(displayedTimelineTime))
                        .frame(width: 46, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { displayedTimelineTime },
                            set: { value in
                                scrubTime = boundedTimelineTime(value)
                                isScrubbing = true
                            }
                        ),
                        in: 0...sliderUpperBound,
                        onEditingChanged: { editing in
                            if editing {
                                scrubTime = timelineCurrentTime
                                isScrubbing = true
                            } else {
                                let target = boundedTimelineTime(scrubTime)
                                isScrubbing = false
                                player.seek(to: target)
                            }
                        }
                    )
                    .tint(AppColors.accent)
                    .frame(width: 380)

                    Text(DisplayFormatters.time(timelineDuration))
                        .frame(width: 46, alignment: .leading)
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(AppColors.tertiaryText)
            }
            .frame(width: 500)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ModeCluster(selectedMode: $playbackMode)
                SpeakerOutputButton()
            }
            .frame(width: 174)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: TrackListMetrics.bottomGlassCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: TrackListMetrics.bottomGlassCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            AppColors.accent.opacity(0.06),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: TrackListMetrics.bottomGlassCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.58),
                            AppColors.searchStroke.opacity(0.52),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: TrackListMetrics.bottomGlassCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 8)
                .blur(radius: 8)
                .offset(y: -7)
                .mask(
                    RoundedRectangle(cornerRadius: TrackListMetrics.bottomGlassCornerRadius, style: .continuous)
                )
        }
        .shadow(color: AppColors.shadow.opacity(0.75), radius: 30, y: 16)
        .shadow(color: AppColors.accent.opacity(0.10), radius: 20, y: 4)
    }

    private var timelineDuration: TimeInterval {
        player.boundedDuration
    }

    private var timelineCurrentTime: TimeInterval {
        boundedTimelineTime(player.boundedCurrentTime)
    }

    private var displayedTimelineTime: TimeInterval {
        isScrubbing ? boundedTimelineTime(scrubTime) : timelineCurrentTime
    }

    private var sliderUpperBound: TimeInterval {
        max(timelineDuration, displayedTimelineTime, 1)
    }

    private func boundedTimelineTime(_ value: TimeInterval) -> TimeInterval {
        let safeValue = value.isFinite ? max(0, value) : 0
        guard timelineDuration > 0 else { return safeValue }
        return min(safeValue, timelineDuration)
    }
}

private struct TransportButton: View {
    let systemImage: String
    var action: () -> Void
    let help: String

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 38, height: 38)
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
    }
}

private struct NowPlayingMini: View {
    @EnvironmentObject private var library: MusicLibraryStore
    let track: MusicTrack?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.flatMap { library.artworkURL(for: $0) }, size: 46)

            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(
                    text: track?.displayTitle ?? "未播放",
                    font: .systemFont(ofSize: 14, weight: .semibold),
                    color: AppNSColors.primaryText
                )
                .frame(maxWidth: .infinity)
                .frame(height: 20)

                MarqueeText(
                    text: "\(track?.displayArtist ?? "-") - \(track?.displayAlbum ?? "-")",
                    font: .systemFont(ofSize: 12, weight: .regular),
                    color: AppNSColors.secondaryText
                )
                .frame(maxWidth: .infinity)
                .frame(height: 17)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: mode.systemImage)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 34, height: 34)
            .foregroundStyle(selectedMode == mode ? AppColors.accent : AppColors.mutedText)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selectedMode == mode ? AppColors.accent.opacity(0.09) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().inset(by: -6))
    }
}
