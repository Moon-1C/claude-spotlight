import Foundation
import CSpotKit

// Phase-0/1 harness:  swift run cspot [--ai] [--model <m>] "<query>"
//   default        → Stage 1 only (instant local collection + ranking + branch decision)
//   --ai           → also run Stage 2 (claude -p reasoning) to re-rank + synthesize an answer
// No GUI. Prints JSON.

struct CLIOutput: Codable {
    let query: String
    let modifiers: [String]
    let shouldEscalate: Bool
    let escalated: Bool
    let answer: String?
    let elapsedMs: Int
    let count: Int
    let candidates: [Candidate]
}

var args = Array(CommandLine.arguments.dropFirst())

var useAI = false
if let i = args.firstIndex(of: "--ai") { useAI = true; args.remove(at: i) }

var model: String? = "sonnet"
if let i = args.firstIndex(of: "--model"), i + 1 < args.count {
    model = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

let rawQuery = args.joined(separator: " ")
let parsed = ParsedQuery.parse(rawQuery)

let collector = CandidateCollector(sources: [FileSource(), CalendarSource()])
let engine = SearchEngine(collector: collector, reasoner: useAI ? ClaudeCLIReasoner(model: model) : nil)

let started = Date()
let result = await engine.search(rawQuery, forceStage2: useAI)
let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

let output = CLIOutput(
    query: parsed.raw,
    modifiers: parsed.modifiers.map(\.rawValue).sorted(),
    shouldEscalate: result.shouldEscalate,
    escalated: result.escalated,
    answer: result.answer,
    elapsedMs: elapsedMs,
    count: result.candidates.count,
    candidates: result.candidates
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
encoder.dateEncodingStrategy = .iso8601

do {
    let data = try encoder.encode(output)
    print(String(decoding: data, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("[cspot] encode error: \(error)\n".utf8))
    exit(1)
}
