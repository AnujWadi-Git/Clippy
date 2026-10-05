import Foundation
import Observation

public enum SensitiveMode: String, CaseIterable, Sendable { case drop, memoryOnly }
public enum AppearanceMode: String, CaseIterable, Sendable { case system, light, dark }

/// UserDefaults-backed settings. Defaults implement the product promises (24h, protect sensitive, cloud off).
@Observable
public final class SettingsManager: @unchecked Sendable {
    private let defaults: UserDefaults

    public var retention: RetentionPolicy { didSet { defaults.set(retention.rawValue, forKey: "retention"); onRetentionChange?(retention) } }
    public var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems") } }
    public var maxDiskMB: Int { didSet { defaults.set(maxDiskMB, forKey: "maxDiskMB") } }
    public var ignoreDuplicates: Bool { didSet { defaults.set(ignoreDuplicates, forKey: "ignoreDuplicates") } }
    public var protectSensitive: Bool { didSet { defaults.set(protectSensitive, forKey: "protectSensitive") } }
    public var sensitiveMode: SensitiveMode { didSet { defaults.set(sensitiveMode.rawValue, forKey: "sensitiveMode") } }
    public var ignorePasswordManagers: Bool { didSet { defaults.set(ignorePasswordManagers, forKey: "ignorePasswordManagers") } }
    public var ignoredApps: [String] { didSet { defaults.set(ignoredApps, forKey: "ignoredApps") } }   // bundle IDs
    public var monitoringPaused: Bool { didSet { defaults.set(monitoringPaused, forKey: "monitoringPaused") } }
    public var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    public var pasteAutomatically: Bool { didSet { defaults.set(pasteAutomatically, forKey: "pasteAutomatically") } }
    public var hotkeyKeyCode: Int { didSet { defaults.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") } }
    public var hotkeyModifiers: Int { didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    public var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    // AI (phase 2). Cloud is OFF by default.
    public var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: "aiEnabled") } }
    public var preferLocalAI: Bool { didSet { defaults.set(preferLocalAI, forKey: "preferLocalAI") } }
    public var allowCloudProcessing: Bool { didSet { defaults.set(allowCloudProcessing, forKey: "allowCloudProcessing") } }
    public var cloudProvider: String { didSet { defaults.set(cloudProvider, forKey: "cloudProvider") } }
    public var cloudModel: String { didSet { defaults.set(cloudModel, forKey: "cloudModel") } }
    public var semanticSearch: Bool { didSet { defaults.set(semanticSearch, forKey: "semanticSearch") } }
    public var cleanJunk: Bool { didSet { defaults.set(cleanJunk, forKey: "cleanJunk") } }
    public var pinSuggestions: Bool { didSet { defaults.set(pinSuggestions, forKey: "pinSuggestions") } }
    public var dismissedPinSuggestions: [String] { didSet { defaults.set(dismissedPinSuggestions, forKey: "dismissedPinSuggestions") } }

    @ObservationIgnored public var onRetentionChange: ((RetentionPolicy) -> Void)?

    public static let defaultHotkey = (keyCode: 9 /* V */, modifiers: 0x0800 /* optionKey */)

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: k) as? Bool ?? d }
        func i(_ k: String, _ d: Int) -> Int { defaults.object(forKey: k) as? Int ?? d }
        retention = RetentionPolicy(rawValue: defaults.string(forKey: "retention") ?? "") ?? .default
        maxItems = i("maxItems", 1000)
        maxDiskMB = i("maxDiskMB", 500)
        ignoreDuplicates = b("ignoreDuplicates", true)
        protectSensitive = b("protectSensitive", true)
        sensitiveMode = SensitiveMode(rawValue: defaults.string(forKey: "sensitiveMode") ?? "") ?? .drop
        ignorePasswordManagers = b("ignorePasswordManagers", true)
        ignoredApps = defaults.stringArray(forKey: "ignoredApps") ?? []
        monitoringPaused = b("monitoringPaused", false)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        pasteAutomatically = b("pasteAutomatically", true)
        hotkeyKeyCode = i("hotkeyKeyCode", Self.defaultHotkey.keyCode)
        hotkeyModifiers = i("hotkeyModifiers", Self.defaultHotkey.modifiers)
        hasOnboarded = b("hasOnboarded", false)
        // On-device AI is private and on by default; CLOUD processing stays off until the user opts in.
        aiEnabled = b("aiEnabled", true)
        preferLocalAI = b("preferLocalAI", true)
        allowCloudProcessing = b("allowCloudProcessing", false)
        cloudProvider = defaults.string(forKey: "cloudProvider") ?? "anthropic"
        cloudModel = defaults.string(forKey: "cloudModel") ?? "claude-haiku-4-5-20251001"
        semanticSearch = b("semanticSearch", true)
        pinSuggestions = b("pinSuggestions", true)
        cleanJunk = b("cleanJunk", true)
        dismissedPinSuggestions = defaults.stringArray(forKey: "dismissedPinSuggestions") ?? []
    }

    public var maxDiskBytes: Int { maxDiskMB * 1_048_576 }

    /// Bundle IDs whose copies are never recorded.
    public var effectiveIgnoredBundles: Set<String> {
        var s = Set(ignoredApps)
        if ignorePasswordManagers { s.formUnion(SensitiveContentDetector.defaultIgnoredBundles) }
        return s
    }
}
