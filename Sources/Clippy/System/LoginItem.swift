import ServiceManagement

/// Launch at Login via SMAppService (macOS 13+). Most reliable when the app lives in /Applications.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch { NSLog("Clippy: login item change failed: \(error.localizedDescription)"); return false }
    }
}
