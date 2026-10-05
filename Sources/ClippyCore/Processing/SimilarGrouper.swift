import Foundation

public struct ItemGroup: Identifiable, Sendable {
    public var id: String { lead.id }
    public let lead: ClipboardItem
    public var others: [ClipboardItem]
    public var count: Int { 1 + others.count }
}

/// Groups near-identical versions (resume v1/v2/v3, edited snippets) so the timeline isn't a wall of look-alikes.
/// Purely lexical (character-trigram Jaccard): deterministic, instant, and works without any model.
/// Cost control: only the most recent `window` groupable items are compared; signatures are cached per content hash;
/// pairs whose trigram-set sizes differ too much are skipped without computing the intersection.
public enum SimilarGrouper {
    public static let window = 250

    private final class SigBox { let grams: Set<UInt32>; init(_ g: Set<UInt32>) { grams = g } }
    private static let cache: NSCache<NSString, SigBox> = { let c = NSCache<NSString, SigBox>(); c.countLimit = 4000; return c }()

    public static func group(_ items: [ClipboardItem]) -> [ItemGroup] {
        var groups: [ItemGroup] = []
        var leadSigs: [(index: Int, sig: Set<UInt32>, category: ClipCategory, length: Int)] = []
        var compared = 0
        for item in items {
            guard canGroup(item), let text = item.text, compared < window else { groups.append(ItemGroup(lead: item, others: [])); continue }
            compared += 1
            let sig = signature(of: item.contentHash, text: text)
            let length = text.count
            if let lead = leadSigs.first(where: { $0.category == item.category && similar($0.sig, sig, length: length) }) {
                groups[lead.index].others.append(item)
            } else {
                groups.append(ItemGroup(lead: item, others: []))
                leadSigs.append((groups.count - 1, sig, item.category, length))
            }
        }
        return groups
    }

    static func canGroup(_ i: ClipboardItem) -> Bool {
        !i.pinned && !i.isHeldSensitive && (i.kind == .text || i.kind == .url) && (i.text?.count ?? 0) >= 8
            && ![.phone, .email].contains(i.category)
    }

    private static func signature(of key: String, text: String) -> Set<UInt32> {
        if let hit = cache.object(forKey: key as NSString) { return hit.grams }
        let g = trigrams(text)
        cache.setObject(SigBox(g), forKey: key as NSString)
        return g
    }

    static func trigrams(_ s: String) -> Set<UInt32> {
        // lowercase, collapse whitespace, first 2000 chars; trigrams packed from scalar values into a 32-bit hash
        var scalars: [UInt32] = []
        scalars.reserveCapacity(256)
        var lastSpace = true
        for u in s.lowercased().unicodeScalars.prefix(2000) {
            if u.properties.isWhitespace { if !lastSpace { scalars.append(32); lastSpace = true } } else { scalars.append(u.value); lastSpace = false }
        }
        guard scalars.count >= 3 else { return [scalars.reduce(2166136261) { ($0 ^ $1) &* 16777619 }] }
        var out = Set<UInt32>(minimumCapacity: scalars.count)
        for i in 0...(scalars.count - 3) {
            var h: UInt32 = 2166136261                      // FNV-1a over three scalars
            h = (h ^ scalars[i]) &* 16777619; h = (h ^ scalars[i + 1]) &* 16777619; h = (h ^ scalars[i + 2]) &* 16777619
            out.insert(h)
        }
        return out
    }

    static func similar(_ a: Set<UInt32>, _ b: Set<UInt32>, length: Int) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let threshold = length < 40 ? 0.6 : 0.7
        let (small, big) = a.count <= b.count ? (a, b) : (b, a)
        // Jaccard ≤ |small|/|big|: skip hopeless pairs without computing the intersection.
        if Double(small.count) / Double(big.count) < threshold { return false }
        var inter = 0
        for g in small where big.contains(g) { inter += 1 }
        let j = Double(inter) / Double(a.count + b.count - inter)
        return j >= threshold && j < 1.0
    }
}
