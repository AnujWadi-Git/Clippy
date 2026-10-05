import Foundation

/// An operation offered in the ⌘K menu. `ai` ones need a model; everything else is deterministic.
public enum ItemAction: Hashable, Sendable {
    // universal
    case paste, pastePlain, copy, pin, unpin, delete
    // links
    case openLink, copyDomain, cleanLink
    // json
    case prettyJSON, minifyJSON, validateJSON
    // email / command / files
    case composeEmail, runInTerminal, reveal
    // AI (user-triggered only)
    case ai(AITask)

    public var title: String {
        switch self {
        case .paste: return "Paste"
        case .pastePlain: return "Paste as Plain Text"
        case .copy: return "Copy"
        case .pin: return "Pin"
        case .unpin: return "Unpin"
        case .delete: return "Delete"
        case .openLink: return "Open Link"
        case .copyDomain: return "Extract Domain"
        case .cleanLink: return "Remove Tracking Parameters"
        case .prettyJSON: return "Pretty Print"
        case .minifyJSON: return "Minify"
        case .validateJSON: return "Validate"
        case .composeEmail: return "Compose Email"
        case .runInTerminal: return "Run in Terminal…"
        case .reveal: return "Reveal in Finder"
        case .ai(let t): return t.title
        }
    }

    public var symbol: String {
        switch self {
        case .paste: return "return"
        case .pastePlain: return "textformat"
        case .copy: return "doc.on.doc"
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .delete: return "trash"
        case .openLink: return "safari"
        case .copyDomain: return "globe"
        case .cleanLink: return "scissors"
        case .prettyJSON: return "text.alignleft"
        case .minifyJSON: return "arrow.down.right.and.arrow.up.left"
        case .validateJSON: return "checkmark.seal"
        case .composeEmail: return "envelope"
        case .runInTerminal: return "terminal"
        case .reveal: return "folder"
        case .ai(let t): return t.symbol
        }
    }

    public var isAI: Bool { if case .ai = self { return true }; return false }
    public var isDestructive: Bool { self == .delete }
}

public enum ActionCatalog {
    public static let translateLanguages = ["Spanish", "French", "German", "Hindi", "Portuguese", "Japanese", "Chinese", "Italian"]
    public static let convertLanguages = ["Python", "Swift", "JavaScript", "TypeScript", "Go", "Rust"]

    static let errorRegex = try! NSRegularExpression(pattern: "(error|exception|traceback|fatal|failed|cannot find|undefined is not|segmentation fault|panic:)", options: .caseInsensitive)

    public static func looksLikeError(_ text: String) -> Bool {
        errorRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Ordered, grouped by relevance. Keeps the menu short: the most specific actions first.
    public static func actions(for item: ClipboardItem, aiAvailable: Bool) -> [ItemAction] {
        var a: [ItemAction] = [.paste]
        let isText = item.kind == .text || item.kind == .url
        if isText { a.append(.pastePlain) }
        a.append(.copy)
        let text = item.text ?? ""

        switch item.category {
        case .link:
            a += [.openLink, .copyDomain, .cleanLink]
        case .json:
            a += [.prettyJSON, .minifyJSON, .validateJSON]
            if aiAvailable { a.append(.ai(.explainCode)) }
        case .code:
            if aiAvailable { a += [.ai(.explainCode), .ai(.formatCode), .ai(.convertCode("Python")), .ai(.convertCode("JavaScript"))] }
            if looksLikeError(text), aiAvailable { a.append(.ai(.explainError)) }
        case .command:
            a.append(.runInTerminal)
            if aiAvailable { a.append(.ai(.explainCommand)) }
        case .email:
            a.append(.composeEmail)
        case .path, .file:
            a.append(.reveal)
        case .message, .other, .address, .phone:
            break
        case .image: break
        }
        if isText, aiAvailable, [.message, .other].contains(item.category) {
            a += RewriteStyle.allCases.map { .ai(.rewrite($0)) }
            a.append(.ai(.translate("Spanish")))
            if text.count >= 200 { a.append(.ai(.summarize)) }
            if looksLikeError(text) { a.append(.ai(.explainError)) }
        }
        if aiAvailable, item.category == .link { /* “Summarize Page” would require fetching the URL; intentionally not offered. */ }
        a.append(item.pinned ? .unpin : .pin)
        a.append(.delete)
        return a
    }
}

/// Deterministic text transforms (no AI, no network).
public enum Transforms {
    public static func prettyJSON(_ s: String) -> String? { reformat(s, pretty: true) }
    public static func minifyJSON(_ s: String) -> String? { reformat(s, pretty: false) }

    private static func reformat(_ s: String, pretty: Bool) -> String? {
        guard let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) else { return nil }
        var opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
        if pretty { opts.insert(.prettyPrinted); opts.insert(.withoutEscapingSlashes) } else { opts.insert(.withoutEscapingSlashes) }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: opts) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    public static func validateJSON(_ s: String) -> (valid: Bool, message: String) {
        guard let d = s.data(using: .utf8) else { return (false, "Not valid UTF-8") }
        do { _ = try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]); return (true, "Valid JSON") }
        catch { return (false, ((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String) ?? "Invalid JSON") }
    }

    public static func domain(_ s: String) -> String? {
        URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines))?.host
    }

    static let trackingKeys: Set<String> = ["fbclid", "gclid", "gclsrc", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid", "_hsenc", "_hsmi",
                                            "ref_src", "ref_url", "spm", "si", "s_cid", "vero_id", "mkt_tok", "oly_enc_id", "oly_anon_id"]
    public static func isTrackingKey(_ k: String) -> Bool { k.lowercased().hasPrefix("utm_") || trackingKeys.contains(k.lowercased()) }

    public static func stripTracking(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: t), let items = c.queryItems else { return nil }
        let kept = items.filter { !isTrackingKey($0.name) }
        guard kept.count != items.count else { return nil }
        c.queryItems = kept.isEmpty ? nil : kept
        return c.string
    }

    public static func mailto(_ s: String) -> URL? {
        let e = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "mailto:\(e)")
    }

    /// A self-deleting script that shows the command and then runs it, for opening in Terminal.
    public static func terminalScript(for command: String) -> String {
        "#!/bin/zsh\n\(command)\nrm -f \"$0\"\n"
    }
}
