import Foundation

/// Deterministic classification. No AI: every rule is cheap and explainable.
public enum ContentClassifier {
    public static func classify(text: String) -> ClipCategory {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .other }
        let singleLine = !t.contains("\n")

        if singleLine, isURL(t) { return .link }
        if singleLine, matches(email, t) { return .email }
        if singleLine, isPhone(t) { return .phone }
        if isJSON(t) { return .json }
        if singleLine, isPath(t) { return .path }
        if isCommand(t) { return .command }
        if looksLikeCode(t) { return .code }
        return .message
    }

    public static func preview(_ text: String, limit: Int = 200) -> String {
        var out = ""
        out.reserveCapacity(limit)
        var lastSpace = true
        for ch in text.prefix(limit * 3) {
            if ch.isWhitespace { if !lastSpace { out.append(" "); lastSpace = true } }
            else { out.append(ch); lastSpace = false }
            if out.count >= limit { break }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Rules
    private static let email = try! NSRegularExpression(pattern: "^[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}$", options: .caseInsensitive)
    private static let phone = try! NSRegularExpression(pattern: "^\\+?[0-9][0-9 ().\\-]{6,18}[0-9]$")
    private static func matches(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func isURL(_ s: String) -> Bool {
        guard !s.contains(" "), let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return false }
        if ["http", "https", "ftp", "ftps", "ssh", "git", "mailto"].contains(scheme) { return scheme == "mailto" || u.host != nil }
        return false
    }
    static func isPhone(_ s: String) -> Bool {
        guard matches(phone, s) else { return false }
        let digits = s.filter(\.isNumber).count
        return (7...15).contains(digits) && (s.contains("+") || s.contains("(") || s.contains("-") || s.contains(" ") || s.contains("."))
    }
    static func isJSON(_ s: String) -> Bool {
        guard let f = s.first, f == "{" || f == "[", let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
    static func isPath(_ s: String) -> Bool {
        (s.hasPrefix("/") || s.hasPrefix("~/") || s.hasPrefix("./") || s.hasPrefix("../")) && !s.contains("  ") && s.count > 1
            && !s.hasPrefix("//")
    }

    private static let commandHeads: Set<String> = [
        "git", "npm", "npx", "yarn", "pnpm", "docker", "docker-compose", "kubectl", "brew", "pip", "pip3", "python", "python3",
        "node", "cargo", "swift", "swiftc", "xcodebuild", "make", "cmake", "curl", "wget", "ssh", "scp", "rsync", "ls", "cd",
        "cat", "grep", "find", "sed", "awk", "chmod", "chown", "mkdir", "rm", "cp", "mv", "sudo", "echo", "export", "tar",
        "open", "killall", "kill", "ps", "go", "java", "mvn", "gradle", "terraform", "aws", "gcloud", "az", "helm", "conda",
        "uv", "bun", "deno", "gh", "tmux", "vim", "nano", "launchctl", "defaults", "xcrun", "pod", "bundle", "rails", "ruby",
    ]
    static func isCommand(_ s: String) -> Bool {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count <= 5 else { return false }
        return lines.allSatisfy { line in
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("$ ") { l.removeFirst(2) }
            if l.hasPrefix("sudo ") { l.removeFirst(5) }
            guard let head = l.split(separator: " ").first.map(String.init) else { return false }
            return commandHeads.contains(head) || head.hasPrefix("./")
        }
    }

    static func looksLikeCode(_ s: String) -> Bool {
        var score = 0
        let keywords = ["func ", "def ", "class ", "import ", "return ", "const ", "let ", "var ", "function ", "=> ", "#include",
                        "public ", "private ", "struct ", "enum ", "if (", "for (", "while (", "</", "SELECT ", "FROM ", "async ", "await "]
        for k in keywords where s.contains(k) { score += 1 }
        for tok in ["{", "}", ";", "();", "=>", "==", "!=", "&&", "||", "</", "/>"] where s.contains(tok) { score += 1 }
        if s.contains("\n") && s.split(separator: "\n").contains(where: { $0.hasPrefix("    ") || $0.hasPrefix("\t") }) { score += 2 }
        let singleLine = !s.contains("\n")
        return singleLine ? score >= 3 : score >= 3
    }
}
