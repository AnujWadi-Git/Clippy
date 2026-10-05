import Foundation
import ClippyCore

/// Deterministic stand-in for an embedding model: hashed bag of words.
struct BagOfWordsEmbedder: EmbeddingProvider {
    let modelID = "test-bow"
    func embed(_ text: String) -> [Float]? {
        var v = [Float](repeating: 0, count: 128)
        for w in SearchEngine.fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            v[abs(String(w).hashValue) % 128] += 1
        }
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard n > 0 else { return nil }
        return v.map { $0 / n }
    }
}

func searchIntelligenceChecks() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    // Wed 2026-10-14 15:30 UTC
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 15, minute: 30))!

    suite("Address classifier") {
        for a in ["123 Main St, Springfield, IL 62701", "1600 Pennsylvania Avenue NW, Washington, DC 20500", "42 Wallaby Way, Sydney"] {
            expect(ContentClassifier.classify(text: a) == .address, "address: \(a) → \(ContentClassifier.classify(text: a))")
        }
        for n in ["5 apples and 3 oranges", "2 street lights were out", "Meeting at 3pm", "100"] {
            expect(ContentClassifier.classify(text: n) != .address, "not address: \(n)")
        }
    }

    suite("QueryIntent") {
        var i = QueryIntent.parse("the github link I copied this morning", now: now, calendar: cal)
        expect(i.categories == [.link] && i.keywords == ["github"], "\(i)")
        expect(i.since == cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 4)) && i.timeLabel == "this morning")
        i = QueryIntent.parse("that Python code for reading JSON", now: now, calendar: cal)
        expect(i.categories.isSuperset(of: [.code, .json]) && i.languageHints == ["python"] && i.keywords == ["reading"], "\(i)")
        i = QueryIntent.parse("What was that address I copied this morning?", now: now, calendar: cal)
        expect(i.categories.contains(.address) && i.keywords.isEmpty, "\(i)")
        i = QueryIntent.parse("Find the API endpoint I copied earlier.", now: now, calendar: cal)
        expect(i.keywords == ["api", "endpoint"], "\(i)")
        i = QueryIntent.parse("Show me Python code I copied today", now: now, calendar: cal)
        expect(i.since == cal.startOfDay(for: now) && i.categories.contains(.code), "\(i)")
        i = QueryIntent.parse("something from yesterday", now: now, calendar: cal)
        expect(i.since == cal.date(from: DateComponents(year: 2026, month: 10, day: 13)) && i.until == cal.startOfDay(for: now))
        i = QueryIntent.parse("links from the last 2 hours", now: now, calendar: cal)
        expect(i.since == now.addingTimeInterval(-7200) && i.categories == [.link], "\(i)")
        i = QueryIntent.parse("the Amazon job link", now: now, calendar: cal)
        expect(i.categories == [.link] && i.keywords == ["amazon", "job"], "\(i)")
    }

    func item(_ t: String, age: TimeInterval = 60, pinned: Bool = false, held: Bool = false) -> ClipboardItem {
        let cat = ContentClassifier.classify(text: t)
        var it = ClipboardItem(kind: cat == .link ? .url : .text, category: cat, contentHash: DuplicateDetector.hash(text: t + "\(age)"),
                               text: t, preview: held ? "🔒 ••••••" : ContentClassifier.preview(t), byteSize: t.utf8.count,
                               createdAt: now.addingTimeInterval(-age), pinned: pinned)
        it.lastUsedAt = now.addingTimeInterval(-age)
        return it
    }
    let corpus = [
        item("docker compose up -d", age: 600),
        item("https://github.com/AnujWadi-Git/Clippy", age: 7200),
        item("import json\nwith open('f.json') as f:\n    data = json.load(f)", age: 3600),
        item("Meeting notes: discuss Q3 roadmap with design team", age: 5000),
        item("+1 415 555 2671", age: 90_000),
        item("123 Main St, San Francisco, CA 94105", age: 20_000),
        item("npm run dev", age: 300),
        item("https://www.amazon.jobs/en/jobs/12345/software-engineer", age: 10_000),
        item("hey can u send that file i need it rn", age: 100),
        item("https://api.example.com/v2/users/{id}/orders", age: 4000),
        item("482913", age: 10, held: true),
    ]

    suite("MemorySearch (deterministic signals only)") {
        let ms = MemorySearch()
        func top(_ q: String) -> String? { ms.search(q, items: corpus, index: nil, now: now).hits.first?.item.preview }
        expect(top("the github link I copied earlier") == "https://github.com/AnujWadi-Git/Clippy", "github: \(String(describing: top("the github link I copied earlier")))")
        expect(top("amazon job link")?.contains("amazon.jobs") == true)
        expect(top("what was that address") == "123 Main St, San Francisco, CA 94105")
        expect(top("phone number") == "+1 415 555 2671")
        expect(top("python code for reading json")?.hasPrefix("import json") == true)
        expect(top("that command for starting my docker containers") == "docker compose up -d", "\(String(describing: top("that command for starting my docker containers")))")
        expect(top("api endpoint")?.contains("api.example.com") == true)
        // Time window is a hard filter
        let today = ms.search("links from today", items: corpus, index: nil, now: now)
        expect(today.hits.allSatisfy { $0.item.category == .link } && today.items.count == 3, "links today: \(today.items.count)")
        let yesterday = ms.search("something from yesterday", items: corpus, index: nil, now: now)
        expect(yesterday.items.map(\.preview) == ["+1 415 555 2671"], "\(yesterday.items.map(\.preview))")
        // No hallucination
        expect(ms.search("zebra spaceship", items: corpus, index: nil, now: now).hits.isEmpty)
        expect(ms.search("kubernetes helm chart", items: corpus, index: nil, now: now).hits.isEmpty)
        expect(MemoryResult.none == "No matching clipboard item found.")
        // Held-sensitive items never surface
        expect(ms.search("code 482913", items: corpus, index: nil, now: now).items.allSatisfy { !$0.isHeldSensitive })
        expect(ms.search("what did I copy", items: corpus, index: nil, now: now).items.count == corpus.count - 1, "pure recency question lists everything searchable")
    }

    suite("SemanticIndex persistence rules") {
        let db = try ClipboardDatabase(path: ":memory:")
        let a = item("docker compose up -d"), b = item("remember to buy milk"), c = item("pinned note about wifi password policy", pinned: true)
        for x in [a, b, c] { try db.insert(x) }   // pinned insert without crypto is fine for the test
        let idx = SemanticIndex(database: db, provider: BagOfWordsEmbedder())
        expect(idx.reconcile(items: [a, b, c]) == 3)
        expect(try db.embeddingCount() == 2, "pinned vector is NOT persisted")
        expect(idx.vector(for: c.id) != nil, "…but is available in memory")
        // reload from disk
        let idx2 = SemanticIndex(database: db, provider: BagOfWordsEmbedder())
        expect(idx2.count == 2)
        // unpinning persists it
        var c2 = c; c2.pinned = false
        _ = idx.reconcile(items: [a, b, c2])
        expect(try db.embeddingCount() == 3)
        // pinning removes the persisted row
        var a2 = a; a2.pinned = true
        _ = idx.reconcile(items: [a2, b, c2])
        expect(try db.embeddingCount() == 2)
        // deleted items disappear
        _ = idx.reconcile(items: [b])
        expect(idx.count == 1)
        // held-sensitive text is never embedded
        let h = item("482913", held: true)
        _ = idx.reconcile(items: [h])
        expect(idx.vector(for: h.id) == nil)
        idx.purge()
        expect(try db.embeddingCount() == 0 && idx.count == 0)
    }

    suite("MemorySearch with embeddings") {
        let db = try ClipboardDatabase(path: ":memory:")
        let idx = SemanticIndex(database: db, provider: BagOfWordsEmbedder())
        for x in corpus where !x.isHeldSensitive { try db.insert(x) }
        _ = idx.reconcile(items: corpus, limit: 100)
        let ms = MemorySearch()
        let r = ms.search("docker compose", items: corpus, index: idx, now: now)
        expect(r.hits.first?.item.preview == "docker compose up -d")
        expect(ms.search("zebra spaceship", items: corpus, index: idx, now: now).hits.isEmpty, "unrelated query still empty with embeddings")
    }

    suite("Embedding model is released when idle") {
        let p = LocalEmbeddingProvider(idleRelease: 0.3)
        guard p.isAvailable else { print("  skipped"); return }
        expect(!p.isLoaded, "not loaded until used")
        expect(p.embed("hello world") != nil && p.isLoaded)
        Thread.sleep(forTimeInterval: 0.8)
        expect(!p.isLoaded, "released after idle")
        expect(p.embed("hello again") != nil, "reloads transparently")
    }

    suite("MemorySearch with real on-device embeddings") {
        let real = LocalEmbeddingProvider()
        guard real.isAvailable else { print("  skipped: NLEmbedding unavailable"); return }
        let db = try ClipboardDatabase(path: ":memory:")
        for x in corpus where !x.isHeldSensitive { try db.insert(x) }
        let idx = SemanticIndex(database: db, provider: real)
        _ = idx.reconcile(items: corpus, limit: 100)
        let ms = MemorySearch()
        let qs: [(String, String)] = [("that command for starting my docker containers", "docker compose up -d"),
                                      ("the github link i copied earlier", "https://github.com/AnujWadi-Git/Clippy"),
                                      ("amazon job link", "https://www.amazon.jobs/en/jobs/12345/software-engineer"),
                                      ("what was that address", "123 Main St, San Francisco, CA 94105"),
                                      ("start dev server", "npm run dev")]
        for (q, want) in qs {
            let hits = ms.search(q, items: corpus, index: idx, now: now).items.map(\.preview)
            expect(hits.first == want, "real-embedding top1 for “\(q)”: got \(hits.prefix(2))")
        }
        for q in ["zebra spaceship", "chocolate cake recipe", "quarterly tax filing deadline"] {
            let n = ms.search(q, items: corpus, index: idx, now: now).hits.count
            expect(n == 0, "unrelated “\(q)” returned \(n) hits")
        }
    }
}
