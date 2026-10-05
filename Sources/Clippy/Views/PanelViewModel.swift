import AppKit
import SwiftUI
import Observation
import ClippyCore

enum PanelRow: Identifiable {
    case header(String)
    case item(ClipboardItem, index: Int, similar: Int, nested: Bool)
    case command(ItemAction, index: Int)
    var id: String {
        switch self {
        case .header(let t): return "h:" + t
        case .item(let i, _, _, _): return i.id
        case .command(let a, _): return "c:" + a.title
        }
    }
}

@MainActor @Observable
final class PanelViewModel {
    private let ctx: AppContext
    var repo: ClipboardRepository { ctx.repository }
    var settings: SettingsManager { ctx.settings }
    private let engine = SearchEngine()

    var query = "" { didSet { if query != oldValue { selection = 0; recompute() } } }
    var filter: ClipFilter = .all { didSet { if filter != oldValue { selection = 0; recompute() } } }

    private(set) var results: [ClipboardItem] = []       // flat, visible, selectable (browse / search / smart)
    private(set) var commandResults: [ItemAction] = []   // command mode
    private(set) var rows: [PanelRow] = []
    private(set) var smartActive = false
    private(set) var smartReasons: [String: String] = [:]
    private(set) var smartNoMatch = false
    private(set) var commandTarget: ClipboardItem?
    private(set) var pinSuggestion: ClipboardItem?
    private(set) var busy: String?
    private(set) var refining = false
    private var groupSize: [String: Int] = [:]
    private var expanded = Set<String>()
    private var smartTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?

    var selection = 0
    var actionsOpen = false
    var actionSelection = 0
    var toast: String?

    var onPaste: ((ClipboardItem, _ plain: Bool, _ copyOnly: Bool) -> Void)?
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(ctx: AppContext) { self.ctx = ctx }

    var isCommandMode: Bool { CommandMode.isCommandQuery(query) }
    var aiAvailable: Bool { ctx.ai.isAvailable }
    var aiUnavailableReason: String? { ctx.ai.unavailableReason() }
    var selectableCount: Int { isCommandMode ? commandResults.count : results.count }
    var selectedItem: ClipboardItem? { isCommandMode ? commandTarget : (results.indices.contains(selection) ? results[selection] : nil) }
    var selectedReason: String? { selectedItem.flatMap { smartReasons[$0.id] } }
    var hasSimilar: Bool { selectedItem.map { (groupSize[$0.id] ?? 0) > 0 } ?? false }

    func reset() {
        smartTask?.cancel(); aiTask?.cancel(); busy = nil; refining = false
        query = ""; filter = .all; selection = 0; actionsOpen = false; toast = nil; expanded = []
        recompute()
    }

    // MARK: Results

    func recompute() {
        smartTask?.cancel()
        let snap = repo.snapshot()
        smartActive = false; smartNoMatch = false; smartReasons = [:]

        if isCommandMode { buildCommandMode(snap); return }
        commandResults = []; commandTarget = nil

        let raw = query.trimmingCharacters(in: .whitespaces)
        let forced = raw.hasPrefix("?")
        let text = forced ? String(raw.dropFirst()).trimmingCharacters(in: .whitespaces) : raw

        if forced { results = [] } else { results = engine.search(snap, query: text, filter: filter) }
        pinSuggestion = (text.isEmpty && filter == .all && settings.pinSuggestions)
            ? PinSuggester.suggestion(from: snap, dismissedHashes: Set(settings.dismissedPinSuggestions)) : nil

        let wantsSmart = !text.isEmpty && settings.aiEnabled && settings.semanticSearch &&
            (forced || text.split(separator: " ").count >= 3 || results.isEmpty)
        if wantsSmart { scheduleSmart(text: text, snapshot: snap) }

        if selection >= results.count { selection = max(0, results.count - 1) }
        buildRows(grouped: text.isEmpty)
    }

    private func scheduleSmart(text: String, snapshot: [ClipboardItem]) {
        let filter = self.filter
        let search = ctx.memorySearch, index = ctx.semanticIndex
        let q = query
        smartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            if Task.isCancelled { return }
            let result = await Task.detached(priority: .userInitiated) {
                search.search(text, items: snapshot, index: index.isAvailable ? index : nil)
            }.value
            guard let self, !Task.isCancelled, self.query == q else { return }
            let hits = result.hits.filter { filter.accepts($0.item) }
            self.smartActive = true
            self.smartNoMatch = hits.isEmpty
            if hits.isEmpty && !(self.settings.aiEnabled && self.ctx.localAI.unavailableReason() == nil && text.split(separator: " ").count >= 2) { return }
            if !hits.isEmpty {   // otherwise keep the plain keyword results already on screen
                self.smartReasons = Dictionary(uniqueKeysWithValues: hits.map { ($0.item.id, $0.why) })
                self.results = hits.map(\.item)
                self.selection = 0
                self.buildRows(grouped: false)
            }
            // On-device refinement: the model expands the query and picks among real candidates. It runs after the
            // instant results are on screen and is skipped if the user has already started acting on them.
            let words = text.split(separator: " ").count
            if self.settings.aiEnabled, words >= 2, self.ctx.localAI.unavailableReason() == nil {
                self.refining = true
                let assisted = await search.assisted(text, items: snapshot, index: index.isAvailable ? index : nil,
                                                     assistant: self.ctx.searchAssistant, mode: .balanced)
                self.refining = false
                guard !Task.isCancelled, self.query == q, self.selection == 0 else { self.smartNoMatch = self.results.isEmpty; return }
                let refined = assisted.hits.filter { filter.accepts($0.item) }
                self.smartNoMatch = refined.isEmpty
                self.smartReasons = Dictionary(uniqueKeysWithValues: refined.map { ($0.item.id, $0.why) })
                self.results = refined.map(\.item)
                self.buildRows(grouped: false)
            }
        }
    }

    private func buildRows(grouped: Bool) {
        var out: [PanelRow] = []
        groupSize = [:]
        if grouped && filter != .pinned {
            var flat: [ClipboardItem] = []
            var lastHeader = ""
            var visible: [(ClipboardItem, Int, Bool)] = []
            for g in SimilarGrouper.group(results) {
                groupSize[g.lead.id] = g.others.count
                visible.append((g.lead, g.others.count, false))
                if expanded.contains(g.lead.id) { for o in g.others { visible.append((o, 0, true)) } }
            }
            flat = visible.map(\.0)
            let showHeaders = filter == .all
            for (i, v) in visible.enumerated() {
                if showHeaders {
                    let h = v.0.pinned ? "Pinned" : "Recent"
                    if h != lastHeader { out.append(.header(h)); lastHeader = h }
                }
                out.append(.item(v.0, index: i, similar: v.1, nested: v.2))
            }
            results = flat
        } else {
            for (i, item) in results.enumerated() { out.append(.item(item, index: i, similar: 0, nested: false)) }
        }
        if selection >= results.count { selection = max(0, results.count - 1) }
        rows = out
    }

    private func buildCommandMode(_ snap: [ClipboardItem]) {
        if commandTarget == nil || !snap.contains(where: { $0.id == commandTarget?.id }) {
            commandTarget = results.indices.contains(selection) ? results[selection] : (snap.first { !$0.isHeldSensitive })
        }
        results = []; pinSuggestion = nil
        guard let target = commandTarget else { commandResults = []; rows = []; return }
        let all = CommandMode.commands(for: target, aiAvailable: aiAvailable)
        commandResults = CommandMode.match(CommandMode.commandText(query), in: all)
        if selection >= commandResults.count { selection = max(0, commandResults.count - 1) }
        rows = commandResults.enumerated().map { .command($0.element, index: $0.offset) }
    }

    // MARK: Pin suggestions

    func acceptPinSuggestion() {
        guard let s = pinSuggestion else { return }
        try? repo.setPinned(id: s.id, true)
        flash("Pinned"); recompute()
    }
    func dismissPinSuggestion() {
        guard let s = pinSuggestion else { return }
        settings.dismissedPinSuggestions = Array((settings.dismissedPinSuggestions + [s.contentHash]).suffix(300))
        recompute()
    }

    // MARK: Actions

    func availableActions(for item: ClipboardItem) -> [ItemAction] {
        ActionCatalog.actions(for: item, aiAvailable: aiAvailable)
    }

    func perform(_ action: ItemAction, on item: ClipboardItem) {
        actionsOpen = false
        let text = item.text ?? ""
        switch action {
        case .paste: onPaste?(item, false, false)
        case .pastePlain: onPaste?(item, true, false)
        case .copy: onPaste?(item, false, true)
        case .pin, .unpin: try? repo.setPinned(id: item.id, action == .pin); recompute()
        case .delete: try? repo.delete(id: item.id); recompute()
        case .openLink:
            if let u = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) { NSWorkspace.shared.open(u); onClose?() }
        case .composeEmail:
            if let u = Transforms.mailto(text) { NSWorkspace.shared.open(u); onClose?() }
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }); onClose?()
        case .runInTerminal: confirmAndRun(text)
        case .copyDomain:
            if let d = Transforms.domain(text) { makeResult(d, label: "Domain") } else { flash("No domain found") }
        case .cleanLink:
            if let c = Transforms.stripTracking(text) { makeResult(c, label: "Clean link") } else { flash("No tracking parameters found") }
        case .prettyJSON:
            if let r = Transforms.prettyJSON(text) { makeResult(r, label: "Pretty JSON") } else { flash("Not valid JSON") }
        case .minifyJSON:
            if let r = Transforms.minifyJSON(text) { makeResult(r, label: "Minified JSON") } else { flash("Not valid JSON") }
        case .validateJSON:
            let v = Transforms.validateJSON(text); flash(v.valid ? "✓ Valid JSON" : "✗ \(v.message)")
        case .ai(let task): runAI(task, on: item)
        }
    }

    private func runAI(_ task: AITask, on item: ClipboardItem) {
        guard let text = item.text else { return }
        busy = task.title + "…"
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let r = try await self.ctx.ai.run(task, input: text)
                if Task.isCancelled { return }
                self.busy = nil
                self.makeResult(r.text, label: task.title, viaCloud: r.provider == .cloud)
            } catch {
                if Task.isCancelled { return }
                self.busy = nil
                self.flash(error.localizedDescription)
            }
        }
    }

    /// A transform/AI result becomes a normal (temporary, 24 h) clipboard item and is copied, ready to paste.
    private func makeResult(_ text: String, label: String, viaCloud: Bool = false) {
        let outcome = ctx.pipeline.process(CapturedClip(payload: .text(text), pasteboardTypes: [],
                                                         sourceBundle: nil, sourceName: "Clippy · \(label)"))
        var id: String?
        switch outcome { case .stored(let i), .duplicate(let i): id = i; default: break }
        guard let id, let item = repo.item(id: id) else { flash("Result wasn't saved (it looks sensitive)"); return }
        ctx.paster.writeToPasteboard(item)
        if isCommandMode { query = "" } else { recompute() }
        recompute()
        if let idx = results.firstIndex(where: { $0.id == id }) { selection = idx }
        flash(viaCloud ? "Result copied · processed in the cloud" : "Result copied · ↩ to paste")
    }

    private func confirmAndRun(_ command: String) {
        onClose?()
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = "Run this command in Terminal?"
            a.informativeText = String(command.prefix(600))
            a.alertStyle = .warning
            a.addButton(withTitle: "Run"); a.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-\(UUID().uuidString).command")
            do {
                try Transforms.terminalScript(for: command).write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                NSWorkspace.shared.open(url)
            } catch { NSLog("Clippy: couldn't prepare command script: \(error.localizedDescription)") }
        }
    }

    func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: Keyboard (routed from the panel's sendEvent so it works regardless of SwiftUI focus)

    func handleKey(keyCode: UInt16, chars: String, flags: NSEvent.ModifierFlags) -> Bool {
        let cmd = flags.contains(.command), opt = flags.contains(.option)
        if actionsOpen { return handleActionsKey(keyCode: keyCode, chars: chars, cmd: cmd) }
        switch keyCode {
        case 126: move(-1); return true
        case 125: move(1); return true
        case 36, 76:
            if isCommandMode {
                if commandResults.indices.contains(selection), let t = commandTarget { perform(commandResults[selection], on: t) }
                return true
            }
            guard let item = selectedItem else { return true }
            onPaste?(item, opt, cmd); return true
        case 53:
            if !query.isEmpty { query = "" } else { onClose?() }
            return true
        case 48: cycleFilter(flags.contains(.shift) ? -1 : 1); return true
        case 124 where query.isEmpty:                       // → expand similar items
            if let i = selectedItem, (groupSize[i.id] ?? 0) > 0 { expanded.insert(i.id); recompute() }
            return true
        case 123 where query.isEmpty:                       // ← collapse
            if let i = selectedItem {
                if expanded.contains(i.id) { expanded.remove(i.id); recompute() }
                else if let lead = leadOf(i) { expanded.remove(lead); recompute() }
            }
            return true
        default: break
        }
        if cmd {
            switch chars.lowercased() {
            case "k": if selectedItem != nil { actionsOpen = true; actionSelection = 0 }; return true
            case "p":
                if cmd && flags.contains(.shift), pinSuggestion != nil { acceptPinSuggestion(); return true }
                if let i = selectedItem { perform(i.pinned ? .unpin : .pin, on: i) }; return true
            case ",": onOpenSettings?(); return true
            default: break
            }
            if keyCode == 51, let i = selectedItem { perform(.delete, on: i); return true }
            if !isCommandMode, let n = Int(chars), (1...9).contains(n), results.indices.contains(n - 1) {
                onPaste?(results[n - 1], false, false); return true
            }
        }
        return false
    }

    private func leadOf(_ item: ClipboardItem) -> String? {
        for (lead, _) in groupSize where expanded.contains(lead) {
            // nested members follow their lead in `results`
            if let li = results.firstIndex(where: { $0.id == lead }), let ii = results.firstIndex(where: { $0.id == item.id }), ii > li { return lead }
        }
        return nil
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
        guard selectableCount > 0 else { return }
        selection = min(max(selection + d, 0), selectableCount - 1)
    }

    private func cycleFilter(_ d: Int) {
        guard !isCommandMode else { return }
        let all = ClipFilter.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + d + all.count) % all.count]
    }
}
