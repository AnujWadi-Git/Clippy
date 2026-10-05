import Foundation
import NaturalLanguage

public protocol EmbeddingProvider: Sendable {
    /// Identifies the model so stale vectors are ignored if it changes.
    var modelID: String { get }
    /// L2-normalised vector, or nil if the text can't be embedded.
    func embed(_ text: String) -> [Float]?
}

/// Apple's on-device sentence embedding (NaturalLanguage). No network, no model download by us.
public struct LocalEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public let modelID = "nl-sentence-en-v1"
    private let embedding: NLEmbedding?

    public init() { embedding = NLEmbedding.sentenceEmbedding(for: .english) }
    public var isAvailable: Bool { embedding != nil }

    public func embed(_ text: String) -> [Float]? {
        guard let e = embedding, let v = e.vector(for: String(text.prefix(1000))) else { return nil }
        var f = v.map { Float($0) }
        let norm = sqrt(f.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        for i in f.indices { f[i] /= norm }
        return f
    }
}

public enum EmbeddingText {
    /// What we actually embed. Prefixing a category label measurably improves ranking of terse items
    /// like commands and URLs (see docs/DESIGN.md → AI notes); URLs are split into words.
    public static func describe(_ item: ClipboardItem) -> String? {
        guard item.kind == .text || item.kind == .url, let text = item.text, !item.isHeldSensitive else { return nil }
        let label: String
        switch item.category {
        case .command: label = "terminal command"
        case .link: label = "web link url"
        case .code: label = "code snippet"
        case .json: label = "json data"
        case .email: label = "email address"
        case .phone: label = "phone number"
        case .address: label = "street address location"
        case .path: label = "file path"
        default: label = "text note"
        }
        var body = String(text.prefix(500))
        if item.category == .link {
            body = body.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                .components(separatedBy: CharacterSet(charactersIn: "/.-_{}?=&:")).filter { !$0.isEmpty }.joined(separator: " ")
        }
        return "\(label): \(body)"
    }
}

public func cosine(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return 0 }
    var d: Float = 0
    for i in a.indices { d += a[i] * b[i] }
    return d   // vectors are pre-normalised
}
