import AppKit
import ClippyCore

/// `CLIPPY_DATA_DIR=… CLIPPY_DEFAULTS_SUITE=… Clippy --selftest` — headless end-to-end checks of the panel's logic
/// (search, smart search, command mode, AI results, grouping, pin suggestions, keyboard) against a throwaway store.
@MainActor
enum SelfTest {
    static var failures = 0, passes = 0
    static func check(_ c: Bool, _ msg: String) {
        if c { passes += 1 } else { failures += 1; print("  FAIL \(msg)") }
    }
    static func wait(_ seconds: Double, until cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 50_000_000) }
        return cond()
    }

    static func run() async {
        let ctx = AppContext.shared
        let vm = ctx.panelModel
        let saved = NSPasteboard.general.string(forType: .string)
        defer { if let saved { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(saved, forType: .string) } }
        func copy(_ t: String, times: Int = 1) { for _ in 0..<times { ctx.pipeline.process(CapturedClip(payload: .text(t), sourceName: "SelfTest")) } }

        print("• seeding")
        copy("docker compose up -d"); copy("npm run dev"); copy("https://github.com/AnujWadi-Git/Clippy")
        copy("https://www.amazon.jobs/en/jobs/12345/software-engineer"); copy("123 Main St, San Francisco, CA 94105")
        copy("+1 415 555 2671"); copy("{\"name\":\"clippy\",\"tags\":[\"a\",\"b\"]}")
        copy("hey can u send that file i need it rn")
        copy("import json\nwith open('f.json') as f:\n    data = json.load(f)")
        copy("resume v1 final draft"); copy("resume v2 final draft"); copy("resume v3 final draft")
        copy("me@example.com", times: 6)
        copy("AKIAIOSFODNN7EXAMPLE")
        check(ctx.repository.snapshot().count == 13, "13 items stored (secret dropped), got \(ctx.repository.snapshot().count)")
        check(!ctx.repository.snapshot().contains { $0.preview.contains("AKIA") }, "secret not stored")
        vm.reset()

        print("• keyword search + keys")
        vm.query = "docker"
        check(vm.results.map(\.preview) == ["docker compose up -d"], "docker → \(vm.results.map(\.preview))")
        vm.query = ""
        check(vm.handleKey(keyCode: 125, chars: "", flags: []) && vm.selection == 1, "down arrow moves selection")
        vm.query = "x"; check(vm.handleKey(keyCode: 53, chars: "", flags: []) && vm.query.isEmpty, "esc clears query first")

        print("• pin suggestion + grouping")
        vm.reset()
        check(vm.pinSuggestion?.preview == "me@example.com", "pin suggestion for 6× email: \(String(describing: vm.pinSuggestion?.preview))")
        let resumeRows = vm.rows.compactMap { r -> Int? in if case .item(let i, _, let sim, _) = r, i.preview.hasPrefix("resume") { return sim }; return nil }
        check(resumeRows == [2], "resume versions collapsed into one row with +2: \(resumeRows)")
        if let idx = vm.results.firstIndex(where: { $0.preview.hasPrefix("resume") }) {
            vm.selection = idx
            _ = vm.handleKey(keyCode: 124, chars: "", flags: [])
            check(vm.results.filter { $0.preview.hasPrefix("resume") }.count == 3, "→ expands similar items")
            _ = vm.handleKey(keyCode: 123, chars: "", flags: [])
            check(vm.results.filter { $0.preview.hasPrefix("resume") }.count == 1, "← collapses")
        } else { check(false, "resume lead not found") }
        vm.acceptPinSuggestion()
        check(ctx.repository.snapshot().first { $0.preview == "me@example.com" }?.pinned == true, "accepting suggestion pins")
        check(vm.pinSuggestion == nil, "suggestion cleared after pin")

        print("• semantic / memory search")
        ctx.semanticIndex.reconcile(items: ctx.repository.snapshot(), limit: 100)
        check(ctx.semanticIndex.isAvailable && ctx.semanticIndex.count >= 10, "index built: \(ctx.semanticIndex.count)")
        for (q, want) in [("that command for starting my docker containers", "docker compose up -d"),
                          ("the github link I copied earlier", "https://github.com/AnujWadi-Git/Clippy"),
                          ("amazon job link", "https://www.amazon.jobs/en/jobs/12345/software-engineer"),
                          ("what was that address", "123 Main St, San Francisco, CA 94105"),
                          ("python code for reading json", "import json")] {
            vm.reset(); vm.query = q
            _ = await wait(4) { vm.smartActive }
            let top = vm.results.first?.preview ?? "nil"
            check(top.hasPrefix(want), "“\(q)” → \(top.prefix(40))")
        }
        vm.reset(); vm.query = "? zebra spaceship quarterly"
        _ = await wait(4) { vm.smartActive }
        check(vm.smartNoMatch && vm.results.isEmpty, "no-match is explicit (smartNoMatch=\(vm.smartNoMatch), results=\(vm.results.count))")

        print("• command mode + transforms")
        vm.reset(); vm.query = "clippy"
        check(vm.results.first?.category == .json, "found json item: \(vm.results.map(\.preview))")
        vm.query = ">pretty"
        check(vm.commandResults.first == .prettyJSON, "‘>pretty’ → \(vm.commandResults.map(\.title))")
        if let t = vm.commandTarget {
            vm.perform(.prettyJSON, on: t)
            check(NSPasteboard.general.string(forType: .string)?.contains("\n  \"name\"") == true, "pretty JSON copied to pasteboard")
            check(ctx.repository.snapshot().contains { $0.sourceName == "Clippy · Pretty JSON" }, "result stored as new item")
        } else { check(false, "no command target") }
        vm.reset(); vm.query = "https://x.com"; // no match; just ensure no crash
        vm.reset()
        copy("https://example.com/p?id=7&utm_source=news&fbclid=zzz")
        vm.query = "example.com/p"
        if let linkItem = vm.results.first { vm.perform(.cleanLink, on: linkItem) }
        check(ctx.repository.snapshot().contains { $0.text == "https://example.com/p?id=7" }, "tracking params stripped")

        print("• on-device AI")
        if let why = ctx.ai.unavailableReason() { print("  skipped: \(why)") } else {
            vm.reset(); vm.query = "send that file"
            guard let note = vm.results.first else { check(false, "note not found"); return finish() }
            check(vm.availableActions(for: note).contains(.ai(.rewrite(.professional))), "rewrite offered for text")
            vm.perform(.ai(.rewrite(.professional)), on: note)
            check(vm.busy != nil, "busy indicator shown")
            let done = await wait(60) { vm.busy == nil }
            check(done, "AI finished")
            let result = ctx.repository.snapshot().first { $0.sourceName == "Clippy · Make Professional" }
            check(result != nil && result!.text != note.text, "rewrite stored as new item: \(result?.text ?? "nil")")
            check(NSPasteboard.general.string(forType: .string) == result?.text, "rewrite copied, ready to paste")
            if let r = result { print("  “hey can u send that file i need it rn” → “\(r.text ?? "")”") }
            // sensitive refusal
            copy("Authorization: Bearer abcdef123456")  // dropped anyway
            check(AIGuardProbe.refuses("AKIAIOSFODNN7EXAMPLE"), "AI guard refuses secrets")
        }
        finish()
    }

    static func finish() {
        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

enum AIGuardProbe {
    static func refuses(_ s: String) -> Bool { (try? AIGuard.validate(s)) == nil }
}
