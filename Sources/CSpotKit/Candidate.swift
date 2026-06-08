import Foundation

/// Where a candidate came from. Stable string values are part of the Stage-1↔Stage-2 contract.
public enum Source: String, Codable, Sendable {
    case file, calendar, contact, message, mail, clipboard, app
}

/// How a candidate matched the query. Drives `matchScore` in `LocalRanker`.
public enum MatchKind: String, Codable, Sendable {
    case nameExact = "name_exact"
    case nameFuzzy = "name_fuzzy"
    case content
    case fieldMatch = "field_match"
    case recent
}

/// One normalized result across every source. This is the canonical shape Stage 2 consumes.
public struct Candidate: Codable, Identifiable, Sendable {
    public let id: String          // source-prefixed + stable, e.g. "file:/Users/…/a.pdf", "cal:<uuid>"
    public let source: Source
    public var title: String
    public var subtitle: String? = nil
    public var path: String? = nil
    public var uri: String? = nil
    public var snippet: String? = nil
    public var createdAt: Date? = nil
    public var modifiedAt: Date? = nil
    public var startAt: Date? = nil
    public var endAt: Date? = nil
    public var matchKind: MatchKind
    public var recencyScore: Double = 0
    public var matchScore: Double = 0
    public var localScore: Double = 0
    public var meta: [String: String] = [:]

    public init(id: String, source: Source, title: String, matchKind: MatchKind) {
        self.id = id
        self.source = source
        self.title = title
        self.matchKind = matchKind
    }
}

/// Stage-1 output: the parsed query, the ranked candidates, and whether to escalate to Stage 2.
public struct StageOneResult: Sendable {
    public let query: ParsedQuery
    public let candidates: [Candidate]
    public let shouldEscalate: Bool
}
