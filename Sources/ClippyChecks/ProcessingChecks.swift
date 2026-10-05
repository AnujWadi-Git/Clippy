import Foundation
import ClippyCore

func processingChecks() {
    suite("ContentClassifier") {
        let cases: [(String, ClipCategory)] = [
            ("https://github.com/foo/bar", .link), ("http://localhost:3000/x?y=1", .link),
            ("me@example.com", .email), ("+1 (415) 555-2671", .phone), ("415-555-2671", .phone),
            ("{\"a\": 1, \"b\": [1,2]}", .json), ("[1, 2, 3]", .json),
            ("/Users/anuj/file.txt", .path), ("~/Documents/x", .path),
            ("docker compose up -d", .message), // 'docker compose' head is docker → command; overwritten below
            ("npm run dev", .command), ("git commit -m \"x\"", .command), ("$ brew install node", .command),
            ("func hello() {\n    print(\"hi\")\n}", .code), ("const x = () => { return 1; }", .code),
            ("hey can u send that file i need it rn", .message), ("Meeting notes: discuss roadmap", .message),
            ("12345", .message),
        ]
        for (text, want) in cases where text != "docker compose up -d" {
            let got = ContentClassifier.classify(text: text)
            expect(got == want, "\(text.prefix(30)) → \(got), wanted \(want)")
        }
        expect(ContentClassifier.classify(text: "docker compose up -d") == .command)
        expect(ContentClassifier.preview("  a \n\n  b   c ") == "a b c")
    }
    suite("DuplicateDetector") {
        expect(DuplicateDetector.hash(text: "hello") == DuplicateDetector.hash(text: "hello"))
        expect(DuplicateDetector.hash(text: "hello") != DuplicateDetector.hash(text: "Hello"))
        expect(DuplicateDetector.hash(text: "hello").count == 64)
        let d = Data([1, 2, 3])
        expect(DuplicateDetector.hash(data: d, kind: .image) != DuplicateDetector.hash(data: d, kind: .file))
    }
    suite("SearchEngine") {
        func item(_ t: String, pinned: Bool = false, age: TimeInterval = 0) -> ClipboardItem {
            let cat = ContentClassifier.classify(text: t)
            return ClipboardItem(kind: cat == .link ? .url : .text, category: cat, contentHash: DuplicateDetector.hash(text: t + "\(age)"),
                                 text: t, preview: ContentClassifier.preview(t), byteSize: t.utf8.count,
                                 createdAt: Date().addingTimeInterval(-age), pinned: pinned)
        }
        let items = [item("docker compose up -d"), item("Dockerfile", age: 60), item("docker build .", age: 5),
                     item("https://docs.docker.com/", age: 120), item("Meeting notes", age: 30),
                     item("café menu", age: 10), item("+1 415 555 2671", pinned: true)]
        let e = SearchEngine()
        expect(e.search(items, query: "docker").count == 4)
        expect(e.search(items, query: "docker up").count == 1)
        expect(e.search(items, query: "cafe").count == 1, "diacritics")
        expect(e.search(items, query: "DOCKER").count == 4, "case")
        expect(e.search(items, query: "zzz").isEmpty)
        expect(e.search(items, query: "", filter: .links).count == 1)
        expect(e.search(items, query: "", filter: .pinned).count == 1)
        expect(e.search(items, query: "", filter: .code).count == 2)
        expect(e.search(items, query: "").count == items.count)
        expect(e.search(items, query: "docker").first?.preview == "docker compose up -d", "recent+prefix first")
    }
}
