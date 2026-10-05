import AppKit
import SwiftUI
import ClippyCore

/// Borderless, non-activating panel: the app you were typing in stays frontmost, so a synthesized ⌘V
/// lands there. Key handling is done in `sendEvent` so it works whatever SwiftUI has focused.
final class ClippyPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Don't hijack keys while an input method is composing text.
            let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
            if !composing, keyHandler?(event) == true { return }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { /* esc handled by keyHandler */ }
}

@MainActor
final class ClippyWindowController {
    private let panel: ClippyPanel
    let viewModel: PanelViewModel
    private let paster: PasteManager
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    var onOpenSettings: (() -> Void)?

    var isVisible: Bool { panel.isVisible }

    init(viewModel: PanelViewModel, paster: PasteManager) {
        self.viewModel = viewModel; self.paster = paster
        panel = ClippyPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 470),
                            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(vm: viewModel))
        panel.contentView?.wantsLayer = true
        panel.keyHandler = { [weak self] e in
            guard let self else { return false }
            return MainActor.assumeIsolated {
                self.viewModel.handleKey(keyCode: e.keyCode, chars: e.charactersIgnoringModifiers ?? "", flags: e.modifierFlags.intersection(.deviceIndependentFlagsMask))
            }
        }

        viewModel.onClose = { [weak self] in self?.hide() }
        viewModel.onOpenSettings = { [weak self] in self?.hide(); self?.onOpenSettings?() }
        viewModel.onPaste = { [weak self] item, plain, copyOnly in self?.paste(item, plain: plain, copyOnly: copyOnly) }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        viewModel.reset()
        position()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        NotificationCenter.default.post(name: .clippyPanelDidShow, object: nil)
        // Close when the user clicks elsewhere.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide(restoreFocus: false) }
        }
    }

    func hide(restoreFocus: Bool = false) {
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    private func paste(_ item: ClipboardItem, plain: Bool, copyOnly: Bool) {
        let target = previousApp
        hide()
        let result = paster.paste(item, plain: plain, into: target, copyOnly: copyOnly)
        if case .copiedOnly(let reason) = result, !copyOnly { Toaster.shared.show(reason) }
        if case .copiedOnly = result, copyOnly { target?.activate() }
    }

    /// Centered horizontally, a third from the top of the screen under the mouse.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - f.height * 0.30 - size.height / 2))
    }
}

/// Tiny transient HUD for messages shown when the panel is already closed.
@MainActor
final class Toaster {
    static let shared = Toaster()
    private var window: NSPanel?

    func show(_ text: String) {
        window?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.sizeToFit()
        let pad: CGFloat = 16
        let size = NSSize(width: label.frame.width + pad * 2, height: label.frame.height + 14)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .hudWindow; fx.state = .active; fx.wantsLayer = true; fx.layer?.cornerRadius = size.height / 2; fx.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: pad, y: 7)
        fx.addSubview(label)
        p.contentView = fx; p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar; p.ignoresMouseEvents = true
        let s = NSScreen.main ?? NSScreen.screens[0]
        p.setFrameOrigin(NSPoint(x: s.visibleFrame.midX - size.width / 2, y: s.visibleFrame.minY + 80))
        p.orderFrontRegardless()
        window = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self, weak p] in
            if self?.window === p { p?.orderOut(nil); self?.window = nil }
        }
    }
}
