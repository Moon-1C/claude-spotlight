import Foundation

/// Decides whether a query stops at Stage 1 (instant, free) or escalates to Stage 2 (one LLM call).
/// Default is NOT to escalate; Stage 2 is reserved for genuinely ambiguous / natural-language queries.
public enum Branch {
    public static func decide(_ q: ParsedQuery, _ ranked: [Candidate]) -> Bool {
        // 0) explicit intent wins
        if q.modifiers.contains(.askLLM) { return true }
        if q.modifiers.contains(.literal) { return false }

        // 1) natural-language query (markers / length / "?" / find-show-open) → escalate
        if q.isNaturalLanguage { return true }

        // 2) empty or single-token lexical query → never escalate
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
}
