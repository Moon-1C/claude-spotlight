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

    /// Kinds that mutate state / send. Opens & drafts (composeMail/replyMail open a draft, never send)
    /// run automatically with a toast.
    static let mutatingKinds: Set<ActionKind> = [
        .createNote, .appendNote, .addCalendarEvent, .addReminder, .sendMessage, .runShortcut,
    ]

    /// Records, sends, OR anything the model flagged destructive must be confirmed.
    public var requiresConfirm: Bool {
        destructive || Action.mutatingKinds.contains(kind)
    }

    /// Build from the decoded `structured_output.action` object (JSON via JSONSerialization).
    public static func from(_ dict: [String: Any]) -> Action? {
        guard let kindStr = dict["kind"] as? String, let kind = ActionKind(rawValue: kindStr) else { return nil }
        // params values are strings per the schema; keep only genuine strings (drop nulls/numbers/arrays).
        let params: [String: String] = (dict["params"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
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
