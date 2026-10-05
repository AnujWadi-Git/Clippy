import AppKit
import ClippyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var ctx: AppContext { .shared }
    private var windowController: ClippyWindowController!
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ctx.start()
        settingsWindow = SettingsWindowController(context: ctx)
        windowController = ClippyWindowController(viewModel: ctx.panelModel, paster: ctx.paster)
        windowController.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menuBar = MenuBarController(context: ctx, openPanel: { [weak self] in self?.windowController.show() },
                                    openSettings: { [weak self] in self?.settingsWindow.show() })
        ctx.hotkey.onTrigger = { [weak self] in self?.windowController.toggle() }

        if !ctx.registerHotkey() { Toaster.shared.show("Clippy: couldn't register the global shortcut — choose another in Settings") }
        if let err = ctx.storageError { NSLog("Clippy storage error: \(err)") }
        if !ctx.settings.hasOnboarded { showWelcome() }
        // Dev aid: `Clippy --show-panel` opens the panel immediately (used for screenshots).
        if CommandLine.arguments.contains("--show-panel") { windowController.show() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showWelcome() {
        let a = NSAlert()
        a.messageText = "Welcome to Clippy"
        a.informativeText = """
        Press \(GlobalHotkeyManager.display(keyCode: ctx.settings.hotkeyKeyCode, modifiers: ctx.settings.hotkeyModifiers)) anywhere to open your clipboard history.

        • Items are kept on this Mac only, and deleted after \(ctx.settings.retention.label) unless you pin them.
        • Passwords, tokens, keys, cards and one-time codes are filtered out before anything is saved.

        To paste straight into the app you're using, Clippy needs Accessibility permission. Without it, Clippy copies the item and you press ⌘V.

        macOS may also ask whether Clippy can paste from other apps — choose Allow so it can see what you copy.
        """
        a.addButton(withTitle: "Grant Accessibility…")
        a.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { PasteManager.requestAccessibility() }
        ctx.settings.hasOnboarded = true
    }
}
