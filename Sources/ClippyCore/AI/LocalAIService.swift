import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device language model (Apple Intelligence). Nothing leaves the Mac.
public struct LocalAIService: AIService {
    public let kind = AIProviderKind.local
    public init() {}

    public func unavailableReason() -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let why):
                switch why {
                case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings to use on-device AI."
                case .modelNotReady: return "The on-device model is still downloading."
                @unknown default: return "The on-device model is unavailable."
                }
            }
        }
        #endif
        return "On-device AI needs macOS 26 or later."
    }

    public func run(_ task: AITask, input: String) async throws -> String {
        if let r = unavailableReason() { throw AIError.unavailable(r) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: PromptBuilder.system)
                let prompt = task == .custom ? input : PromptBuilder.userPrompt(task: task, input: input)
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch { throw AIError.failed(error.localizedDescription) }
        }
        #endif
        throw AIError.unavailable("On-device AI needs macOS 26 or later.")
    }
}
