import AppKit

let app = NSApplication.shared
if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in await SelfTest.run() }
    app.run()
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
