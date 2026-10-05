import Foundation

/// “Raycast for your clipboard”: type `>` then a command; the selected item is the input.
/// Matching is deliberately forgiving: every word you type must appear somewhere in the command's name or aliases.
public enum CommandMode {
    public static let prefix: Character = ">"

    public static func isCommandQuery(_ q: String) -> Bool { q.hasPrefix(String(prefix)) }
    public static func commandText(_ q: String) -> String { String(q.dropFirst()).trimmingCharacters(in: .whitespaces) }

    public static func aliases(for a: ItemAction) -> String {
        switch a {
        case .prettyJSON: return "json format pretty print prettify beautify indent"
        case .minifyJSON: return "json minify compress compact"
        case .validateJSON: return "json validate check lint verify"
        case .copyDomain: return "domain host extract"
        case .cleanLink: return "clean link url tracking utm strip"
        case .ai(.rewrite(let s)):
            switch s {
            case .improve: return "rewrite improve better polish"
            case .professional: return "rewrite professional formal polite"
            case .friendly: return "rewrite friendly casual warm"
            case .shorter: return "rewrite shorten shorter concise trim"
            case .longer: return "rewrite expand longer elaborate"
            case .grammar: return "rewrite grammar spelling fix proofread"
            }
        case .ai(.summarize): return "summarize summary tldr bullets"
        case .ai(.explainCode), .ai(.explainCommand), .ai(.explainError), .ai(.explainText): return "explain what does meaning"
        case .ai(.convertCode): return "convert port translate code language"
        case .ai(.formatCode): return "format fix formatting indent style"
        case .composeEmail: return "email mail compose send"
        case .runInTerminal: return "run terminal execute shell"
        case .openLink: return "open browser safari"
        default: return ""
        }
    }

    /// Everything applicable to this item, in command-mode order (most useful first).
    public static func commands(for item: ClipboardItem, aiAvailable: Bool) -> [ItemAction] {
        guard item.kind == .text || item.kind == .url, let text = item.text else {
            return [.paste, .copy, item.pinned ? .unpin : .pin, .delete]
        }
        var out: [ItemAction] = []
        let looksJSON = ContentClassifier.isJSON(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if looksJSON || item.category == .json { out += [.prettyJSON, .minifyJSON, .validateJSON] }
        if item.category == .link { out += [.copyDomain, .cleanLink, .openLink] }
        if item.category == .email { out.append(.composeEmail) }
        if item.category == .command { out.append(.runInTerminal) }
        if aiAvailable {
            switch item.category {
            case .command: out.append(.ai(.explainCommand))
            case .code, .json: out += [.ai(.explainCode), .ai(.formatCode)] + ActionCatalog.convertLanguages.map { .ai(.convertCode($0)) }
            default: out.append(.ai(ActionCatalog.looksLikeError(text) ? .explainError : .explainText))
            }
            if item.category != .command {
                out += RewriteStyle.allCases.map { .ai(.rewrite($0)) }
                out.append(.ai(.summarize))
                out += ActionCatalog.translateLanguages.map { .ai(.translate($0)) }
            }
        }
        out += [.copy, item.pinned ? .unpin : .pin, .delete]
        return out
    }

    public static func match(_ query: String, in actions: [ItemAction]) -> [ItemAction] {
        let tokens = SearchEngine.fold(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return actions }
        var scored: [(ItemAction, Int, Int)] = []
        for (i, a) in actions.enumerated() {
            let title = SearchEngine.fold(a.title)
            let hay = title + " " + aliases(for: a)
            guard tokens.allSatisfy({ hay.contains($0) }) else { continue }
            scored.append((a, (title.hasPrefix(tokens[0]) || title.contains(" " + tokens[0])) ? 0 : 1, i))
        }
        return scored.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }
}
