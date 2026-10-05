import Foundation

public enum ClipFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", text = "Text", code = "Code", links = "Links", images = "Images", files = "Files", pinned = "Pinned"
    public var id: String { rawValue }

    public func accepts(_ i: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return i.pinned
        case .images: return i.kind == .image
        case .files: return i.kind == .file || i.category == .path
        case .links: return i.category == .link
        case .code: return [.code, .command, .json].contains(i.category)
        case .text: return i.kind == .text && ![.code, .command, .json, .link, .path].contains(i.category)
        }
    }
}

/// Instant in-memory search over history. Every query token must match (AND).
/// Ranking: word-prefix > substring, preview hit > body hit, pinned and recent bias.
public struct SearchEngine: Sendable {
    public init() {}

    public func search(_ items: [ClipboardItem], query: String, filter: ClipFilter = .all) -> [ClipboardItem] {
        let filtered = filter == .all ? items : items.filter(filter.accepts)
        let tokens = Self.fold(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return filtered }

        var scored: [(ClipboardItem, Double)] = []
        for item in filtered {
            let preview = Self.fold(item.preview)
            let body = item.text.map { Self.fold(String($0.prefix(4000))) } ?? ""
            let meta = Self.fold("\(item.category.rawValue) \(item.sourceName ?? "") \(item.kind.rawValue)")
            var total = 0.0
            var ok = true
            for t in tokens {
                var s = 0.0
                if let r = preview.range(of: t) {
                    s = Self.isWordStart(preview, r.lowerBound) ? 10 : 6
                } else if body.contains(t) { s = 3 }
                else if meta.contains(t) { s = 1.5 }
                if s == 0 { ok = false; break }
                total += s
            }
            guard ok else { continue }
            if item.pinned { total += 1 }
            total += max(0, 1 - Date().timeIntervalSince(item.lastUsedAt) / 86400) * 0.5
            scored.append((item, total))
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastUsedAt > $1.0.lastUsedAt }.map(\.0)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
    private static func isWordStart(_ s: String, _ i: String.Index) -> Bool {
        if i == s.startIndex { return true }
        let prev = s[s.index(before: i)]
        return !prev.isLetter && !prev.isNumber
    }
}
