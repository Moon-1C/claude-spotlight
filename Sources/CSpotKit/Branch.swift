import Foundation

/// Decides whether a query stops at Stage 1 (instant, free) or escalates to Stage 2 (one LLM call).
/// Default is NOT to escalate; Stage 2 is reserved for genuinely ambiguous / natural-language queries.
public enum Branch {
    public static func decide(_ q: ParsedQuery, _ ranked: [Candidate]) -> Bool {
        // 0) explicit intent wins
        if q.modifiers.contains(.askLLM) { return true }
        if q.modifiers.contains(.literal) { return false }

        // 1) natural-language markers → escalate
        if hasNLMarkers(q) { return true }

        // 2) long / multi-clause query → escalate
        if q.tokens.count >= 5 { return true }

        // 3) empty or single-token lexical query → never escalate
        if q.tokens.count <= 1 { return false }

        // 4) ambiguity test on local scores
        guard let top = ranked.first else { return false }
        let second = ranked.dropFirst().first?.localScore ?? 0
        let decisive = top.localScore >= 0.75 && (top.localScore - second) >= 0.15
        let viable = ranked.filter { $0.localScore >= 0.45 }.count
        if decisive && viable <= 1 { return false }
        if viable >= 2 && (top.localScore - second) < 0.10 { return true }

        // 5) cross-source tie (file AND event both plausible) → escalate
        if Set(ranked.prefix(5).map(\.source)).count >= 2 && viable >= 2 { return true }

        return false
    }

    static let nlMarkers: Set<String> = [
        "the", "my", "that", "which", "where", "when", "what", "about",
        "for", "with", "from", "last", "yesterday", "tomorrow", "week",
        "meeting", "regarding", "sent", "received",
        "어제", "지난", "관련", "회의", "보낸", "받은", "찾아",
    ]

    static func hasNLMarkers(_ q: ParsedQuery) -> Bool {
        let words = q.tokens.map { $0.lowercased() }
        if words.contains(where: nlMarkers.contains) { return true }
        if q.raw.hasSuffix("?") { return true }
        if q.raw.range(of: #"\b(find|show|open|where('?s)?|which)\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
