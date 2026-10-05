import AppKit

/// Best-effort: the pasteboard doesn't record who wrote to it. We prefer the (unofficial but widely used)
/// `org.nspasteboard.source` type, and otherwise fall back to the frontmost app at detection time
/// (can be wrong by up to one poll interval).
public enum SourceApplicationDetector {
    public static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    public static func detect(pasteboard: NSPasteboard) -> (bundle: String?, name: String?) {
        if let bundle = pasteboard.string(forType: sourceType), !bundle.isEmpty {
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName
            return (bundle, name)
        }
        let app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return (nil, nil) }
        return (app?.bundleIdentifier, app?.localizedName)
    }
}
