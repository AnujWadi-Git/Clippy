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
        guard let text = item.text, !item.isHeldSensitive, [.text, .url, .image].contains(item.kind) else { return nil }
        if item.kind == .image { return "text in image: \(String(text.prefix(500)))" }
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

/// Apple's contextual (transformer) text embedding, mean-pooled over token vectors. Needs the on-device
/// language assets; returns nil from `init` if they aren't present (we never trigger a download ourselves).
public final class ContextualEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public let modelID: String
    private let embedding: NLContextualEmbedding
    private let lock = NSLock()

    public init?() {
        guard let e = NLContextualEmbedding(language: .english), e.hasAvailableAssets else { return nil }
        do { try e.load() } catch { return nil }
        embedding = e
        modelID = "nl-contextual-\(e.modelIdentifier)"
    }

    public func embed(_ text: String) -> [Float]? {
        let t = String(text.prefix(1200))
        guard !t.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let result = try? embedding.embeddingResult(for: t, language: .english) else { return nil }
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var n = 0.0
        result.enumerateTokenVectors(in: t.startIndex..<t.endIndex) { vec, _ in
            for i in 0..<min(vec.count, sum.count) { sum[i] += vec[i] }
            n += 1
            return true
        }
        guard n > 0 else { return nil }
        var f = sum.map { Float($0 / n) }
        let norm = sqrt(f.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        for i in f.indices { f[i] /= norm }
        return f
    }
}
