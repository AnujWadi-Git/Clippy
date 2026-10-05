import Foundation

public struct ItemGroup: Identifiable, Sendable {
    public var id: String { lead.id }
    public let lead: ClipboardItem
    public var others: [ClipboardItem]
    public var count: Int { 1 + others.count }
}

/// Groups near-identical versions (resume v1/v2/v3, edited snippets) so the timeline isn't a wall of look-alikes.
/// Purely lexical (character trigram Jaccard): deterministic, instant, and works without any model.
public enum SimilarGrouper {
    public static func group(_ items: [ClipboardItem]) -> [ItemGroup] {
        var groups: [ItemGroup] = []
        var grams: [String: Set<String>] = [:]
        for item in items {
            guard canGroup(item), let text = item.text else { groups.append(ItemGroup(lead: item, others: [])); continue }
            let g = trigrams(text)
            grams[item.id] = g
            if let idx = groups.firstIndex(where: { gr in
                canGroup(gr.lead) && gr.lead.category == item.category && similar(grams[gr.lead.id] ?? [], g, text.count)
            }) {
                groups[idx].others.append(item)
            } else {
                groups.append(ItemGroup(lead: item, others: []))
            }
        }
        return groups
    }

    static func canGroup(_ i: ClipboardItem) -> Bool {
        !i.pinned && !i.isHeldSensitive && (i.kind == .text || i.kind == .url) && (i.text?.count ?? 0) >= 8
            && ![.phone, .email].contains(i.category)
    }

    static func trigrams(_ s: String) -> Set<String> {
        let norm = Array(String(s.lowercased().prefix(2000)).split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
        guard norm.count >= 3 else { return [String(norm)] }
        var out = Set<String>()
        for i in 0...(norm.count - 3) { out.insert(String(norm[i..<i + 3])) }
        return out
    }

    static func similar(_ a: Set<String>, _ b: Set<String>, _ length: Int) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let inter = Double(a.intersection(b).count), union = Double(a.union(b).count)
        let j = inter / union
        return j >= (length < 40 ? 0.6 : 0.7) && j < 1.0
    }
}
