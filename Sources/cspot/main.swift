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

// `cspot --ax` → print what Accessibility can read from the frontmost app (or report not-trusted).
if args.contains("--ax") {
    if AXReader.isTrusted, let snap = AXReader.snapshotForFrontmost() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: (try? enc.encode(snap)) ?? Data("{}".utf8), as: UTF8.self))
    } else {
        print("{ \"trusted\": false }")
        FileHandle.standardError.write(Data("[cspot] not trusted for Accessibility — grant the app in System Settings ▸ Privacy ▸ Accessibility\n".utf8))
    }
    exit(0)
}

// `cspot --context [--deep]` → print the current running-app context and exit.
if args.contains("--context") {
    let ctx = await ContextCapture.capture(deep: args.contains("--deep"))
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let ctx, let data = try? enc.encode(ctx) {
        print(String(decoding: data, as: UTF8.self))
    } else {
        print("{}")
    }
    exit(0)
}

// `cspot --propose "<text>"` → print Stage-2's proposed Action (or mode=search). NEVER executes.
if let pi = args.firstIndex(of: "--propose") {
    args.remove(at: pi)
    let text = args.joined(separator: " ")
    let ctx = await ContextCapture.capture(deep: true)
    let result = await ClaudeCLIReasoner().rank(query: ParsedQuery.parse(text), candidates: [], context: ctx)
    if let action = result?.action {
        print("mode=action")
        print("  kind:        \(action.kind.rawValue)")
        print("  preview:     \(action.preview)")
        print("  requiresConfirm: \(action.requiresConfirm)  destructive: \(action.destructive)")
        print("  params:      \(action.params)")
    } else {
        print("mode=search  answer: \(result?.answer ?? "-")")
    }
    exit(0)
}

var useAI = false
if let i = args.firstIndex(of: "--ai") { useAI = true; args.remove(at: i) }

var model: String? = "sonnet"
if let i = args.firstIndex(of: "--model"), i + 1 < args.count {
    model = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

let rawQuery = args.joined(separator: " ")
let parsed = ParsedQuery.parse(rawQuery)

let collector = CandidateCollector(sources: [AppSource(), FileSource(), CalendarSource()])
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
