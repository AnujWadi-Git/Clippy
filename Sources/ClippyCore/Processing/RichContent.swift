import Foundation

/// (De)serialisation of the original pasteboard formatting kept alongside a text item.
public enum RichContent {
    public static let maxBytes = 1_000_000
    /// Pasteboard types worth keeping. Everything else (private app types) is ignored.
    public static let keptTypes = ["public.rtf", "public.html"]

    public static func encode(_ types: [String: Data]) -> Data? {
        let kept = types.filter { keptTypes.contains($0.key) && !$0.value.isEmpty }
        guard !kept.isEmpty, kept.values.reduce(0, { $0 + $1.count }) <= maxBytes else { return nil }
        return try? PropertyListEncoder().encode(kept)
    }

    public static func decode(_ data: Data) -> [String: Data]? {
        try? PropertyListDecoder().decode([String: Data].self, from: data)
    }
}
