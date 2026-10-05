import AppKit
import ClippyCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let ctx: AppContext
    private let openPanel: () -> Void
    private let openSettings: () -> Void
    private let historyMenu = NSMenu(), pinnedMenu = NSMenu()
    private var pauseItem: NSMenuItem!

    init(context: AppContext, openPanel: @escaping () -> Void, openSettings: @escaping () -> Void) {
        ctx = context; self.openPanel = openPanel; self.openSettings = openSettings
        super.init()
        let img = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clippy")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "Clippy"

        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Clippy", action: #selector(openAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let h = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: ""); h.submenu = historyMenu
        let p = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: ""); p.submenu = pinnedMenu
        menu.addItem(h); menu.addItem(p)
        menu.addItem(.separator())
        menu.addItem(target(NSMenuItem(title: "Clear History", action: #selector(clearAction), keyEquivalent: "")))
        pauseItem = target(NSMenuItem(title: "Pause Clipboard Monitoring", action: #selector(pauseAction), keyEquivalent: ""))
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(target(NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")))
        menu.addItem(NSMenuItem(title: "Quit Clippy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        historyMenu.autoenablesItems = false; pinnedMenu.autoenablesItems = false
    }

    private func target(_ i: NSMenuItem) -> NSMenuItem { i.target = self; return i }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let paused = ctx.settings.monitoringPaused
        pauseItem.title = paused ? "Resume Clipboard Monitoring" : "Pause Clipboard Monitoring"
        item.button?.appearsDisabled = paused
        let snap = ctx.repository.snapshot()
        fill(historyMenu, with: Array(snap.filter { !$0.pinned }.prefix(10)), empty: "Nothing copied yet")
        fill(pinnedMenu, with: snap.filter(\.pinned), empty: "No pinned items")
    }

    private func fill(_ menu: NSMenu, with items: [ClipboardItem], empty: String) {
        menu.removeAllItems()
        if items.isEmpty { let e = NSMenuItem(title: empty, action: nil, keyEquivalent: ""); e.isEnabled = false; menu.addItem(e); return }
        for it in items {
            let title = String((it.preview.isEmpty ? "(empty)" : it.preview).prefix(60))
            let mi = NSMenuItem(title: title, action: #selector(copyItem(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = it.id; mi.isEnabled = true
            mi.image = NSImage(systemSymbolName: ClipStyle.symbol(it), accessibilityDescription: nil)
            menu.addItem(mi)
        }
    }

    @objc private func copyItem(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String, let it = ctx.repository.item(id: id) else { return }
        ctx.paster.paste(it, into: nil, copyOnly: true)
        Toaster.shared.show("Copied")
    }
    @objc private func openAction() { openPanel() }
    @objc private func settingsAction() { openSettings() }
    @objc private func pauseAction() { ctx.settings.monitoringPaused.toggle() }
    @objc private func clearAction() {
        let a = NSAlert()
        a.messageText = "Clear clipboard history?"
        a.informativeText = "All unpinned items will be permanently deleted. Pinned items are kept."
        a.addButton(withTitle: "Clear"); a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { try? ctx.repository.clear() }
    }
}
