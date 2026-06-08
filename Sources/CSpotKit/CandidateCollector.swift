import Foundation

/// A Stage-1 source that turns a parsed query into candidates with no LLM and no network.
public protocol CandidateSource: Sendable {
    var name: String { get }
    func collect(_ q: ParsedQuery) async -> [Candidate]
}

/// Fans out across sources concurrently, merges, locally ranks, and decides whether to escalate.
/// Each source self-budgets; the collector additionally caps total wall time.
public struct CandidateCollector: Sendable {
    public let sources: [CandidateSource]
    public let hardBudgetMs: Int

    public init(sources: [CandidateSource], hardBudgetMs: Int = 300) {
        self.sources = sources
        self.hardBudgetMs = hardBudgetMs
    }

    public func collect(_ q: ParsedQuery) async -> StageOneResult {
        let sources = self.sources

        // Each source self-budgets (FileSource caps each mdfind flavor at ~280ms; CalendarSource is
        // sub-10ms on a 2-week window), so awaiting all of them is bounded by the slowest source.
        let all: [Candidate] = await withTaskGroup(of: [Candidate].self) { group in
            for src in sources {
                group.addTask { await src.collect(q) }
            }
            var acc: [Candidate] = []
            for await partial in group { acc += partial }
            return acc
        }

        let ranked = LocalRanker.rank(all, for: q)
        return StageOneResult(query: q, candidates: ranked, shouldEscalate: Branch.decide(q, ranked))
    }
}
