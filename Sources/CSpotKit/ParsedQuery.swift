import Foundation

public enum QueryModifier: String, Sendable {
    case askLLM     // prefix "?"  → force Stage 2
    case literal    // prefix "="  → force Stage 1 (lexical only)
    case recent     // prefix "recent:" → recency flavor
}

public struct DateHint: Sendable {
    public let start: Date
    public let end: Date
}

/// A user query parsed into tokens, modifiers, and hints. No LLM involved.
public struct ParsedQuery: Sendable {
    public let raw: String                 // query text after stripping a leading modifier marker
    public let tokens: [String]
    public let modifiers: Set<QueryModifier>
    public let kindHint: String?           // pdf | image | screenshot | note | code | movie
    public let dateHint: DateHint?

    public init(raw: String, tokens: [String], modifiers: Set<QueryModifier>,
                kindHint: String?, dateHint: DateHint?) {
        self.raw = raw
        self.tokens = tokens
        self.modifiers = modifiers
        self.kindHint = kindHint
        self.dateHint = dateHint
    }

    private static let kinds = ["pdf", "image", "screenshot", "note", "code", "movie"]

    /// Natural-language filler to drop when extracting the searchable keywords (EN + KO).
    static let stopwords: Set<String> = [
        "the", "a", "an", "i", "me", "my", "mine", "you", "your", "we", "our", "it", "its",
        "is", "are", "was", "were", "be", "been", "do", "did", "does", "done",
        "of", "in", "on", "at", "to", "from", "for", "with", "by", "about", "as",
        "and", "or", "but", "that", "this", "these", "those", "there", "here",
        "find", "show", "open", "get", "give", "search", "look", "want", "need",
        "worked", "work", "made", "make", "sent", "send", "received",
        "recent", "recently", "last", "latest", "yesterday", "today", "tomorrow", "week", "ago",
        "please", "where", "when", "what", "which", "who", "how", "regarding",
        // Korean fillers
        "그", "저", "내", "제", "것", "거", "그거", "이거", "좀", "해줘", "찾아", "찾아줘",
        "관련", "지난", "어제", "오늘", "내일", "보낸", "받은", "에서", "에게", "한",
    ]

    /// Markers that signal a natural-language (not lexical) query (EN + KO).
    static let nlMarkers: Set<String> = [
        "the", "my", "that", "which", "where", "when", "what", "about",
        "for", "with", "from", "last", "yesterday", "tomorrow", "week",
        "meeting", "regarding", "sent", "received", "recently",
        "어제", "지난", "관련", "회의", "보낸", "받은", "찾아",
    ]

    /// Content-bearing tokens (stopwords removed). Falls back to all tokens if everything was filtered.
    public var keywords: [String] {
        let ks = tokens.filter { !Self.stopwords.contains($0.lowercased()) && $0.count >= 2 }
        return ks.isEmpty ? tokens : ks
    }

    /// Whether this reads like a natural-language request rather than a lexical keyword search.
    public var isNaturalLanguage: Bool {
        if modifiers.contains(.literal) { return false }
        if modifiers.contains(.askLLM) { return true }
        if raw.hasSuffix("?") { return true }
        if tokens.count >= 5 { return true }
        if tokens.contains(where: { Self.nlMarkers.contains($0.lowercased()) }) { return true }
        if raw.range(of: #"\b(find|show|open|where('?s)?|which)\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func parse(_ input: String) -> ParsedQuery {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var mods = Set<QueryModifier>()

        if s.hasPrefix("?") {
            mods.insert(.askLLM)
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("=") {
            mods.insert(.literal)
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if s.lowercased().hasPrefix("recent:") {
            mods.insert(.recent)
            s = String(s.dropFirst("recent:".count)).trimmingCharacters(in: .whitespaces)
        }

        let tokens = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let kindHint = tokens.first { kinds.contains($0.lowercased()) }?.lowercased()

        return ParsedQuery(raw: s, tokens: tokens, modifiers: mods, kindHint: kindHint, dateHint: nil)
    }
}
