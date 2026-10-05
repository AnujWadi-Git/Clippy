import Foundation

public enum AIProviderKind: String, Sendable { case local = "On-device", cloud = "Cloud" }

public struct AIResult: Sendable {
    public let text: String
    public let provider: AIProviderKind
}

public enum AIError: Error, LocalizedError, Sendable {
    case disabled, unavailable(String), refusedSensitive, emptyInput, failed(String)
    public var errorDescription: String? {
        switch self {
        case .disabled: return "AI features are turned off in Settings."
        case .unavailable(let r): return r
        case .refusedSensitive: return "This looks sensitive, so Clippy won't send it to any AI."
        case .emptyInput: return "Nothing to process."
        case .failed(let m): return "AI request failed: \(m)"
        }
    }
}

/// Swap-able backend for text tasks. Implementations must not persist or log the input.
public protocol AIService: Sendable {
    var kind: AIProviderKind { get }
    /// nil when ready, otherwise a user-facing reason it can't be used.
    func unavailableReason() -> String?
    func run(_ task: AITask, input: String) async throws -> String
}

/// A raw chat-completion backend a CloudAIService can wrap (Anthropic today; others later).
public protocol CloudProvider: Sendable {
    var name: String { get }
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
}

/// Defense in depth: even though sensitive items are never stored, re-check right before any AI call.
public enum AIGuard {
    public static func validate(_ input: String) throws {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.emptyInput }
        if SensitiveContentDetector(dropBareNumericCodes: false).check(text: String(input.prefix(20_000))) != nil {
            throw AIError.refusedSensitive
        }
    }
}
