import Foundation
import ClippyCore

/// `--perf`: timing of the main-thread paths at the maximum default history size.
func perfChecks() {
    let words = ["alpha", "beta", "gamma", "delta", "func", "return", "docker", "compose", "invoice", "meeting", "report", "value", "token", "result", "swift", "build"]
    var rng = SystemRandomNumberGenerator()
    func text(_ i: Int) -> String {
        (0..<30).map { _ in words.randomElement(using: &rng)! }.joined(separator: " ") + " #\(i)"
    }
    let items: [ClipboardItem] = (0..<1000).map { i in
        let t = text(i)
        return ClipboardItem(kind: .text, category: .message, contentHash: "h\(i)", text: t, preview: ContentClassifier.preview(t), byteSize: t.utf8.count,
                             createdAt: Date().addingTimeInterval(-Double(i)))
    }
    func time(_ label: String, _ body: () -> Void) {
        let t0 = Date(); body(); print(String(format: "  %-34@ %7.1f ms", label as NSString, Date().timeIntervalSince(t0) * 1000))
    }
    print("perf @ 1000 items (~200 chars each):")
    time("SimilarGrouper.group") { _ = SimilarGrouper.group(items) }
    time("SearchEngine.search (1 word)") { _ = SearchEngine().search(items, query: "docker") }
    time("SearchEngine.search (3 words)") { _ = SearchEngine().search(items, query: "docker compose invoice") }
    time("MemorySearch.search (no index)") { _ = MemorySearch().search("the docker command from today", items: items, index: nil) }
}
