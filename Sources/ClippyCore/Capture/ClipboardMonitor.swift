import AppKit

/// NSPasteboard has no change notification, so we poll `changeCount` (an Int read; effectively free)
/// and only read contents when it changes. Reading happens on the main thread (AppKit requirement),
/// processing (hash / detect / persist) on a utility queue.
public final class ClipboardMonitor: @unchecked Sendable {
    private let pasteboard = NSPasteboard.general
    private let pipeline: CapturePipeline
    private let settings: SettingsManager
    private let queue = DispatchQueue(label: "clippy.capture", qos: .utility)
    private var timer: Timer?
    private var lastChangeCount: Int
    private var skipCounts = Set<Int>()
    public var interval: TimeInterval = 0.4
    /// When set, the next copy from another app is not recorded (one-shot). Cleared once consumed.
    public private(set) var skipNextCopy = false
    public var onSkipStateChange: (@Sendable (Bool) -> Void)?
    public var onOutcome: (@Sendable (CaptureOutcome) -> Void)?

    public init(pipeline: CapturePipeline, settings: SettingsManager) {
        self.pipeline = pipeline; self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval / 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() { timer?.invalidate(); timer = nil }

    public func setSkipNextCopy(_ on: Bool) { skipNextCopy = on; onSkipStateChange?(on) }
    public func toggleSkipNextCopy() -> Bool { setSkipNextCopy(!skipNextCopy); return skipNextCopy }

    /// Call right after Clippy itself writes to the pasteboard so it isn't recorded as a new copy.
    public func ignoreCurrentChange() { skipCounts.insert(pasteboard.changeCount) }

    private func tick() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if skipCounts.remove(count) != nil { return }
        if skipNextCopy { setSkipNextCopy(false); return }   // consumed: this copy is never read or stored
        guard !settings.monitoringPaused else { return }
        guard let clip = readCurrent() else { return }
        queue.async { [pipeline, onOutcome] in onOutcome?(pipeline.process(clip)) }
    }

    private func readCurrent() -> CapturedClip? {
        let types = pasteboard.types ?? []
        let typeNames = types.map(\.rawValue)
        let src = SourceApplicationDetector.detect(pasteboard: pasteboard)
        func clip(_ p: CapturedClip.Payload) -> CapturedClip {
            CapturedClip(payload: p, pasteboardTypes: typeNames, sourceBundle: src.bundle, sourceName: src.name)
        }
        // Concealed/transient items: don't even read the contents into memory.
        if settings.protectSensitive, typeNames.contains(where: SensitiveContentDetector.concealedTypes.contains) {
            return CapturedClip(payload: .text(""), pasteboardTypes: typeNames, sourceBundle: src.bundle, sourceName: src.name)
        }
        // 1. Files
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return clip(.files(urls.map(\.path)))
        }
        // 2. Text (incl. URLs), with its original formatting when the source app provided it
        if let s = pasteboard.string(forType: .string) {
            var c = clip(.text(s))
            if settings.keepFormatting {
                for t in RichContent.keptTypes {
                    if let d = pasteboard.data(forType: NSPasteboard.PasteboardType(t)), d.count <= RichContent.maxBytes { c.rich[t] = d }
                }
            }
            return c
        }
        if let s = pasteboard.string(forType: .URL) { return clip(.text(s)) }
        // 3. Images
        if let png = pasteboard.data(forType: .png) { return clip(.image(png)) }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { return clip(.image(png)) }
        return nil
    }
}

/// macOS 15.4+ lets users control whether an app may read the pasteboard programmatically.
public enum PasteboardAccess: Sendable {
    case allowed, ask, denied, unknown

    public static var current: PasteboardAccess {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: return .allowed
            case .ask: return .ask
            case .alwaysDeny: return .denied
            case .default: return .allowed
            @unknown default: return .unknown
            }
        }
        return .allowed   // earlier macOS: no per-app control
    }
}
