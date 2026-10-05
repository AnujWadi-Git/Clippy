import Foundation
import ClippyCore

func intelligenceChecks() {
    func mk(_ t: String, cat: ClipCategory? = nil, copies: Int = 1, age: TimeInterval = 0, pinned: Bool = false, now: Date = Date()) -> ClipboardItem {
        let c = cat ?? ContentClassifier.classify(text: t)
        var i = ClipboardItem(kind: c == .link ? .url : .text, category: c, contentHash: DuplicateDetector.hash(text: t), text: t,
                              preview: ContentClassifier.preview(t), byteSize: t.utf8.count, createdAt: now.addingTimeInterval(-age), copyCount: copies, pinned: pinned)
        i.lastUsedAt = now.addingTimeInterval(-age)
        return i
    }

    suite("Transforms") {
        expect(Transforms.prettyJSON("{\"b\":1,\"a\":[1,2]}")?.contains("\n") == true)
        expect(Transforms.minifyJSON("{\n  \"a\": 1,\n  \"b\": [1, 2]\n}") == "{\"a\":1,\"b\":[1,2]}", "\(String(describing: Transforms.minifyJSON("{\n \"a\": 1,\n \"b\": [1, 2]\n}")))")
        expect(Transforms.prettyJSON("{nope") == nil)
        expect(Transforms.validateJSON("{\"a\":1}").valid)
        expect(!Transforms.validateJSON("{\"a\":}").valid)
        expect(Transforms.domain("https://docs.docker.com/engine/") == "docs.docker.com")
        expect(Transforms.stripTracking("https://example.com/p?id=7&utm_source=x&fbclid=abc") == "https://example.com/p?id=7")
        expect(Transforms.stripTracking("https://example.com/p?utm_source=x") == "https://example.com/p")
        expect(Transforms.stripTracking("https://example.com/p?id=7") == nil, "nothing to strip → nil")
        expect(Transforms.mailto("me@example.com")?.absoluteString == "mailto:me@example.com")
        expect(Transforms.terminalScript(for: "ls -la").contains("ls -la"))
    }

    suite("ActionCatalog") {
        func titles(_ t: String, ai: Bool = true) -> [String] { ActionCatalog.actions(for: mk(t), aiAvailable: ai).map(\.title) }
        expect(titles("https://example.com").contains("Open Link") && titles("https://example.com").contains("Extract Domain"))
        expect(titles("{\"a\":1}").contains("Pretty Print") && titles("{\"a\":1}").contains("Minify") && titles("{\"a\":1}").contains("Validate"))
        expect(titles("npm run dev").contains("Run in Terminal…") && titles("npm run dev").contains("Explain Command"))
        expect(!titles("npm run dev", ai: false).contains("Explain Command"), "AI actions hidden when unavailable")
        expect(titles("me@example.com").contains("Compose Email"))
        let note = titles("hey can u send that file i need it rn")
        expect(note.contains("Make Professional") && note.contains("Fix Grammar") && note.contains("Shorten") && note.contains("Translate to Spanish"))
        expect(!note.contains("Summarize"), "summarize only for long text")
        expect(titles(String(repeating: "A long document sentence. ", count: 20)).contains("Summarize"))
        expect(titles("Traceback (most recent call last): ValueError: bad").contains("Explain Error"))
        expect(titles("anything").first == "Paste" && titles("anything").last == "Delete")
        let pinned = ActionCatalog.actions(for: mk("x item", pinned: true), aiAvailable: false).map(\.title)
        expect(pinned.contains("Unpin") && !pinned.contains("Pin"))
        expect(ItemAction.ai(.summarize).isAI && !ItemAction.paste.isAI)
    }

    suite("JunkDetector") {
        let now = Date()
        for j in ["x", ".", "  \n ", "...", "->", "Copied!", "loading...", "undefined",
                  "https://www.google.com/url?q=https://example.com&sa=D", "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com"] {
            expect(JunkDetector.isJunk(mk(j, age: 600, now: now), now: now), "junk: \(j)")
        }
        for k in ["ok sure", "42", "docker ps", "https://github.com/a/b", "hello world", "a@b.co", "+1 415 555 0100"] {
            expect(!JunkDetector.isJunk(mk(k, age: 600, now: now), now: now), "keep: \(k)")
        }
        expect(!JunkDetector.isJunk(mk("x", age: 10, now: now), now: now), "fresh copies are never cleaned")
        expect(!JunkDetector.isJunk(mk("x", age: 9999, pinned: true, now: now), now: now), "pinned never cleaned")
    }

    suite("Junk cleanup in repository") {
        let e = try Env()
        _ = e.copy("."); _ = e.copy("keep this note")
        e.clock.advance(60)
        expect(try e.repo.purgeExpired() == 0, "within grace period")
        e.clock.advance(400)
        expect(try e.repo.purgeExpired() == 1)
        expect(e.repo.snapshot().map(\.preview) == ["keep this note"])
        e.settings.cleanJunk = false
        _ = e.copy("x")
        e.clock.advance(1000)
        expect(try e.repo.purgeExpired() == 0, "setting off")
    }

    suite("PinSuggester") {
        let a = mk("docker compose up -d", copies: 8), b = mk("me@example.com", copies: 5), c = mk("hello there", copies: 2)
        expect(PinSuggester.suggestion(from: [c, b, a], dismissedHashes: [])?.id == a.id, "most copied")
        expect(PinSuggester.suggestion(from: [c, b, a], dismissedHashes: [a.contentHash])?.id == b.id, "dismissed skipped")
        expect(PinSuggester.suggestion(from: [c], dismissedHashes: []) == nil)
        expect(PinSuggester.suggestion(from: [mk("x y z note", copies: 9, pinned: true)], dismissedHashes: []) == nil, "already pinned")
        var img = a; img.kind = .image
        expect(PinSuggester.suggestion(from: [img], dismissedHashes: []) == nil)
    }

    suite("SimilarGrouper") {
        let items = [mk("resume v3 final draft"), mk("resume v2 final draft"), mk("resume v1 final draft"),
                     mk("docker compose up -d"), mk("buy milk and eggs tomorrow"),
                     mk("func add(a: Int, b: Int) -> Int { return a + b }"), mk("func add(a: Int, b: Int, c: Int) -> Int { return a + b + c }")]
        let groups = SimilarGrouper.group(items)
        expect(groups.count == 4, "groups: \(groups.map { $0.count })")
        expect(groups[0].count == 3 && groups[0].lead.preview == "resume v3 final draft", "resume versions grouped, newest leads")
        expect(groups.last?.count == 2, "similar code grouped")
        expect(groups.filter { $0.count == 1 }.count == 2)
        let pinned = [mk("resume v1 final draft", pinned: true), mk("resume v2 final draft")]
        expect(SimilarGrouper.group(pinned).count == 2, "pinned never grouped")
        let phones = [mk("+1 415 555 2671"), mk("+1 415 555 2672")]
        expect(SimilarGrouper.group(phones).count == 2, "phones never grouped")
    }
}

func commandModeChecks() {
    func mk(_ t: String) -> ClipboardItem {
        let c = ContentClassifier.classify(text: t)
        return ClipboardItem(kind: c == .link ? .url : .text, category: c, contentHash: t, text: t, preview: t, byteSize: t.utf8.count)
    }
    suite("CommandMode") {
        let note = CommandMode.commands(for: mk("hey can u send that file i need it rn"), aiAvailable: true)
        func titles(_ q: String, _ item: [ItemAction]) -> [String] { CommandMode.match(q, in: item).map(\.title) }
        expect(titles("summarize", note) == ["Summarize"])
        expect(titles("rewrite professional", note) == ["Make Professional"], "\(titles("rewrite professional", note))")
        expect(titles("translate french", note) == ["Translate to French"])
        expect(titles("explain", note) == ["Explain"], "plain text explains generically")
        expect(titles("shorten", note) == ["Shorten"])
        let json = CommandMode.commands(for: mk("{\"a\":1}"), aiAvailable: true)
        expect(titles("json format", json).first == "Pretty Print", "\(titles("json format", json))")
        expect(titles("minify", json) == ["Minify"])
        expect(titles("validate", json) == ["Validate"])
        let cmd = CommandMode.commands(for: mk("rm -rf build"), aiAvailable: true)
        expect(titles("explain", cmd) == ["Explain Command"] && titles("run", cmd) == ["Run in Terminal…"])
        expect(!titles("professional", cmd).contains("Make Professional"), "no rewrite for commands")
        let offline = CommandMode.commands(for: mk("hey there friend ok"), aiAvailable: false)
        expect(CommandMode.match("summarize", in: offline).isEmpty, "AI commands hidden when AI unavailable")
        expect(CommandMode.isCommandQuery(">json") && CommandMode.commandText(">  json format ") == "json format")
        expect(CommandMode.match("", in: note).count == note.count)
        expect(CommandMode.match("zzz", in: note).isEmpty)
        let link = CommandMode.commands(for: mk("https://example.com/a?utm_source=x"), aiAvailable: false)
        expect(titles("domain", link) == ["Extract Domain"] && titles("clean", link) == ["Remove Tracking Parameters"])
    }
}

func archiveChecks() {
    suite("HistoryArchive") {
        let a = try Env()
        _ = a.copy("pinned address 12 Oak Lane"); _ = a.copy("ordinary note about lunch"); _ = a.copy("docker ps -a")
        try a.repo.setPinned(id: a.repo.snapshot().first { $0.preview.hasPrefix("pinned") }!.id, true)
        _ = a.pipeline.process(CapturedClip(payload: .files(["/tmp/a.txt", "/tmp/b.txt"])))
        let png = renderTextImage("not exported")
        _ = a.pipeline.process(CapturedClip(payload: .image(png)))

        let pinnedOnly = try HistoryArchive.export(a.repo.snapshot(), pinnedOnly: true)
        let all = try HistoryArchive.export(a.repo.snapshot(), pinnedOnly: false)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        expect(try dec.decode(HistoryArchive.Archive.self, from: pinnedOnly).entries.count == 1)
        let allEntries = try dec.decode(HistoryArchive.Archive.self, from: all).entries
        expect(allEntries.count == 4 && !allEntries.contains { $0.text.contains("not exported") }, "images excluded: \(allEntries.count)")

        let b = try Env()
        let r = try HistoryArchive.importArchive(all, pipeline: b.pipeline, repository: b.repo)
        expect(r == HistoryArchive.ImportResult(imported: 4, duplicates: 0, skipped: 0, pinned: 1), "\(r)")
        expect(b.repo.snapshot().first { $0.pinned }?.preview == "pinned address 12 Oak Lane")
        expect(b.repo.snapshot().contains { $0.kind == .file }, "files restored")
        let again = try HistoryArchive.importArchive(all, pipeline: b.pipeline, repository: b.repo)
        expect(again.duplicates == 4 && again.imported == 0, "re-import creates no duplicates: \(again)")
        expect(b.repo.snapshot().count == 4)

        // Hostile archive: secrets are filtered on the way in.
        let evil = """
        {"format":"clippy-history","version":1,"exportedAt":"2026-01-01T00:00:00Z","entries":[
         {"text":"AKIAIOSFODNN7EXAMPLE","kind":"text","pinned":true,"copyCount":1,"createdAt":"2026-01-01T00:00:00Z"},
         {"text":"fine text here","kind":"text","pinned":false,"copyCount":1,"createdAt":"2026-01-01T00:00:00Z"}]}
        """.data(using: .utf8)!
        let c = try Env()
        let er = try HistoryArchive.importArchive(evil, pipeline: c.pipeline, repository: c.repo)
        expect(er.imported == 1 && er.skipped == 1 && er.pinned == 0, "\(er)")
        expect(!c.repo.snapshot().contains { $0.preview.contains("AKIA") })
        do { _ = try HistoryArchive.importArchive(Data("{}".utf8), pipeline: c.pipeline, repository: c.repo); expect(false, "should throw") } catch { expect(true) }
    }
}
