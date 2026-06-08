import Foundation

/// A write/act operation the user can take on their running apps. Stage 2 PROPOSES one; the
/// ActionExecutor performs it only after confirmation (for mutating kinds).
public enum ActionKind: String, Codable, Sendable, CaseIterable {
    case createNote, appendNote, addCalendarEvent, addReminder
    case composeMail, replyMail, sendMessage
    case openURL, revealFile, copyText, runShortcut
}

public struct Action: Codable, Sendable {
    public let kind: ActionKind
    public let params: [String: String]
    public let preview: String
    public let destructive: Bool

    public init(kind: ActionKind, params: [String: String], preview: String, destructive: Bool) {
        self.kind = kind
        self.params = params
        self.preview = preview
        self.destructive = destructive
    }

    /// Reads/opens/drafts run automatically (with a toast); record-creating & sending kinds confirm.
    public var requiresConfirm: Bool {
        switch kind {
        case .openURL, .revealFile, .copyText, .composeMail, .replyMail: return false
        case .createNote, .appendNote, .addCalendarEvent, .addReminder, .sendMessage, .runShortcut: return true
        }
    }

    /// Build from the decoded `structured_output.action` object (JSON via JSONSerialization).
    public static func from(_ dict: [String: Any]) -> Action? {
        guard let kindStr = dict["kind"] as? String, let kind = ActionKind(rawValue: kindStr) else { return nil }
        let params: [String: String] = (dict["params"] as? [String: Any])?
            .reduce(into: [:]) { $0[$1.key] = "\($1.value)" } ?? [:]
        let preview = (dict["preview"] as? String) ?? kind.rawValue
        let destructive = (dict["destructive"] as? Bool) ?? false
        return Action(kind: kind, params: params, preview: preview, destructive: destructive)
    }
}

/// Result of attempting an action.
public enum Outcome: Sendable {
    case ok(String)
    case needsConfirm
    case failure(String)

    public var message: String {
        switch self {
        case .ok(let m): return m
        case .needsConfirm: return "Confirmation required"
        case .failure(let m): return "Failed: \(m)"
        }
    }
    public var succeeded: Bool { if case .ok = self { return true } else { return false } }
}
