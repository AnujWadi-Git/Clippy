import AppKit

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--export-screenshots"), CommandLine.arguments.count > i + 1 {
    let dir = CommandLine.arguments[i + 1]
    Task { @MainActor in await ScreenshotExport.run(outDir: dir) }
    app.run()
} else if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in await SelfTest.run() }
    app.run()
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
