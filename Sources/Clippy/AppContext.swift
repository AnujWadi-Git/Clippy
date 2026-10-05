import AppKit
import ClippyCore

/// Composition root: owns every long-lived service.
@MainActor
final class AppContext {
    static let shared = AppContext()

    let settings: SettingsManager
    let repository: ClipboardRepository
    let pipeline: CapturePipeline
    let monitor: ClipboardMonitor
    let cleanup: CleanupService
    let paster: PasteManager
    let ai: AIRouter
    let semanticIndex: SemanticIndex
    let memorySearch = MemorySearch()
    let localAI = LocalAIService()
    lazy var searchAssistant = SearchAssistant(ai: localAI)   // on-device only; retrieval never uses the cloud
    let keychain = KeychainStore(service: "com.anujwadi.Clippy.ai")
    lazy var panelModel = PanelViewModel(ctx: self)
    private let indexQueue = DispatchQueue(label: "clippy.index", qos: .utility)
    private var indexWork: DispatchWorkItem?
    let hotkey = GlobalHotkeyManager()
    private(set) var storageError: String?

    private init() {
        let fm = FileManager.default
        // Test hooks: isolated data dir + defaults suite (used by `Clippy --selftest`; never set in normal use).
        let env = ProcessInfo.processInfo.environment
        if let suite = env["CLIPPY_DEFAULTS_SUITE"], let d = UserDefaults(suiteName: suite) { settings = SettingsManager(defaults: d) }
        else { settings = SettingsManager() }
        let base = env["CLIPPY_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clippy", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var baseURL = base; var rv = URLResourceValues(); rv.isExcludedFromBackup = true; try? baseURL.setResourceValues(rv)

        let crypto = CryptoBox.keychainBacked()
        if crypto == nil { NSLog("Clippy: Keychain unavailable; pinned items will not be encrypted at rest.") }

        let repo: ClipboardRepository
        let database: ClipboardDatabase
        do {
            let db = try ClipboardDatabase(path: base.appendingPathComponent("clippy.sqlite").path, crypto: crypto)
            let blobs = try BlobStore(directory: base.appendingPathComponent("Blobs", isDirectory: true), crypto: crypto)
            repo = try ClipboardRepository(database: db, blobs: blobs, settings: settings)
            database = db
        } catch {
            // Fall back to a throwaway in-memory store rather than crash; tell the user.
            storageError = "\(error)"
            let db = try! ClipboardDatabase(path: ":memory:")
            let blobs = try! BlobStore(directory: fm.temporaryDirectory.appendingPathComponent("clippy-\(UUID().uuidString)"))
            repo = try! ClipboardRepository(database: db, blobs: blobs, settings: settings)
            database = db
        }
        repository = repo
        pipeline = CapturePipeline(repository: repo, settings: settings)
        monitor = ClipboardMonitor(pipeline: pipeline, settings: settings)
        cleanup = CleanupService(repository: repo)
        paster = PasteManager(repository: repo, monitor: monitor, settings: settings)

        let embedder = LocalEmbeddingProvider()
        semanticIndex = SemanticIndex(database: database, provider: embedder.isAvailable ? embedder : nil)

        let settings = self.settings
        let keychain = self.keychain
        let cloud = CloudAIService(
            provider: {
                guard let key = keychain.get(settings.cloudProvider), !key.isEmpty else { return nil }
                return AnthropicProvider(apiKey: key, model: settings.cloudModel)
            },
            isPermitted: { settings.aiEnabled && settings.allowCloudProcessing })
        ai = AIRouter(settings: settings, local: LocalAIService(), cloud: cloud)

        settings.onRetentionChange = { [repo] policy in try? repo.applyRetention(policy) }
        repo.onChange = { [weak self] in
            DispatchQueue.main.async { self?.panelModel.recompute(); self?.scheduleIndexing() }
        }
    }

    func start() {
        applyAppearance()
        // Log outcome kinds only, never clipboard content.
        monitor.onOutcome = { outcome in NSLog("Clippy capture: \(outcome)") }
        monitor.start()
        cleanup.start()
        registerHotkey()
        scheduleIndexing()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cleanup.runNow()
        }
    }

    @discardableResult
    func registerHotkey() -> Bool {
        hotkey.register(id: 2, keyCode: SettingsManager.skipHotkey.keyCode, modifiers: SettingsManager.skipHotkey.modifiers)
        return hotkey.register(id: 1, keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    /// ⌥⇧V / menu item: arm or disarm “skip my next copy”.
    func toggleSkipNextCopy() {
        let on = monitor.toggleSkipNextCopy()
        Toaster.shared.show(on ? "Your next copy won’t be recorded" : "Recording resumed")
    }

    /// Low-priority, debounced embedding of new items. Skipped entirely when AI/semantic search is off.
    func scheduleIndexing() {
        indexWork?.cancel()
        guard settings.aiEnabled, settings.semanticSearch, semanticIndex.isAvailable else { return }
        let work = DispatchWorkItem { [repository, semanticIndex] in
            // Loop in small batches so a big backlog never hogs the CPU.
            while semanticIndex.reconcile(items: repository.snapshot(), limit: 40) >= 40 { Thread.sleep(forTimeInterval: 0.05) }
        }
        indexWork = work
        indexQueue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Turning semantic search off removes every stored vector.
    func semanticSearchChanged() {
        if settings.aiEnabled && settings.semanticSearch { scheduleIndexing() }
        else { indexWork?.cancel(); indexQueue.async { [semanticIndex] in semanticIndex.purge() } }
    }

    func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
