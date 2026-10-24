import AVKit
import SwiftUI

struct SpeakerOutputButton: View {
    @EnvironmentObject private var player: AudioPlayerService

    var body: some View {
        SpeakerOutputControl(routing: player.airPlay, player: player.routingPlayer)
    }
}

private struct SpeakerOutputControl: View {
    @ObservedObject var routing: AirPlayRouting
    let player: AVPlayer
    @State private var isPresented = false
    @State private var pickerRequest = 0

    var body: some View {
        Button {
            isPresented.toggle()
            if isPresented { routing.checkAutomaticEnrollment() }
        } label: {
            Image(systemName: "airplay.audio")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .help("AirPlay 扬声器")
        .background {
            AirPlayRoutePicker(player: player, routing: routing, presentationRequest: pickerRequest,
                               onFinish: { isPresented = true })
                .allowsHitTesting(false)
                .opacity(0)
        }
        .contextMenu {
            Button("连接全部 AirPlay 设备…") { presentSystemPicker() }
            if routing.hasKnownReceivers {
                Button("扬声器音量") { isPresented = true }
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            SpeakerOutputsPanel(routing: routing, player: player, enroll: presentSystemPicker)
                .presentationCornerRadius(18)
        }
    }

    private func presentSystemPicker() {
        guard routing.supportsGroups else {
            isPresented = true
            return
        }
        isPresented = false
        // Let the custom popover/context menu close before presenting AVKit's.
        DispatchQueue.main.async { pickerRequest += 1 }
    }
}

private struct SpeakerOutputsPanel: View {
    @ObservedObject var routing: AirPlayRouting
    let player: AVPlayer
    let enroll: () -> Void
    @State private var showsCalibration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if routing.supportsGroups {
                ForEach(routing.speakers) { speaker in
                    HStack(spacing: 10) {
                        Image(systemName: speaker.isLocal ? "macmini" : "laptopcomputer")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(speaker.name)
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            if routing.pendingIDs.contains(speaker.id) {
                                ProgressView().controlSize(.mini)
                                    .accessibilityLabel("正在接入\(speaker.name)")
                            }
                        }
                        .frame(width: 12)
                        Slider(value: Binding(
                            get: { speaker.volume },
                            set: { routing.setVolume($0, id: speaker.id) }
                        ), in: 0...1)
                        .controlSize(.small)
                        .tint(.secondary)
                        .frame(width: 60)
                        .disabled(!speaker.isConnected || !speaker.canSetVolume)
                        .accessibilityLabel("\(speaker.name)音量")
                        Toggle(isOn: Binding(
                            get: { speaker.isPlaying },
                            set: { routing.setPlaybackEnabled($0, id: speaker.id) }
                        )) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("播放\(speaker.name)")
                        .disabled(speaker.isConnected && !speaker.canControlPlayback)
                    }
                    .frame(height: 32)
                    .contextMenu {
                        Button("延迟校准…") { showsCalibration.toggle() }
                            .disabled(!routing.hasRemoteOutputs)
                        if !speaker.isLocal {
                            Button("重新同步") { routing.resynchronize() }
                                .disabled(!speaker.isConnected || !routing.pendingIDs.isEmpty)
                        }
                    }
                }
            }
            if showsCalibration {
                Divider().padding(.vertical, 5)
                HStack(spacing: 8) {
                    Text("本机延迟").font(.system(size: 11))
                    Slider(value: Binding(get: { routing.localDelay }, set: { routing.setLocalDelay($0) }),
                           in: -3...3, step: 0.005)
                        .controlSize(.small)
                        .accessibilityLabel("本机相对 AirPlay 的延迟")
                    Stepper(value: Binding(get: { routing.localDelay }, set: { routing.setLocalDelay($0) }),
                            in: -3...3, step: 0.005) {
                        Text(String(format: "%+.0f ms", routing.localDelay * 1_000))
                            .font(.system(size: 10).monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                    }
                    .controlSize(.mini)
                }
                .contextMenu { Button("恢复 0 ms") { routing.setLocalDelay(0) } }
                Text("正值让本机晚播").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.bottom, 3)
            }
            if !routing.supportsGroups {
                AirPlayRoutePicker(player: player, routing: routing)
                    .frame(width: 24, height: 24)
            }
            if routing.enrollmentNeedsPermission {
                Button("启用自动连接…", action: enroll)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .padding(.vertical, 4)
            }
            if let error = routing.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { routing.startMonitoring() }
    }
}

struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer
    let routing: AirPlayRouting
    var presentationRequest = 0
    var onFinish: (() -> Void)?

    func makeNSView(context: Context) -> AudioGroupRoutePicker {
        let view = AudioGroupRoutePicker()
        view.configure(player: player, routing: routing)
        view.onFinish = onFinish
        return view
    }

    func updateNSView(_ view: AudioGroupRoutePicker, context: Context) {
        view.configure(player: player, routing: routing)
        view.onFinish = onFinish
        view.presentIfRequested(presentationRequest)
    }
}

final class AudioGroupRoutePicker: NSView, AVRoutePickerViewDelegate {
    private let picker = AVRoutePickerView()
    private let button = NSButton()
    private weak var routing: AirPlayRouting?
    private var lastPresentationRequest = 0
    private var enrollment: NativeAirPlayEnrollment?
    private var shouldReopenPanel = false
    var onFinish: (() -> Void)?
    private let presentationSelector = NSSelectorFromString("showRoutePickingControlsForOutputContext:relativeToRect:ofView:")

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.image = NSImage(systemSymbolName: "airplay.audio", accessibilityDescription: "选择 AirPlay 设备")
        button.imageScaling = .scaleProportionallyUpOrDown
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.target = self
        button.action = #selector(showAudioGroup)
        button.setAccessibilityLabel("选择 AirPlay 设备")
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.controlAccentColor, for: .normal)
        picker.delegate = self
        addSubview(button)
        addSubview(picker)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(player: AVPlayer, routing: AirPlayRouting) {
        self.routing = routing
        if enrollment == nil, routing.supportsGroups {
            enrollment = NativeAirPlayEnrollment(picker: picker, anchor: self, routing: routing)
            routing.onCheckEnrollment = { [weak enrollment] in enrollment?.checkNow() }
        }
        if window != nil { enrollment?.start() }
        let hasGroups = routing.supportsGroups && picker.responds(to: presentationSelector)
        button.isHidden = !hasGroups
        picker.isHidden = hasGroups
        let destinationPlayer = hasGroups ? nil : player
        if picker.player !== destinationPlayer { picker.player = destinationPlayer }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { enrollment?.start() }
    }

    override func layout() {
        super.layout()
        button.frame = bounds.insetBy(dx: 4, dy: 4)
        picker.frame = bounds
    }

    func presentIfRequested(_ request: Int) {
        guard request != lastPresentationRequest else { return }
        lastPresentationRequest = request
        DispatchQueue.main.async { [weak self] in self?.showAudioGroup() }
    }

    @objc private func showAudioGroup() {
        shouldReopenPanel = true
        enrollment?.requestAll(askPermission: true)
    }

    nonisolated func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.routing?.finishAddingDevice()
            if self?.shouldReopenPanel == true {
                self?.shouldReopenPanel = false
                self?.onFinish?()
            }
        }
    }
}
