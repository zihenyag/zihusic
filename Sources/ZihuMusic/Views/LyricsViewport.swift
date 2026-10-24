import AppKit
import QuartzCore
import SwiftUI

/// SwiftUI supplies timestamp changes; AppKit handles the short transitions and
/// wheel gestures without rebuilding the SwiftUI lyric tree on every frame.
struct LyricsViewport: NSViewRepresentable {
    let lines: [LyricsTimeline.Entry]
    let currentIndex: Int
    let topExclusion: CGFloat
    let bottomExclusion: CGFloat
    let accent: NSColor
    let normal: NSColor
    let hover: NSColor
    let onSeek: (Double) -> Void

    func makeNSView(context: Context) -> LyricsScrollView { LyricsScrollView() }

    func updateNSView(_ view: LyricsScrollView, context: Context) {
        view.configure(lines: lines, index: currentIndex, top: topExclusion, bottom: bottomExclusion,
                       accent: accent, normal: normal, hover: hover, seek: onSeek)
    }
}

final class LyricsScrollView: NSScrollView {
    private let canvas = LyricsDocumentView()
    private var lines: [LyricsTimeline.Entry] = []
    private var metrics = LyricsLayout(texts: [], width: 1)
    private var rows: [Int: LyricsRenderedRow] = [:]
    private var currentIndex = 0
    private var lastSize = CGSize.zero
    private var topExclusion: CGFloat = 0
    private var bottomExclusion: CGFloat = 0
    private var accent = NSColor.controlAccentColor
    private var normal = NSColor.secondaryLabelColor
    private var hover = NSColor.labelColor
    private var onSeek: ((Double) -> Void)?
    private var followsPlayback = true
    private var returnTimer: Timer?
    private var tracking: NSTrackingArea?
    private var hoveredIndex: Int?
    private var layingOut = false
    private var motionTimer: Timer?
    private var motion: (from: CGFloat, to: CGFloat, start: TimeInterval)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        contentView.drawsBackground = false
        contentView.postsBoundsChangedNotifications = true
        canvas.owner = self
        documentView = canvas
        setAccessibilityLabel("歌词")
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(lines: [LyricsTimeline.Entry], index: Int, top: CGFloat, bottom: CGFloat,
                   accent: NSColor, normal: NSColor, hover: NSColor, seek: @escaping (Double) -> Void) {
        let changed = self.lines != lines
        let moved = currentIndex != index
        let adjacent = abs(currentIndex - index) == 1
        self.topExclusion = top
        self.bottomExclusion = bottom
        self.accent = accent
        self.normal = normal
        self.hover = hover
        onSeek = seek
        currentIndex = index
        if changed {
            stopMotion()
            self.lines = lines
            returnTimer?.invalidate()
            followsPlayback = true
            hoveredIndex = nil
            rows.values.forEach { $0.removeFromSuperview() }
            rows.removeAll()
            lastSize = .zero
        }
        let resized = updateMetrics()
        if followsPlayback, changed || moved || resized { follow(animated: !changed && !resized && adjacent) }
        updateRows()
    }

    override func layout() {
        super.layout()
        if updateMetrics() {
            if followsPlayback { follow(animated: false) }
            updateRows()
        }
    }

    @discardableResult
    private func updateMetrics() -> Bool {
        let size = contentView.bounds.size
        guard !layingOut, size.width > 1, size.height > 1, size != lastSize else { return false }
        layingOut = true
        let oldPosition = metrics.position(atCenter: contentView.bounds.minY)
        lastSize = size
        metrics = LyricsLayout(texts: lines.map(\.text), width: max(size.width - 56, 1))
        canvas.frame = CGRect(x: 0, y: 0, width: size.width, height: metrics.totalHeight + size.height)
        if !followsPlayback { contentView.scroll(to: CGPoint(x: 0, y: metrics.center(at: oldPosition))) }
        layingOut = false
        return true
    }

    private func follow(animated: Bool) {
        stopMotion()
        guard !metrics.centers.isEmpty else { return }
        let destination = CGPoint(x: 0, y: metrics.center(at: Double(currentIndex)))
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reducedMotion {
            motion = (contentView.bounds.minY, destination.y, CACurrentMediaTime())
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                self?.advanceMotion()
            }
            RunLoop.main.add(timer, forMode: .common)
            motionTimer = timer
        } else {
            contentView.scroll(to: destination)
        }
        reflectScrolledClipView(contentView)
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard activeRect.contains(point), !lines.isEmpty else { return }
        stopMotion()
        followsPlayback = false
        super.scrollWheel(with: event)
        returnTimer?.invalidate()
        returnTimer = Timer.scheduledTimer(withTimeInterval: LyricsInteraction.returnDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.followsPlayback = true
            self.follow(animated: true)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeRect.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    private var activeRect: CGRect {
        LyricsInteraction.activeRect(size: bounds.size, top: topExclusion, bottom: bottomExclusion)
    }

    private func index(at point: CGPoint) -> Int? {
        LyricsInteraction.index(at: point, size: contentView.bounds.size, center: contentView.bounds.minY,
                                layout: metrics, top: topExclusion, bottom: bottomExclusion)
    }

    fileprivate func click(_ event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)), lines.indices.contains(index) else { return }
        returnTimer?.invalidate()
        stopMotion()
        followsPlayback = true
        onSeek?(lines[index].time)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { updateHover() }
    override func mouseEntered(with event: NSEvent) { updateHover() }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    private func updateHover() {
        guard let window else { setHover(nil); return }
        setHover(index(at: convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private func setHover(_ index: Int?) {
        guard index != hoveredIndex else { return }
        let old = hoveredIndex
        hoveredIndex = index
        if let old { colorRow(old) }
        if let index { colorRow(index) }
    }

    @objc private func boundsChanged() {
        guard !layingOut else { return }
        updateRows()
        updateHover()
    }

    private func updateRows() {
        guard !layingOut, metrics.heights.count == lines.count, !lines.isEmpty else { return }
        let size = contentView.bounds.size
        let visible = metrics.visibleRange(center: contentView.bounds.minY, viewportHeight: size.height)
        for index in Array(rows.keys) where !visible.contains(index) {
            rows.removeValue(forKey: index)?.removeFromSuperview()
        }
        for index in visible {
            let row = rows[index] ?? LyricsRenderedRow(text: lines[index].text)
            if rows[index] == nil { canvas.addSubview(row); rows[index] = row }
            row.frame = CGRect(x: 28, y: size.height / 2 + metrics.starts[index],
                               width: max(size.width - 56, 1), height: metrics.heights[index])
            colorRow(index)
        }
    }

    private func colorRow(_ index: Int) {
        let near = abs(index - currentIndex) <= 2
        let base = index == currentIndex ? accent : normal.withAlphaComponent(near ? 0.86 : 0.58)
        rows[index]?.textColor = hoveredIndex == index ? base.blended(withFraction: 0.22, of: hover) ?? base : base
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRows()
    }

    private func advanceMotion() {
        guard let motion else { return }
        let progress = min(max((CACurrentMediaTime() - motion.start) / 0.32, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        contentView.scroll(to: CGPoint(x: 0, y: motion.from + (motion.to - motion.from) * eased))
        reflectScrolledClipView(contentView)
        if progress >= 1 { stopMotion() }
    }

    private func stopMotion() {
        motionTimer?.invalidate()
        motionTimer = nil
        motion = nil
    }

    deinit { motionTimer?.invalidate(); returnTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }
}

private final class LyricsDocumentView: NSView {
    weak var owner: LyricsScrollView?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { owner?.click(event) }
}

private final class LyricsRenderedRow: NSView {
    private let text: String
    var textColor = NSColor.labelColor {
        didSet { if textColor != oldValue { needsDisplay = true } }
    }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let height = LyricsLayout.textHeight(text, width: bounds.width)
        LyricsLayout.attributedText(text, color: textColor).draw(
            with: CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
