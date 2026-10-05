import AppKit
import SwiftUI
import ClippyCore

/// `Clippy --export-screenshots <dir>` renders the REAL panel view (sample data, isolated store) to PNGs in light
/// and dark for the website. No screen-recording permission needed: SwiftUI draws itself via ImageRenderer.
/// Run with CLIPPY_DATA_DIR / CLIPPY_DEFAULTS_SUITE set to throwaway values.
@MainActor
enum ScreenshotExport {
    /// ImageRenderer can hand back an extended/HDR colour space; websites need plain sRGB.
    static func toSRGB(_ img: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }

    static func run(outDir: String) async {
        Brand.exporting = true
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let ctx = AppContext.shared
        let vm = ctx.panelModel

        // --- seed realistic sample clips (oldest first), with real source apps so real icons appear
        let seed: [(String, String, String, Double, Bool)] = [
            ("ssh -i ~/.ssh/id_ed25519 ubuntu@10.0.4.17", "com.apple.Terminal", "Terminal", 540, false),
            ("1600 Amphitheatre Parkway, Mountain View, CA 94043", "com.apple.Maps", "Maps", 660, false),
            ("https://docs.docker.com/compose/compose-file/", "com.apple.Safari", "Safari", 360, false),
            ("Meeting notes: finalize pricing, ship onboarding, hire designer", "com.apple.Notes", "Notes", 300, false),
            ("git reset --soft HEAD~1", "com.apple.Terminal", "Terminal", 180, false),
            ("{\"port\":8080,\"debug\":true,\"db\":{\"host\":\"localhost\"}}", "com.microsoft.VSCode", "Visual Studio Code", 120, false),
            ("hey can u send that file i need it rn", "com.apple.MobileSMS", "Messages", 60 * 60 / 60, false),
            ("https://github.com/AnujWadi-Git/Clippy", "com.google.Chrome", "Google Chrome", 38, false),
            ("docker compose up -d", "com.apple.Terminal", "Terminal", 14, false),
            ("anuj@example.com", "com.apple.mail", "Mail", 2000, true),
            ("742 Evergreen Terrace, Springfield, OR 97477", "com.apple.Notes", "Notes", 2400, true),
        ]
        // ages are given in minutes
        for (text, bundle, name, minutes, pinned) in seed {
            ctx.pipeline.process(CapturedClip(payload: .text(text), sourceBundle: bundle, sourceName: name))
            if let it = ctx.repository.snapshot().first(where: { $0.text == text }) {
                ctx.repository.backdate(id: it.id, by: minutes * 60)
                if pinned { try? ctx.repository.setPinned(id: it.id, true) }
            }
        }
        ctx.semanticIndex.reconcile(items: ctx.repository.snapshot(), limit: 100)

        func wait(_ s: Double, until c: () -> Bool) async { let end = Date().addingTimeInterval(s); while Date() < end, !c() { try? await Task.sleep(nanoseconds: 100_000_000) } }

        func render(_ name: String, scheme: ColorScheme) {
            let content = ClipboardPanelView(vm: vm)
                .environment(\.colorScheme, scheme)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            let r = ImageRenderer(content: content)
            r.scale = 2; r.isOpaque = false
            guard let raw = r.cgImage, let cg = toSRGB(raw), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { print("render failed: \(name)"); return }
            let path = "\(outDir)/\(name)-\(scheme == .dark ? "dark" : "light").png"
            try? png.write(to: URL(fileURLWithPath: path)); print("wrote \(path) (\(cg.width)x\(cg.height))")
        }

        for scheme in [ColorScheme.dark, .light] {
            // 1. browse
            vm.reset(); vm.selection = 1
            await wait(1) { false }
            render("panel-browse", scheme: scheme)

            // 2. smart search
            vm.reset(); vm.query = "that command for starting my docker containers"
            await wait(90) { vm.smartActive && !vm.refining && !vm.results.isEmpty }
            await wait(1.2) { false }
            render("panel-search", scheme: scheme)

            // 3. command mode on a casual message
            vm.reset(); vm.query = "send that file"
            await wait(1) { false }
            vm.query = ">rewrite"
            await wait(1) { false }
            render("panel-command", scheme: scheme)

            // 4. ⌘K actions on a link
            vm.reset(); vm.query = "github"
            await wait(1) { false }
            _ = vm.handleKey(keyCode: 40, chars: "k", flags: .command)
            await wait(0.5) { false }
            render("panel-actions", scheme: scheme)
        }
        print("done")
        exit(0)
    }
}
