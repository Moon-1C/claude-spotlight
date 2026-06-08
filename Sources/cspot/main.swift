import Foundation
import CSpotKit

// Phase-0 Stage-1 harness:  swift run cspot "<query>"
// Prints a ranked candidate JSON for files + calendar, plus the Branch escalate decision.
// No auth, no network, no LLM, no UI.

struct CLIOutput: Codable {
    let query: String
    let modifiers: [String]
    let shouldEscalate: Bool
    let elapsedMs: Int
    let count: Int
    let candidates: [Candidate]
}

let rawQuery = Array(CommandLine.arguments.dropFirst()).joined(separator: " ")
let parsed = ParsedQuery.parse(rawQuery)

let collector = CandidateCollector(sources: [FileSource(), CalendarSource()])

let started = Date()
let result = await collector.collect(parsed)
let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

let output = CLIOutput(
    query: parsed.raw,
    modifiers: parsed.modifiers.map(\.rawValue).sorted(),
    shouldEscalate: result.shouldEscalate,
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
