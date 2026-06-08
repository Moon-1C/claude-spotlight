import Foundation

/// Result of a Stage-2 reasoning pass.
public struct ReasonResult: Sendable {
    public let orderedIDs: [String]   // Candidate.id values, best-first (a reorder/subset of the input)
    public let answer: String?        // one-line natural-language summary
}

/// Stage 2: rank/synthesize Stage-1 candidates against a natural-language query using an LLM.
public protocol Reasoner: Sendable {
    func rank(query: ParsedQuery, candidates: [Candidate]) async -> ReasonResult?
}

/// Reasoner backed by the user's local, logged-in Claude Code CLI run headless (`claude -p`).
/// Uses the subscription via the genuine binary — no API key, no OAuth token handling.
public struct ClaudeCLIReasoner: Reasoner {
    public let model: String?        // e.g. "sonnet" | "haiku" | "opus"; nil → Claude Code default
    public let timeoutSec: Int

    public init(model: String? = "sonnet", timeoutSec: Int = 45) {
        self.model = model
        self.timeoutSec = timeoutSec
    }

    // Structured-output schema (must be INLINE JSON for `--json-schema`; verified on this Mac).
    private static let schema =
        #"{"type":"object","additionalProperties":false,"properties":{"ranked":{"type":"array","items":{"type":"string"}},"answer":{"type":"string"}},"required":["ranked","answer"]}"#

    public func rank(query: ParsedQuery, candidates: [Candidate]) async -> ReasonResult? {
        guard !candidates.isEmpty else { return nil }

        // Compact projection with short stable handles (c0..cn) to save tokens; map back afterward.
        var handleToID: [String: String] = [:]
        var projection: [[String: String]] = []
        for (i, c) in candidates.enumerated() {
            let h = "c\(i)"
            handleToID[h] = c.id
            projection.append([
                "id": h,
                "source": c.source.rawValue,
                "title": c.title,
                "sub": c.subtitle ?? "",
                "mod": c.modifiedAt.map(Self.dayString) ?? "",
                "snip": c.snippet ?? "",
            ])
        }
        guard
            let projData = try? JSONSerialization.data(withJSONObject: projection),
            let projStr = String(data: projData, encoding: .utf8)
        else { return nil }

        let prompt = """
        You are the ranking engine for a macOS search launcher. Rank the candidate items by how well \
        they match the user's natural-language query by MEANING (not just keyword overlap). Return \
        best-first in "ranked" using each item's "id". Include only plausibly relevant items and drop \
        clearly irrelevant ones; if nothing matches well, return an empty "ranked". Give a concise \
        one-sentence "answer" describing what you found (or that nothing matched). Do not use any tools.

        Query: \(query.raw)

        Candidates (JSON array): \(projStr)
        """

        var args = ["-p", "--output-format", "json", "--json-schema", Self.schema]
        if let model { args += ["--model", model] }

        guard let output = await Self.runClaude(args: args, stdin: prompt, timeoutSec: timeoutSec),
              let env = Self.parseEnvelope(output)
        else { return nil }

        if let isError = env["is_error"] as? Bool, isError { return nil }
        guard let structured = env["structured_output"] as? [String: Any] else { return nil }

        let rankedHandles = (structured["ranked"] as? [String]) ?? []
        let answer = structured["answer"] as? String
        let orderedIDs = rankedHandles.compactMap { handleToID[$0] }
        return ReasonResult(orderedIDs: orderedIDs, answer: answer)
    }

    // MARK: helpers

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func dayString(_ d: Date) -> String { dayFormatter.string(from: d) }

    /// Parse the `claude -p --output-format json` envelope. Tolerant of any leading noise lines.
    static func parseEnvelope(_ output: String) -> [String: Any]? {
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        // fallback: the last line that parses as a JSON object
        for line in output.split(separator: "\n").reversed() {
            if let d = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    /// Locate the `claude` binary (PATH from a GUI app can be minimal) and run it with stdin.
    static func runClaude(args: [String], stdin: String, timeoutSec: Int) async -> String? {
        await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["claude"] + args

            var environment = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            let existing = environment["PATH"] ?? ""
            environment["PATH"] = (extra + [existing]).filter { !$0.isEmpty }.joined(separator: ":")
            if let override = environment["CSPOT_CLAUDE_BIN"], !override.isEmpty {
                proc.executableURL = URL(fileURLWithPath: override)
                proc.arguments = args
            }
            proc.environment = environment

            let inPipe = Pipe(), outPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = outPipe
            proc.standardError = Pipe()

            signal(SIGPIPE, SIG_IGN)   // claude may close stdin early; don't let the write crash us
            do { try proc.run() } catch { return nil }

            try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()

            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSec)) {
                if proc.isRunning { proc.terminate() }
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            return text.isEmpty ? nil : text
        }.value
    }
}

/// Coordinates Stage 1 (collect) and optional Stage 2 (reason) per the Branch decision.
public struct SearchEngine: Sendable {
    public let collector: CandidateCollector
    public let reasoner: Reasoner?
    public let stage2Cap: Int

    public init(collector: CandidateCollector, reasoner: Reasoner? = nil, stage2Cap: Int = 40) {
        self.collector = collector
        self.reasoner = reasoner
        self.stage2Cap = stage2Cap
    }

    public func search(_ raw: String, forceStage2: Bool = false) async -> SearchResult {
        let q = ParsedQuery.parse(raw)
        let stage1 = await collector.collect(q)
        let wantStage2 = (stage1.shouldEscalate || forceStage2) && !q.modifiers.contains(.literal)

        guard wantStage2, let reasoner, !stage1.candidates.isEmpty else {
            return SearchResult(query: q, candidates: stage1.candidates,
                                shouldEscalate: stage1.shouldEscalate, escalated: false, answer: nil)
        }

        let capped = Array(stage1.candidates.prefix(stage2Cap))
        guard let result = await reasoner.rank(query: q, candidates: capped) else {
            // degrade to Stage-1
            return SearchResult(query: q, candidates: stage1.candidates,
                                shouldEscalate: stage1.shouldEscalate, escalated: false, answer: nil)
        }

        let reordered = SearchEngine.reorder(stage1.candidates, by: result.orderedIDs)
        return SearchResult(query: q, candidates: reordered,
                            shouldEscalate: true, escalated: true, answer: result.answer)
    }

    /// Reorder `all` so the LLM-ranked ids come first (deduped); unranked items keep original order at the end.
    public static func reorder(_ all: [Candidate], by orderedIDs: [String]) -> [Candidate] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [Candidate] = []
        for id in orderedIDs where !seen.contains(id) {
            if let c = byID[id] { out.append(c); seen.insert(id) }
        }
        for c in all where !seen.contains(c.id) { out.append(c) }
        return out
    }
}

public struct SearchResult: Sendable {
    public let query: ParsedQuery
    public let candidates: [Candidate]
    public let shouldEscalate: Bool
    public let escalated: Bool
    public let answer: String?
}
