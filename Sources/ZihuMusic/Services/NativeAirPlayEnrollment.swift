import AppKit
import ApplicationServices
import AVKit
import ObjectiveC

private struct EnrollmentHandle: @unchecked Sendable { let element: AXUIElement }

/// Automates only this app's hosted Apple AirPlay popover. It never searches
/// other apps/windows or changes a checked route. macOS requires Accessibility
/// consent because Apple renders that popover in a separate service process.
@MainActor
final class NativeAirPlayEnrollment: NSObject, NetServiceBrowserDelegate {
    private weak var picker: AVRoutePickerView?
    private weak var anchor: NSView?
    private weak var routing: AirPlayRouting?
    private let browser = NetServiceBrowser()
    private let queue = DispatchQueue(label: "com.local.zihusic.airplay.enroll", qos: .userInitiated)
    private var services: Set<String> = []
    private var pending = true
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var wasTrusted = false
    private var started = false
    private var popover: NSPopover?
    private var beforeWindows: Set<ObjectIdentifier> = []
    var onWillPresent: (() -> Void)?

    init(picker: AVRoutePickerView, anchor: NSView, routing: AirPlayRouting) {
        self.picker = picker; self.anchor = anchor; self.routing = routing
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        browser.searchForServices(ofType: "_raop._tcp.", inDomain: "local.")
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.async { [weak self] in self?.requestAll(askPermission: true) }
    }

    func requestAll(askPermission: Bool = false) {
        pending = true
        if askPermission, !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        check()
    }

    func checkNow() { check() }

    private func check() {
        let trusted = AXIsProcessTrusted()
        routing?.setEnrollmentNeedsPermission(!trusted)
        if trusted && !wasTrusted { pending = true }
        wasTrusted = trusted
        guard trusted, pending, task == nil, NSApp.isActive,
              anchor?.window?.isVisible == true else { return }
        pending = false
        task = Task { @MainActor [weak self] in await self?.enroll() }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let name = service.name
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.services.insert(name).inserted { self.pending = true }
            // The periodic check allows Bonjour's burst of callbacks to settle.
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        Task { @MainActor [weak self] in self?.services.remove(name) }
    }

    private func enroll() async {
        guard let picker, let anchor, let context = routing?.context else { task = nil; return }
        onWillPresent?()
        routing?.setEnrolling(true)
        beforeWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let selector = NSSelectorFromString("showRoutePickingControlsForOutputContext:relativeToRect:ofView:")
        guard let method = class_getInstanceMethod(AVRoutePickerView.self, selector) else { finish(); return }
        typealias Present = @convention(c)(NSObject, Selector, NSObject, CGRect, NSView) -> Void
        unsafeBitCast(method_getImplementation(method), to: Present.self)(picker, selector, context, anchor.bounds, anchor)
        var pressed: Set<String> = []
        var lastChange = Date()
        let deadline = Date(timeIntervalSinceNow: 12)
        var sawTable = false
        while !Task.isCancelled, Date() < deadline, NSApp.isActive {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { break }
            if popover == nil { popover = nativePopover(picker) }
            guard let root = popoverRoot() else { continue }
            let localName = routing?.speakers.first { $0.isLocal }?.name ?? ""
            let snapshot = await inspect(root, localName: localName, pressed: pressed)
            sawTable = sawTable || snapshot.sawTable
            if let name = snapshot.pressed {
                pressed.insert(name)
                lastChange = Date()
                routing?.refresh()
            }
            if sawTable, Date().timeIntervalSince(lastChange) > 2.5 { break }
        }
        if !sawTable { routing?.reportEnrollmentError("自动接入未完成，请确认辅助功能权限后重试。") }
        finish()
    }

    private func finish() {
        popover?.performClose(nil)
        popover = nil
        routing?.setEnrolling(false)
        routing?.finishAddingDevice()
        task = nil
    }

    private func nativePopover(_ picker: AVRoutePickerView) -> NSPopover? {
        guard class_getInstanceVariable(type(of: picker), "_routePickerViewRemoteViewService") != nil,
              let service = picker.value(forKey: "routePickerViewRemoteViewService") as? NSObject,
              service.responds(to: NSSelectorFromString("popover")) else { return nil }
        return service.value(forKey: "popover") as? NSPopover
    }

    private func popoverRoot() -> EnrollmentHandle? {
        let window = popover?.contentViewController?.view.window ?? NSApp.windows.first {
            !beforeWindows.contains(ObjectIdentifier($0)) && $0.className.contains("Popover")
        }
        guard let window else { return nil }
        let children = window.accessibilityChildren() as? [NSObject] ?? []
        for child in children {
            let selector = NSSelectorFromString("AXUIElement")
            guard let method = class_getInstanceMethod(type(of: child), selector) else { continue }
            typealias Getter = @convention(c)(NSObject, Selector) -> Unmanaged<AXUIElement>?
            if let root = unsafeBitCast(method_getImplementation(method), to: Getter.self)(child, selector)?.takeUnretainedValue() {
                return EnrollmentHandle(element: root)
            }
        }
        return nil
    }

    private struct Inspection: Sendable { var sawTable = false; var pressed: String? }

    /// Remote accessibility IPC has a timeout and runs off the UI actor.
    private func inspect(_ root: EnrollmentHandle, localName: String, pressed: Set<String>) async -> Inspection {
        await withCheckedContinuation { continuation in
            queue.async {
                AXUIElementSetMessagingTimeout(root.element, 0.3)
                var result = Inspection()
                let nodes = Self.descendants(root.element)
                result.sawTable = nodes.contains { Self.string($0, kAXRoleAttribute) == kAXTableRole }
                let rows = nodes.filter { Self.string($0, kAXRoleAttribute) == kAXRowRole }
                // Apple's audio picker puts this Mac first. Its checkmark is
                // exclusive with the receiver group, so never press that row.
                for row in rows.dropFirst() {
                    let children = Self.descendants(row)
                    let labels = children.filter { Self.string($0, kAXRoleAttribute) == kAXStaticTextRole }
                        .compactMap { Self.string($0, kAXValueAttribute) ?? Self.string($0, kAXTitleAttribute) }
                    let name = labels.joined(separator: " ")
                    guard !name.isEmpty, name != localName, !pressed.contains(name) else { continue }
                    guard let checkbox = children.first(where: { Self.string($0, kAXRoleAttribute) == kAXCheckBoxRole }),
                          (Self.attribute(checkbox, kAXEnabledAttribute) as? NSNumber)?.boolValue != false,
                          (Self.attribute(checkbox, kAXValueAttribute) as? NSNumber)?.intValue == 0 else { continue }
                    if AXUIElementPerformAction(checkbox, kAXPressAction as CFString) == .success {
                        result.pressed = name
                        break // Re-read the table before acting on another row.
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ key: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    private nonisolated static func string(_ element: AXUIElement, _ key: String) -> String? { attribute(element, key) as? String }
    private nonisolated static func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var pending = [root]
        let deadline = Date(timeIntervalSinceNow: 1)
        while let node = pending.popLast(), result.count < 200, Date() < deadline {
            AXUIElementSetMessagingTimeout(node, 0.15)
            result.append(node)
            if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { pending.append(contentsOf: children.reversed()) }
        }
        return result
    }

    deinit { timer?.invalidate(); task?.cancel(); browser.stop() }
}
