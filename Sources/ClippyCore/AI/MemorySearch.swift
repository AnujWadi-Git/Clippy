import Foundation

public struct MemoryHit: Sendable {
    public let item: ClipboardItem
    public let score: Double
    public let why: String
    public init(item: ClipboardItem, score: Double, why: String) { self.item = item; self.score = score; self.why = why }
}

public struct MemoryResult: Sendable {
    public let hits: [MemoryHit]
    public let intent: QueryIntent
    public var items: [ClipboardItem] { hits.map(\.item) }
    public init(hits: [MemoryHit], intent: QueryIntent) { self.hits = hits; self.intent = intent }
    /// Shown when there is nothing. Produced by the app, never by a model.
    public static let none = "No matching clipboard item found."
}

/// "Clipboard memory": natural-language retrieval over stored history ONLY.
/// Candidates come from deterministic filters + keyword + embedding signals, so a result can never be an
/// item that doesn't exist. An optional on-device LLM may re-order the top candidates by ID, nothing more.
public struct MemorySearch: Sendable {
    public var semanticMinimum: Float = 0.62      // embedding-only matches (no category/keyword signal) must clear this
    public var semanticFloor: Float = 0.25        // below this the embedding contributes nothing

    public init() {}

    public func search(_ query: String, items: [ClipboardItem], index: SemanticIndex?, now: Date = Date(), limit: Int = 30) -> MemoryResult {
        let intent = QueryIntent.parse(query, now: now)
        let pool = items.filter { !$0.isHeldSensitive }
        var queryVec: [Float]?
        if index?.isAvailable == true, !intent.keywords.isEmpty || intent.categories.isEmpty {
            queryVec = index?.embedQuery(query)
        }

        var hits: [MemoryHit] = []
        for item in pool {
            // Hard filter: time window.
            if let s = intent.since, item.lastUsedAt < s && item.createdAt < s { continue }
            if let u = intent.until, item.lastUsedAt >= u && item.createdAt >= u { continue }

            let preview = SearchEngine.fold(item.preview)
            let body = SearchEngine.fold(String((item.text ?? "").prefix(4000)))
            var score = 0.0
            var reasons: [String] = []

            let catMatch = intent.categories.contains(item.category) || intent.kinds.contains(item.kind)
            if catMatch { score += 3; reasons.append(item.category.rawValue) }

            var kwHits = 0
            for k in intent.keywords {
                let stem = k.count > 3 && k.hasSuffix("s") ? String(k.dropLast()) : k
                if preview.contains(stem) { score += 2.5; kwHits += 1 }
                else if body.contains(stem) { score += 1.2; kwHits += 1 }
            }
            if kwHits > 0 { reasons.append("matches “\(intent.keywords.prefix(3).joined(separator: " "))”") }
            for l in intent.languageHints {
                if body.contains(l) { score += 1.5 }
                else if let sigs = QueryIntent.languageSignatures[l], sigs.contains(where: { (item.text ?? "").contains($0) }) { score += 1.5 }
            }
            for h in intent.literalHints where body.contains(h) || preview.contains(h) { score += 1.5 }

            var sem: Float = 0
            if let qv = queryVec, let iv = index?.vector(for: item.id) {
                sem = cosine(qv, iv)
                if sem > semanticFloor { score += Double(sem - semanticFloor) * 8; reasons.append("similar meaning") }
            }

            // Admission: some real signal, or a pure time/“what did I copy” question.
            let hasSignal = catMatch || kwHits > 0 || sem >= semanticMinimum
            if intent.hasConstraints && !(intent.categories.isEmpty && intent.keywords.isEmpty && intent.kinds.isEmpty) && !hasSignal { continue }
            // With keywords present, a category-only match is weaker than a keyword match but still admitted.
            if !intent.keywords.isEmpty && kwHits == 0 && sem < semanticMinimum && !catMatch { continue }

            score += max(0, 1 - now.timeIntervalSince(item.lastUsedAt) / 86_400) * 0.4
            if item.pinned { score += 0.3 }
            hits.append(MemoryHit(item: item, score: score, why: reasons.joined(separator: ", ")))
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.item.lastUsedAt > $1.item.lastUsedAt }
        return MemoryResult(hits: Array(hits.prefix(limit)), intent: intent)
    }

    /// Optionally let the on-device model promote the best candidates. It sees only numbered previews and
    /// answers with numbers; anything outside the candidate list is ignored. Never removes a candidate.
    public func rerank(_ result: MemoryResult, query: String, ai: AIRouter?) async -> MemoryResult {
        guard let ai, ai.isAvailable, result.hits.count > 1 else { return result }
        let top = Array(result.hits.prefix(8))
        let listing = top.enumerated().map { "\($0.offset + 1). [\($0.element.item.category.rawValue)] \(String($0.element.item.preview.prefix(120)))" }.joined(separator: "\n")
        let prompt = "Request: \(query)\n\nCandidates:\n\(listing)\n\nReply with ONLY the numbers of the candidates that best match the request, best first, separated by commas."
        guard let reply = try? await ai.run(.rewrite(.improve), input: prompt, rawPrompt: true).text else { return result }
        let nums = reply.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { (1...top.count).contains($0) }
        var seen = Set<Int>(), order: [MemoryHit] = []
        for n in nums where seen.insert(n).inserted { order.append(top[n - 1]) }
        guard !order.isEmpty else { return result }
        let promoted = Set(order.map(\.item.id))
        let rest = result.hits.filter { !promoted.contains($0.item.id) }
        return MemoryResult(hits: order + rest, intent: result.intent)
    }
}
