import AppKit
import ClippyCore

/// Composition root: owns every long-lived service.
@MainActor
final class AppContext {
    static let shared = AppContext()

    let settings = SettingsManager()
    let repository: ClipboardRepository
    let pipeline: CapturePipeline
    let monitor: ClipboardMonitor
    let cleanup: CleanupService
    let paster: PasteManager
    let panelModel: PanelViewModel
    let hotkey = GlobalHotkeyManager()
    private(set) var storageError: String?

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clippy", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var baseURL = base; var rv = URLResourceValues(); rv.isExcludedFromBackup = true; try? baseURL.setResourceValues(rv)

        let crypto = CryptoBox.keychainBacked()
        if crypto == nil { NSLog("Clippy: Keychain unavailable; pinned items will not be encrypted at rest.") }

        let repo: ClipboardRepository
        do {
            let db = try ClipboardDatabase(path: base.appendingPathComponent("clippy.sqlite").path, crypto: crypto)
            let blobs = try BlobStore(directory: base.appendingPathComponent("Blobs", isDirectory: true))
            repo = try ClipboardRepository(database: db, blobs: blobs, settings: settings)
        } catch {
            // Fall back to a throwaway in-memory store rather than crash; tell the user.
            storageError = "\(error)"
            let db = try! ClipboardDatabase(path: ":memory:")
            let blobs = try! BlobStore(directory: fm.temporaryDirectory.appendingPathComponent("clippy-\(UUID().uuidString)"))
            repo = try! ClipboardRepository(database: db, blobs: blobs, settings: settings)
        }
        repository = repo
        pipeline = CapturePipeline(repository: repo, settings: settings)
        monitor = ClipboardMonitor(pipeline: pipeline, settings: settings)
        cleanup = CleanupService(repository: repo)
        paster = PasteManager(repository: repo, monitor: monitor, settings: settings)
        panelModel = PanelViewModel(repo: repo, settings: settings)

        settings.onRetentionChange = { [repo] policy in try? repo.applyRetention(policy) }
        repo.onChange = { [weak self] in DispatchQueue.main.async { self?.panelModel.recompute() } }
    }

    func start() {
        applyAppearance()
        // Log outcome kinds only, never clipboard content.
        monitor.onOutcome = { outcome in NSLog("Clippy capture: \(outcome)") }
        monitor.start()
        cleanup.start()
        registerHotkey()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cleanup.runNow()
        }
    }

    @discardableResult
    func registerHotkey() -> Bool {
        hotkey.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
