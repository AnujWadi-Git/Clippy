import Foundation

/// Anthropic Messages API. Only reachable when the user has enabled cloud processing AND stored a key.
public struct AnthropicProvider: CloudProvider {
    public let name = "Anthropic"
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey; self.model = model; self.session = session
    }

    public func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system,
                                   "messages": [["role": "user", "content": user]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.failed("No response") }
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw AIError.failed(msg ?? "HTTP \(http.statusCode)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { throw AIError.failed("Unexpected response") }
        return content.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Wraps any CloudProvider. `isPermitted` is evaluated on every call so toggling the setting takes effect at once.
public struct CloudAIService: AIService {
    public let kind = AIProviderKind.cloud
    private let provider: @Sendable () -> CloudProvider?
    private let isPermitted: @Sendable () -> Bool

    public init(provider: @escaping @Sendable () -> CloudProvider?, isPermitted: @escaping @Sendable () -> Bool) {
        self.provider = provider; self.isPermitted = isPermitted
    }

    public func unavailableReason() -> String? {
        if !isPermitted() { return "Cloud processing is turned off in Settings → AI." }
        if provider() == nil { return "Add a cloud API key in Settings → AI." }
        return nil
    }

    public func run(_ task: AITask, input: String) async throws -> String {
        if let r = unavailableReason() { throw AIError.unavailable(r) }
        guard let p = provider() else { throw AIError.unavailable("No cloud provider configured.") }
        return try await p.complete(system: PromptBuilder.system, user: PromptBuilder.userPrompt(task: task, input: input), maxTokens: 1500)
    }
}

/// Picks a backend per the user's settings. Local first by default; cloud only if explicitly allowed.
public final class AIRouter: @unchecked Sendable {
    private let settings: SettingsManager
    private let local: AIService
    private let cloud: AIService

    public init(settings: SettingsManager, local: AIService, cloud: AIService) {
        self.settings = settings; self.local = local; self.cloud = cloud
    }

    private func candidates() -> [AIService] {
        settings.preferLocalAI ? [local, cloud] : [cloud, local]
    }

    /// nil when at least one backend is usable.
    public func unavailableReason() -> String? {
        guard settings.aiEnabled else { return AIError.disabled.localizedDescription }
        var reasons: [String] = []
        for c in candidates() { if let r = c.unavailableReason() { reasons.append(r) } else { return nil } }
        return reasons.first
    }

    public var isAvailable: Bool { unavailableReason() == nil }

    public func run(_ task: AITask, input: String) async throws -> AIResult {
        guard settings.aiEnabled else { throw AIError.disabled }
        try AIGuard.validate(input)
        var lastError: Error = AIError.unavailable(unavailableReason() ?? "No AI backend available.")
        for svc in candidates() where svc.unavailableReason() == nil {
            do { return AIResult(text: try await svc.run(task, input: input), provider: svc.kind) }
            catch { lastError = error }
        }
        throw lastError
    }
}
