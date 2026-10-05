import Foundation

/// On-device LLM helpers for retrieval. The model never sees more than short previews of candidate items, never
/// produces item content, and its answers are mapped back to REAL items by number: it can reorder or filter
/// candidates, it cannot invent one.
public struct SearchAssistant: Sendable {
    private let ai: AIService
    public init(ai: AIService) { self.ai = ai }

    public var isAvailable: Bool { ai.unavailableReason() == nil }

    /// Related keywords an item answering the request might contain ("start my containers" → docker, compose, up…).
    public func expand(_ query: String) async -> [String] {
        let prompt = """
        A user is searching their clipboard history. Request: "\(query)"
        List 8 to 12 single-word keywords, synonyms and related technical terms (tool names, commands, file types, \
        country codes, jargon) likely to appear in a clipboard item that satisfies the request. \
        Reply with the words only, lowercase, comma-separated.
        """
        guard let out = try? await ai.run(.custom, input: prompt) else { return [] }
        let stop = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        var seen = Set<String>(), words: [String] = []
        for raw in out.lowercased().split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let w = raw.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'.-•*0123456789)(")))
            guard w.count >= 2, w.count <= 24, !w.contains(" "), !stop.contains(w), seen.insert(w).inserted else { continue }
            words.append(w)
        }
        return Array(words.prefix(12))
    }

    /// Picks which numbered candidates satisfy the request. nil = the model failed (caller keeps its own ranking);
    /// [] = the model says none match.
    public func select(query: String, candidates: [ClipboardItem]) async -> [ClipboardItem]? {
        guard !candidates.isEmpty else { return [] }
        let listing = candidates.enumerated().map { i, c in
            "\(i + 1). [\(c.category.rawValue)] \(String((c.text ?? c.preview).replacingOccurrences(of: "\n", with: " ⏎ ").prefix(110)))"
        }.joined(separator: "\n")
        let prompt = """
        A user is looking for something they copied earlier. Request: "\(query)"

        Clipboard items:
        \(listing)

        Which items does the user most plausibly mean? Be strict: only include items that genuinely fit the request. \
        Reply with ONLY the item numbers, best first, comma-separated (at most 5). If nothing fits, reply NONE.
        """
        guard let out = try? await ai.run(.custom, input: prompt) else { return nil }
        if out.uppercased().contains("NONE") && !out.contains(where: \.isNumber) { return [] }
        var seen = Set<Int>(), picked: [ClipboardItem] = []
        for n in out.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }) where (1...candidates.count).contains(n) && seen.insert(n).inserted {
            picked.append(candidates[n - 1])
        }
        return picked
    }
}
