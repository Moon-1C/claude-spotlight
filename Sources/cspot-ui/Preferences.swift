import Foundation
import CSpotKit

/// User preferences, backed by UserDefaults (shared with the SwiftUI @AppStorage keys in SettingsView).
/// Unbundled apps get a defaults domain keyed by the executable name — fine for a single tool.
enum Prefs {
    static let modelKey = "cspot.model"
    static let searchContentKey = "cspot.searchContent"
    static let includeCalendarKey = "cspot.includeCalendar"
    static let extraDirsKey = "cspot.extraDirs"   // newline-joined absolute paths

    static var model: String {
        let m = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return m.isEmpty ? "sonnet" : m
    }
    static var searchContent: Bool { UserDefaults.standard.bool(forKey: searchContentKey) }
    static var includeCalendar: Bool { UserDefaults.standard.bool(forKey: includeCalendarKey) }

    static var extraDirs: [String] {
        (UserDefaults.standard.string(forKey: extraDirsKey) ?? "")
            .split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty }
    }

    /// All search directories: the built-in Tier-A set plus any user-added folders (deduped, existing).
    static var searchDirs: [String] {
        var seen = Set<String>()
        return (FileSource.tierADirs() + extraDirs)
            .filter { FileManager.default.fileExists(atPath: $0) }
            .filter { seen.insert($0).inserted }
    }

    /// Build the live Stage-1 sources from current prefs. (Live search stays name-only unless the
    /// user opts into content search, which is slower.)
    static func liveSources() -> [CandidateSource] {
        var sources: [CandidateSource] = [
            AppSource(),
            FileSource(includeContent: searchContent, dirs: searchDirs),
        ]
        if includeCalendar { sources.append(CalendarSource()) }
        return sources
    }

    static func reasoner() -> Reasoner { ClaudeCLIReasoner(model: model) }
}
