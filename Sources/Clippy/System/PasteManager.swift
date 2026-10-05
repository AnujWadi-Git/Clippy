import AppKit
import ClippyCore
import ApplicationServices
import Carbon.HIToolbox

/// There is no API to insert content into another app. The only route is: put it on the pasteboard
/// and synthesize ⌘V. Posting key events to other apps requires the Accessibility permission; without
/// it we still copy the item and the user presses ⌘V themselves.
@MainActor
final class PasteManager {
    private let repo: ClipboardRepository
    private let monitor: ClipboardMonitor
    private let settings: SettingsManager

    init(repository: ClipboardRepository, monitor: ClipboardMonitor, settings: SettingsManager) {
        self.repo = repository; self.monitor = monitor; self.settings = settings
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    enum Result { case pasted, copiedOnly(reason: String) }

    /// Writes `item` to the pasteboard. `plain` strips formatting (text only).
    func writeToPasteboard(_ item: ClipboardItem, plain: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .url:
            pb.setString(item.text ?? item.preview, forType: .string)
        case .image:
            if let name = item.blobPath, let data = repo.blobs.read(name) {
                pb.setData(data, forType: .png)
                if let img = NSImage(data: data), let tiff = img.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .file:
            let urls = (item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL }
            pb.writeObjects(urls)
        }
        monitor.ignoreCurrentChange()
    }

    /// Copy, then (if permitted) paste into `target`.
    @discardableResult
    func paste(_ item: ClipboardItem, plain: Bool = false, into target: NSRunningApplication?, copyOnly: Bool = false) -> Result {
        writeToPasteboard(item, plain: plain)
        repo.markUsed(id: item.id)
        if copyOnly { return .copiedOnly(reason: "Copied") }
        guard settings.pasteAutomatically else { return .copiedOnly(reason: "Copied — press ⌘V to paste") }
        guard Self.hasAccessibility else { return .copiedOnly(reason: "Copied — grant Accessibility to paste automatically") }
        if IsSecureEventInputEnabled() { return .copiedOnly(reason: "Secure Input is on — press ⌘V to paste") }
        target?.activate()
        // Give the target app a moment to become key before the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Self.postCommandV() }
        return .pasted
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
}
