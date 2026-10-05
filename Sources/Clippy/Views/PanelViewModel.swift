import AppKit
import SwiftUI
import Observation
import ClippyCore

enum PanelAction: String, Identifiable, CaseIterable {
    case paste = "Paste", pastePlain = "Paste as Plain Text", copy = "Copy", pin = "Pin", unpin = "Unpin"
    case openLink = "Open Link", copyDomain = "Copy Domain", reveal = "Reveal in Finder", delete = "Delete"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .paste: return "return"
        case .pastePlain: return "textformat"
        case .copy: return "doc.on.doc"
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .openLink: return "safari"
        case .copyDomain: return "globe"
        case .reveal: return "folder"
        case .delete: return "trash"
        }
    }
}

enum PanelRow: Identifiable {
    case header(String)
    case item(ClipboardItem, Int)    // index into results
    var id: String {
        switch self { case .header(let t): return "h:" + t; case .item(let i, _): return i.id }
    }
}

@MainActor @Observable
final class PanelViewModel {
    let repo: ClipboardRepository
    let settings: SettingsManager
    private let engine = SearchEngine()

    var query = "" { didSet { if query != oldValue { selection = 0; recompute() } } }
    var filter: ClipFilter = .all { didSet { if filter != oldValue { selection = 0; recompute() } } }
    private(set) var results: [ClipboardItem] = []
    private(set) var rows: [PanelRow] = []
    var selection = 0
    var actionsOpen = false
    var actionSelection = 0
    var toast: String?

    var onPaste: ((ClipboardItem, _ plain: Bool, _ copyOnly: Bool) -> Void)?
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(repo: ClipboardRepository, settings: SettingsManager) {
        self.repo = repo; self.settings = settings
        recompute()
    }

    var selectedItem: ClipboardItem? { results.indices.contains(selection) ? results[selection] : nil }

    func reset() { query = ""; filter = .all; selection = 0; actionsOpen = false; toast = nil; recompute() }

    func recompute() {
        let snap = repo.snapshot()
        results = engine.search(snap, query: query, filter: filter)
        if selection >= results.count { selection = max(0, results.count - 1) }
        var out: [PanelRow] = []
        let grouped = query.isEmpty && filter == .all
        var lastHeader = ""
        for (i, item) in results.enumerated() {
            if grouped {
                let h = item.pinned ? "Pinned" : "Recent"
                if h != lastHeader { out.append(.header(h)); lastHeader = h }
            }
            out.append(.item(item, i))
        }
        rows = out
    }

    // MARK: Actions

    func availableActions(for item: ClipboardItem) -> [PanelAction] {
        var a: [PanelAction] = [.paste]
        if item.kind == .text || item.kind == .url { a.append(.pastePlain) }
        a.append(.copy)
        if item.category == .link { a += [.openLink, .copyDomain] }
        if item.kind == .file || item.category == .path { a.append(.reveal) }
        a.append(item.pinned ? .unpin : .pin)
        a.append(.delete)
        return a
    }

    func perform(_ action: PanelAction, on item: ClipboardItem) {
        actionsOpen = false
        switch action {
        case .paste: onPaste?(item, false, false)
        case .pastePlain: onPaste?(item, true, false)
        case .copy: onPaste?(item, false, true)
        case .pin, .unpin: try? repo.setPinned(id: item.id, action == .pin); recompute()
        case .delete: try? repo.delete(id: item.id); recompute()
        case .openLink:
            if let s = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), let u = URL(string: s) { NSWorkspace.shared.open(u); onClose?() }
        case .copyDomain:
            if let s = item.text, let host = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines))?.host {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(host, forType: .string)
                flash("Copied \(host)")
            }
        case .reveal:
            let urls = (item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            NSWorkspace.shared.activateFileViewerSelecting(urls); onClose?()
        }
    }

    func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: Keyboard (routed from the panel's sendEvent so it works regardless of SwiftUI focus)

    /// Returns true if the event was consumed.
    func handleKey(keyCode: UInt16, chars: String, flags: NSEvent.ModifierFlags) -> Bool {
        let cmd = flags.contains(.command), opt = flags.contains(.option)
        if actionsOpen { return handleActionsKey(keyCode: keyCode, chars: chars, cmd: cmd) }
        switch keyCode {
        case 126: move(-1); return true                          // ↑
        case 125: move(1); return true                           // ↓
        case 36, 76:                                              // return
            guard let item = selectedItem else { return true }
            onPaste?(item, opt, cmd); return true               // ⌥↩ plain, ⌘↩ copy only
        case 53:                                                  // esc
            if !query.isEmpty { query = "" } else { onClose?() }
            return true
        case 48:                                                  // tab / shift-tab cycles filters
            cycleFilter(flags.contains(.shift) ? -1 : 1); return true
        case 123 where query.isEmpty, 124 where query.isEmpty:
            cycleFilter(keyCode == 124 ? 1 : -1); return true
        default: break
        }
        if cmd {
            switch chars.lowercased() {
            case "k": if selectedItem != nil { actionsOpen = true; actionSelection = 0 }; return true
            case "p": if let i = selectedItem { perform(i.pinned ? .unpin : .pin, on: i) }; return true
            case "," : onOpenSettings?(); return true
            default: break
            }
            if keyCode == 51, let i = selectedItem { perform(.delete, on: i); return true }   // ⌘⌫
            if let n = Int(chars), (1...9).contains(n), results.indices.contains(n - 1) {     // ⌘1…9
                onPaste?(results[n - 1], false, false); return true
            }
        }
        return false
    }

    private func handleActionsKey(keyCode: UInt16, chars: String, cmd: Bool) -> Bool {
        guard let item = selectedItem else { actionsOpen = false; return true }
        let actions = availableActions(for: item)
        switch keyCode {
        case 126: actionSelection = (actionSelection - 1 + actions.count) % actions.count
        case 125: actionSelection = (actionSelection + 1) % actions.count
        case 36, 76: perform(actions[min(actionSelection, actions.count - 1)], on: item)
        case 53: actionsOpen = false
        default: if cmd && chars.lowercased() == "k" { actionsOpen = false }
        }
        return true
    }

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + d, 0), results.count - 1)
    }

    private func cycleFilter(_ d: Int) {
        let all = ClipFilter.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + d + all.count) % all.count]
    }
}
