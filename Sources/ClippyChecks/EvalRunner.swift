import Foundation
import ClippyCore

/// `swift run ClippyChecks --eval` — compares retrieval pipelines on EvalData. Not part of the pass/fail suite.
func runRetrievalEval() {
    let now = Date()
    var items: [ClipboardItem] = []
    var keyOf: [String: String] = [:]
    for (i, e) in EvalData.items.enumerated() {
        let c = ContentClassifier.classify(text: e.text)
        var it = ClipboardItem(kind: c == .link ? .url : .text, category: c, contentHash: DuplicateDetector.hash(text: e.text), text: e.text,
                               preview: ContentClassifier.preview(e.text), byteSize: e.text.utf8.count,
                               createdAt: now.addingTimeInterval(-Double(i) * 600))
        it.lastUsedAt = it.createdAt
        items.append(it); keyOf[it.id] = e.key
    }
    let sentence = LocalEmbeddingProvider()
    let contextual = ContextualEmbeddingProvider()
    print("categories:", Dictionary(grouping: items, by: \.category).mapValues(\.count).sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue):\($0.value)" }.joined(separator: " "))

    struct Score { var top1 = 0, top3 = 0, mrr = 0.0, fp = 0 }
    func report(_ name: String, _ s: Score, misses: [String]) {
        let n = Double(EvalData.queries.count)
        print(String(format: "%-34@ top1 %2d/%d (%3.0f%%)  top3 %2d/%d (%3.0f%%)  MRR %.2f  false-positive %d/%d",
                     name as NSString, s.top1, EvalData.queries.count, Double(s.top1) / n * 100, s.top3, EvalData.queries.count, Double(s.top3) / n * 100, s.mrr / n, s.fp, EvalData.negatives.count))
        if CommandLine.arguments.contains("--misses") { for m in misses { print("     miss:", m) } }
    }

    func evaluate(_ name: String, rank: (String) -> [ClipboardItem]) {
        var s = Score(); var misses: [String] = []
        for (q, expect) in EvalData.queries {
            let keys = rank(q).compactMap { keyOf[$0.id] }
            if let idx = keys.firstIndex(where: expect.contains) {
                if idx == 0 { s.top1 += 1 }; if idx < 3 { s.top3 += 1 }; s.mrr += 1.0 / Double(idx + 1)
            }
            if keys.first.map(expect.contains) != true { misses.append("“\(q)” → \(keys.prefix(3)) (want \(expect))") }
        }
        for q in EvalData.negatives where !rank(q).isEmpty { s.fp += 1 }
        report(name, s, misses: misses)
    }

    // Runs the async pipeline to completion for the synchronous scorer (model output is live, so variants differ slightly run to run).
    func evaluateAsync(_ name: String, _ run: @escaping (String) async -> [ClipboardItem]) {
        evaluate(name) { q in var out: [ClipboardItem] = []; try? blocking { out = await run(q) }; return out }
    }

    func index(_ p: EmbeddingProvider) -> SemanticIndex {
        let db = try! ClipboardDatabase(path: ":memory:")
        for i in items { try! db.insert(i) }
        let idx = SemanticIndex(database: db, provider: p)
        _ = idx.reconcile(items: items, limit: 1000)
        return idx
    }

    func pureEmbedding(_ p: EmbeddingProvider, describe: Bool) -> (String) -> [ClipboardItem] {
        let vecs: [(ClipboardItem, [Float])] = items.compactMap { i in
            guard let t = describe ? EmbeddingText.describe(i) : i.text, let v = p.embed(t) else { return nil }
            return (i, v)
        }
        return { q in
            guard let qv = p.embed(q) else { return [] }
            return vecs.map { ($0.0, cosine(qv, $0.1)) }.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    let ms = MemorySearch()
    print("\n— pure embedding (cosine only, no intent/keywords; negatives always return results so FP is n/a) —")
    evaluate("sentence, raw text", rank: pureEmbedding(sentence, describe: false))
    evaluate("sentence, described text", rank: pureEmbedding(sentence, describe: true))
    if let c = contextual {
        evaluate("contextual, raw text", rank: pureEmbedding(c, describe: false))
        evaluate("contextual, described text", rank: pureEmbedding(c, describe: true))
    }
    print("\n— full hybrid pipeline (MemorySearch) —")
    evaluate("keywords + intent only") { ms.search($0, items: items, index: nil, now: now).items }
    let sIdx = index(sentence)
    evaluate("hybrid + sentence embeddings") { ms.search($0, items: items, index: sIdx, now: now).items }
    if CommandLine.arguments.contains("--only-sentence") { return }
    if let c = contextual {
        let cIdx = index(c)
        evaluate("hybrid + contextual embeddings") { ms.search($0, items: items, index: cIdx, now: now).items }
    }
    if CommandLine.arguments.contains("--llm") {
        let local = LocalAIService()
        if let why = local.unavailableReason() { print("LLM variants skipped:", why); return }
        let assistant = SearchAssistant(ai: local)
        print("\n— with on-device LLM assistance (live model; takes a few minutes) —")
        if CommandLine.arguments.contains("--balanced-only") {
            evaluateAsync("hybrid + LLM expand + select (balanced)") { q in await ms.assisted(q, items: items, index: sIdx, assistant: assistant, mode: .balanced, now: now).items }
            return
        }
        evaluateAsync("hybrid + LLM expand + select (trust)") { q in await ms.assisted(q, items: items, index: sIdx, assistant: assistant, mode: .trust, now: now).items }
        evaluateAsync("hybrid + LLM expand + select (soft)") { q in await ms.assisted(q, items: items, index: sIdx, assistant: assistant, mode: .soft, now: now).items }
    }
}
