import Foundation

/// Deterministic understanding of a natural-language clipboard question:
/// "the github link I copied this morning" → categories {link}, keywords [github], time = this morning.
/// Cheap, explainable, and the reason retrieval never needs to trust a model to decide what exists.
public struct QueryIntent: Equatable, Sendable {
    public var categories: Set<ClipCategory> = []
    public var kinds: Set<ClipKind> = []
    public var keywords: [String] = []
    public var languageHints: [String] = []
    /// Category words that also literally appear in matching content (e.g. “json”), used as a small relevance bonus.
    public var literalHints: [String] = []
    public var since: Date?
    public var until: Date?
    public var timeLabel: String?

    public var hasConstraints: Bool { !categories.isEmpty || !kinds.isEmpty || !keywords.isEmpty || since != nil }

    static let filler: Set<String> = [
        "find", "show", "me", "what", "was", "were", "is", "are", "the", "that", "this", "those", "a", "an", "i", "my", "mine", "we",
        "copied", "copy", "copying", "earlier", "before", "recently", "recent", "last", "please", "which", "where", "did", "do",
        "have", "had", "has", "got", "get", "from", "of", "about", "for", "to", "in", "on", "at", "with", "it", "one", "some",
        "something", "thing", "stuff", "up", "give", "look", "looking", "search", "can", "you", "could", "ago", "just", "and", "or",
        "then", "out", "any", "all", "again", "over", "there", "those", "me", "saved", "pasted", "clipboard", "clip", "item", "into",
        "how", "why", "when", "who", "whom", "whose", "does", "would", "should", "will", "need", "needs", "want", "wanted", "like", "using", "use", "used",
        "our", "your", "their", "its", "by", "as", "be", "been", "being", "am", "if", "so", "but", "not", "no", "yes", "than", "too", "very", "also", "http", "https", "www", "com",
    ]
    static let categoryWords: [String: (cats: [ClipCategory], kinds: [ClipKind])] = [
        "link": ([.link], []), "links": ([.link], []), "url": ([.link], []), "urls": ([.link], []), "website": ([.link], []),
        "webpage": ([.link], []), "site": ([.link], []), "page": ([.link], []),
        "command": ([.command], []), "commands": ([.command], []), "terminal": ([.command], []), "shell": ([.command], []), "cli": ([.command], []),
        "code": ([.code, .json], []), "snippet": ([.code], []), "function": ([.code], []), "script": ([.code, .command], []),
        "json": ([.json], []),
        "email": ([.email], []), "emails": ([.email], []), "mail": ([.email], []),
        "phone": ([.phone], []), "mobile": ([.phone], []), "telephone": ([.phone], []),
        "address": ([.address], []), "street": ([.address], []), "location": ([.address], []),
        "path": ([.path], []), "folder": ([.path], []), "directory": ([.path], []),
        "image": ([], [.image]), "images": ([], [.image]), "screenshot": ([], [.image]), "picture": ([], [.image]), "photo": ([], [.image]),
        "file": ([.file, .path], [.file]), "files": ([.file, .path], [.file]), "document": ([.file], [.file]),
        "message": ([.message], []), "note": ([.message], []), "notes": ([.message], []), "text": ([.message], []),
    ]
    static let genericCategoryWords: Set<String> = ["link", "links", "url", "urls", "website", "webpage", "site", "page", "code", "snippet", "function", "script",
        "text", "note", "notes", "message", "file", "files", "document", "image", "images", "picture", "photo", "screenshot", "folder", "directory", "location", "street", "terminal", "shell", "mobile", "telephone", "path", "command", "commands"]
    /// Tokens that suggest a programming language, used to reward matching code.
    static let languageSignatures: [String: [String]] = [
        "python": ["import ", "def ", "self.", "print(", "elif "], "swift": ["func ", "let ", "var ", "guard ", "import Foundation", "struct "],
        "javascript": ["const ", "=>", "function", "console.log"], "js": ["const ", "=>", "function"], "typescript": ["interface ", ": string", "const ", "=>"], "ts": ["interface ", ": string", "=>"],
        "java": ["public class", "System.out", "void "], "rust": ["fn ", "let mut", "impl ", "::"], "go": ["func ", "package ", ":="], "ruby": ["def ", "end\n", "puts "],
        "sql": ["select ", "from ", "where ", "insert into"], "html": ["</", "<div", "<html"], "css": ["{", "px", "color:"], "bash": ["#!/bin", "echo ", "$("], "kotlin": ["fun ", "val "], "php": ["<?php", "$"],
    ]
    static let languageWords: Set<String> = ["python", "swift", "javascript", "typescript", "js", "ts", "java", "rust", "go", "ruby", "sql", "html", "css", "bash", "c++", "kotlin", "php"]

    public static func parse(_ query: String, now: Date = Date(), calendar: Calendar = .current) -> QueryIntent {
        var intent = QueryIntent()
        var q = SearchEngine.fold(query).replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ",", with: " ")
        q = " " + q + " "

        // --- time ---
        let startOfToday = calendar.startOfDay(for: now)
        func at(_ hour: Int, daysAgo: Int = 0) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)!)!
        }
        func strip(_ s: String) { q = q.replacingOccurrences(of: s, with: " ") }
        if q.contains(" this morning ") { intent.since = at(4); intent.until = at(12); intent.timeLabel = "this morning"; strip(" this morning ") }
        else if q.contains(" this afternoon ") { intent.since = at(12); intent.until = at(18); intent.timeLabel = "this afternoon"; strip(" this afternoon ") }
        else if q.contains(" this evening ") || q.contains(" tonight ") { intent.since = at(17); intent.timeLabel = "this evening"; strip(" this evening "); strip(" tonight ") }
        else if q.contains(" last night ") { intent.since = at(18, daysAgo: 1); intent.until = at(5); intent.timeLabel = "last night"; strip(" last night ") }
        else if q.contains(" yesterday ") { intent.since = at(0, daysAgo: 1); intent.until = startOfToday; intent.timeLabel = "yesterday"; strip(" yesterday ") }
        else if q.contains(" today ") { intent.since = startOfToday; intent.timeLabel = "today"; strip(" today ") }
        else if let m = q.range(of: #" (?:last|past) (\d+|an?|one|few) (minute|min|hour|hr|day)s? "#, options: .regularExpression) {
            let parts = q[m].split(separator: " ")
            let n = Double(parts[1]) ?? (parts[1] == "few" ? 3 : 1)
            let unit = String(parts[2])
            let secs = unit.hasPrefix("min") ? 60.0 : unit.hasPrefix("h") ? 3600.0 : 86400.0
            intent.since = now.addingTimeInterval(-n * secs); intent.timeLabel = "last \(parts[1]) \(unit)s"
            q.replaceSubrange(m, with: " ")
        } else if q.contains(" an hour ago ") || q.contains(" hour ago ") { intent.since = now.addingTimeInterval(-2 * 3600); intent.timeLabel = "about an hour ago"; strip(" an hour ago "); strip(" hour ago ") }
        else if q.contains(" few minutes ago ") { intent.since = now.addingTimeInterval(-30 * 60); intent.timeLabel = "a few minutes ago"; strip(" few minutes ago ") }

        // --- categories / keywords ---
        for raw in q.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" && $0 != "#" && $0 != "." && $0 != "-" }) {
            let w = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            guard !w.isEmpty else { continue }
            if filler.contains(w) { continue }
            if let c = categoryWords[w] { intent.categories.formUnion(c.cats); intent.kinds.formUnion(c.kinds); if !genericCategoryWords.contains(w) { intent.literalHints.append(w) }; continue }
            if languageWords.contains(w) { intent.languageHints.append(w); intent.categories.formUnion([.code, .command, .json]); continue }
            intent.keywords.append(w)
        }
        return intent
    }
}
