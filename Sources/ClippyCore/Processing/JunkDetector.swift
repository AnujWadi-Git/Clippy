import Foundation

/// Deterministic “is this worth keeping?” for early cleanup. It can only make things disappear SOONER;
/// nothing here (or in AI code) can extend the retention window.
public enum JunkDetector {
    public static let minAge: TimeInterval = 300     // never touch something you copied in the last 5 minutes

    static let uiStrings: Set<String> = ["copy", "copied", "copied!", "paste", "loading", "loading...", "loading…", "untitled", "cancel", "close", "undefined", "null", "nan"]
    static let redirectHosts = try! NSRegularExpression(pattern: "^(click|links?|track|trk|email|go|redirect|r|l|t)\\d*\\.", options: .caseInsensitive)

    public static func isJunk(_ item: ClipboardItem, now: Date = Date()) -> Bool {
        guard !item.pinned, now.timeIntervalSince(item.lastUsedAt) >= minAge else { return false }
        guard item.kind == .text || item.kind == .url, let text = item.text else { return false }
        return isJunkText(text)
    }

    public static func isJunkText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if t.count == 1 { return true }                                     // single char / punctuation
        if t.allSatisfy({ !$0.isLetter && !$0.isNumber }) && t.count <= 3 { return true }   // "...", "->", "—"
        if uiStrings.contains(t.lowercased()) { return true }
        if isTrackingRedirect(t) { return true }
        return false
    }

    static func isTrackingRedirect(_ t: String) -> Bool {
        guard !t.contains(" "), let u = URL(string: t), let host = u.host?.lowercased(), u.scheme?.hasPrefix("http") == true else { return false }
        let path = u.path.lowercased()
        if host.hasSuffix("google.com") && path == "/url" && (u.query ?? "").contains("url=") || (host.hasSuffix("google.com") && path == "/url" && (u.query ?? "").contains("q=http")) { return true }
        if host == "l.facebook.com" || host == "lm.facebook.com" { return true }
        if host.hasSuffix("sendgrid.net") && path.hasPrefix("/ls/click") { return true }
        if host.hasSuffix("mandrillapp.com") && path.hasPrefix("/track/click") { return true }
        if host.hasSuffix("list-manage.com") && path.hasPrefix("/track/click") { return true }
        if redirectHosts.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil, path.count > 40, (u.query ?? "").isEmpty { return true }
        return false
    }
}
