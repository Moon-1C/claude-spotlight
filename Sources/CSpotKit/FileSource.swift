import Foundation

/// Stage-1 file collector: spawns `mdfind` (Spotlight index) with `-attr` so each result is
/// self-describing (path + modification date + content type + display name in one process call).
public struct FileSource: CandidateSource {
    public let name = "file"
    /// When false, skips the broad/slow `kMDItemTextContent` flavor — used by the live UI for snappy
    /// name-only search; the CLI keeps it true for completeness.
    public let includeContent: Bool
    public let dirs: [String]

    public init(includeContent: Bool = true, dirs: [String]? = nil) {
        self.includeContent = includeContent
        if let dirs, !dirs.isEmpty { self.dirs = dirs } else { self.dirs = Self.tierADirs() }
    }

    /// Paths whose presence anywhere means the result is noise — applied even at Tier A.
    /// (Verified on this Mac: scoped mdfind still returns venv/site-packages/caches junk.)
    static let excludeContains = [
        "/Library/", "/Caches/", "/Cache/", "/CEF/", "/node_modules/", "/.git/",
        "/DerivedData/", "/Application Support/", "/venv/", "/site-packages/",
        "/__pycache__/", "/.build/", "/.",
    ]
    static let excludeSuffix = [".app/", ".pyc", ".lock"]

    static func isExcluded(_ path: String) -> Bool {
        if excludeContains.contains(where: path.contains) { return true }
        if excludeSuffix.contains(where: path.hasSuffix) { return true }
        if path.contains(".app/") { return true }
        return false
    }

    static let attrKeys = ["kMDItemContentModificationDate", "kMDItemContentType", "kMDItemDisplayName"]

    /// High-signal directories (Tier A). Tier B (home-wide) is deferred per the roadmap.
    public static func tierADirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let names = ["Desktop", "Documents", "Downloads", "Pictures", "Movies"]
        return names.map { "\(home)/\($0)" }.filter { FileManager.default.fileExists(atPath: $0) }
    }

    public func collect(_ q: ParsedQuery) async -> [Candidate] {
        var onlyin: [String] = []
        for d in dirs { onlyin += ["-onlyin", d] }
        var attrs: [String] = []
        for k in Self.attrKeys { attrs += ["-attr", k] }

        // Search on content-bearing KEYWORDS (stopwords removed) so natural-language queries like
        // "the report I worked on recently" still collect candidates instead of ANDing every filler word.
        let terms = q.keywords

        // Flavor selection:
        //  - empty / recent: → recency only
        //  - natural-language: breadth — OR over keywords (name + content) PLUS recent files, so Stage 2
        //    has material to rank (NL queries are exactly the ones that escalate).
        //  - lexical: precision — AND over keywords (name + content).
        // Per-flavor timeout: name/recency cheap; content (kMDItemTextContent) is broad/slow → longer leash.
        var flavors: [(predicate: String, kind: MatchKind, timeoutMs: Int)] = []
        if terms.isEmpty || q.modifiers.contains(.recent) {
            flavors.append((Self.recentPredicate(), .recent, 1500))
        } else if q.isNaturalLanguage {
            flavors.append((Self.namePredicate(terms, conjunction: " || "), .nameFuzzy, 1500))
            if includeContent {
                flavors.append((Self.contentPredicate(terms, conjunction: " || "), .content, 3000))
            }
            flavors.append((Self.recentPredicate(), .recent, 1500))
        } else {
            flavors.append((Self.namePredicate(terms, conjunction: " && "), .nameFuzzy, 1500))
            if includeContent {
                flavors.append((Self.contentPredicate(terms, conjunction: " && "), .content, 3000))
            }
        }

        return await withTaskGroup(of: [Candidate].self) { group in
            for f in flavors {
                let args = onlyin + attrs + [f.predicate]
                let kind = f.kind
                let timeout = f.timeoutMs
                group.addTask {
                    let lines = await Task.detached {
                        runMdfind(args, timeoutMs: timeout, maxLines: 200)
                    }.value
                    return lines.compactMap { Self.makeCandidate(from: $0, kind: kind) }
                }
            }
            var acc: [Candidate] = []
            for await partial in group { acc += partial }
            return acc
        }
    }

    // MARK: predicates

    static func clean(_ token: String) -> String {
        token.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "")
    }

    static func namePredicate(_ tokens: [String], conjunction: String = " && ") -> String {
        tokens.map { "(kMDItemDisplayName == \"*\(clean($0))*\"cd)" }.joined(separator: conjunction)
    }

    static func contentPredicate(_ tokens: [String], conjunction: String = " && ") -> String {
        tokens.map { "(kMDItemTextContent == \"*\(clean($0))*\"cd)" }.joined(separator: conjunction)
    }

    static func recentPredicate() -> String {
        "kMDItemContentModificationDate >= $time.now(-604800)"
    }

    // MARK: parsing

    /// `-attr` output is SPACE-delimited (verified on this Mac): `<path>   <key> = <value>   <key> = <value>`.
    /// Paths and values can contain spaces, so we anchor on the known attribute keys rather than splitting.
    static func parseAttrLine(_ line: String, keys: [String]) -> (path: String, attrs: [String: String]) {
        var found: [(key: String, range: Range<String.Index>)] = []
        for k in keys {
            if let r = line.range(of: k) { found.append((k, r)) }
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound }
        guard let first = found.first else {
            return (line.trimmingCharacters(in: .whitespaces), [:])
        }
        let path = String(line[line.startIndex..<first.range.lowerBound])
            .trimmingCharacters(in: .whitespaces)

        var attrs: [String: String] = [:]
        for (i, item) in found.enumerated() {
            let valStart = item.range.upperBound
            let valEnd = (i + 1 < found.count) ? found[i + 1].range.lowerBound : line.endIndex
            var v = String(line[valStart..<valEnd])
            if let eq = v.range(of: "=") { v = String(v[eq.upperBound...]) }
            v = v.trimmingCharacters(in: .whitespaces)
            if v != "(null)" && !v.isEmpty { attrs[item.key] = v }
        }
        return (path, attrs)
    }

    static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"   // e.g. 2026-05-21 07:59:03 +0000
        return f
    }()

    static func makeCandidate(from line: String, kind: MatchKind) -> Candidate? {
        let (path, attrs) = parseAttrLine(line, keys: attrKeys)
        guard !path.isEmpty, path.hasPrefix("/") else { return nil }
        if isExcluded(path) { return nil }

        let url = URL(fileURLWithPath: path)
        let display = attrs["kMDItemDisplayName"] ?? url.lastPathComponent
        let title = url.deletingPathExtension().lastPathComponent.isEmpty
            ? display
            : url.deletingPathExtension().lastPathComponent

        var c = Candidate(id: "file:\(path)", source: .file, title: title, matchKind: kind)
        c.path = path
        c.uri = url.absoluteString
        c.subtitle = abbreviatedParent(of: path)
        if let ds = attrs["kMDItemContentModificationDate"] { c.modifiedAt = dateParser.date(from: ds) }
        if let ct = attrs["kMDItemContentType"] { c.meta["contentType"] = ct }
        return c
    }

    static func abbreviatedParent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}

/// Runs mdfind with a hard watchdog that terminates the process on timeout. Synchronous;
/// intended to be called from a detached task so the cooperative pool isn't blocked.
func runMdfind(_ args: [String], timeoutMs: Int, maxLines: Int) -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()

    do { try p.run() } catch { return [] }

    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
        if p.isRunning { p.terminate() }
    }

    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()

    let text = String(decoding: data, as: UTF8.self)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    if lines.count > maxLines { lines = Array(lines.prefix(maxLines)) }
    return lines
}
