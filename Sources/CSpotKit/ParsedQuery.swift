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
