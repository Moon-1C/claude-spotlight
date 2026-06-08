import Foundation

/// Stage-1 source for installed applications (the #1 launcher use). Matches on both the localized
/// display name AND the non-localized file name, so an English query finds a localized app
/// (e.g. "calendar" → 캘린더.app / Calendar.app).
public struct AppSource: CandidateSource {
    public let name = "app"
    public init() {}

    static func appDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "\(home)/Applications",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }

    public func collect(_ q: ParsedQuery) async -> [Candidate] {
        let terms = q.keywords
        guard !terms.isEmpty else { return [] }   // never list every app on an empty query

        var args: [String] = []
        for d in Self.appDirs() { args += ["-onlyin", d] }
        args += ["-attr", "kMDItemDisplayName"]

        let conjunction = q.isNaturalLanguage ? " || " : " && "
        let perTerm = terms.map { t -> String in
            let c = FileSource.clean(t)
            return "(kMDItemDisplayName == \"*\(c)*\"cd || kMDItemFSName == \"*\(c)*\"cd)"
        }.joined(separator: conjunction)
        let predicate = "(kMDItemContentTypeTree == 'com.apple.application-bundle') && (\(perTerm))"

        let lines = await Task.detached {
            runMdfind(args + [predicate], timeoutMs: 1200, maxLines: 60)
        }.value

        let lowerTerms = terms.map { $0.lowercased() }
        return lines.compactMap { line -> Candidate? in
            let (path, attrs) = FileSource.parseAttrLine(line, keys: ["kMDItemDisplayName"])
            guard !path.isEmpty, path.hasSuffix(".app") else { return nil }
            let url = URL(fileURLWithPath: path)
            let raw = attrs["kMDItemDisplayName"] ?? url.lastPathComponent
            let title = raw.hasSuffix(".app") ? String(raw.dropLast(4)) : raw

            // Exact name match (display or file name) ranks an app at the top.
            let fileBase = url.deletingPathExtension().lastPathComponent.lowercased()
            let titleLower = title.lowercased()
            let exact = lowerTerms.contains { $0 == titleLower || $0 == fileBase }

            var c = Candidate(id: "app:\(path)", source: .app, title: title,
                              matchKind: exact ? .nameExact : .nameFuzzy)
            c.path = path
            c.uri = url.absoluteString
            c.subtitle = FileSource.abbreviatedParent(of: path)
            c.meta["kind"] = "Application"
            return c
        }
    }
}
