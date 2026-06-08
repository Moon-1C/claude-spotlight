import Foundation

/// Pure-local scoring (no LLM). Produces `localScore` that both orders the Stage-1 list and feeds
/// the Stage-2 branch decision.
public enum LocalRanker {
    static func matchScore(_ k: MatchKind) -> Double {
        switch k {
        case .nameExact: return 1.0
        case .nameFuzzy: return 0.7
        case .fieldMatch: return 0.6
        case .content: return 0.5
        case .recent: return 0.3
        }
    }

    /// exp(-ageDays / 14): ~0.93 at 1 day, ~0.49 at 10 days, ~0.14 at 28 days.
    static func recency(_ c: Candidate, now: Date) -> Double {
        let ref: Date?
        switch c.source {
        case .calendar: ref = c.startAt          // proximity to event time
        default:        ref = c.modifiedAt
        }
        guard let d = ref else { return 0 }
        let ageDays = abs(now.timeIntervalSince(d)) / 86_400
        return exp(-ageDays / 14)
    }

    public static func rank(_ candidates: [Candidate], for q: ParsedQuery, now: Date = Date()) -> [Candidate] {
        let queryWords = Set(q.tokens.map { $0.lowercased() })

        var byID: [String: Candidate] = [:]
        for var c in candidates {
            c.matchScore = matchScore(c.matchKind)
            c.recencyScore = recency(c, now: now)
            var blended = 0.6 * c.matchScore + 0.4 * c.recencyScore

            // small boost: a query token equals a whole word of the title
            let titleWords = Set(c.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            if !queryWords.isDisjoint(with: titleWords) { blended += 0.05 }
            // small boost: calendar hit when the query carried a date hint
            if c.source == .calendar, q.dateHint != nil { blended += 0.05 }

            c.localScore = min(1.0, max(0.0, blended))

            if let existing = byID[c.id] {
                if c.localScore > existing.localScore { byID[c.id] = c }
            } else {
                byID[c.id] = c
            }
        }

        return byID.values.sorted {
            $0.localScore != $1.localScore ? $0.localScore > $1.localScore
                : ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }
    }
}
