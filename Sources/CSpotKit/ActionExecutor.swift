import Foundation
import AppKit
import EventKit

/// Performs an Action. The hard rule (DESIGN §9): mutating actions require explicit confirmation;
/// `confirmed:true` is passed from exactly one place in the UI (the confirm band).
public struct ActionExecutor: Sendable {
    public init() {}

    public func perform(_ a: Action, confirmed: Bool) async -> Outcome {
        if a.requiresConfirm && !confirmed { return .needsConfirm }   // WRITE = CONFIRM
        switch a.kind {
        case .openURL:    return await openURL(a.params)
        case .revealFile: return await revealFile(a.params)
        case .copyText:   return await copyText(a.params)
        case .addReminder:      return await addReminder(a.params)
        case .addCalendarEvent: return await addEvent(a.params)
        case .createNote: return createNote(a.params)
        case .appendNote: return appendNote(a.params)
        case .composeMail, .replyMail: return composeMail(a.params)   // opens a draft; never auto-sends
        case .sendMessage: return sendMessage(a.params)
        case .runShortcut: return runShortcut(a.params)
        }
    }

    // MARK: non-mutating (no TCC)

    private func openURL(_ p: [String: String]) async -> Outcome {
        guard var s = p["url"], !s.isEmpty else { return .failure("no url") }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return .failure("bad url") }
        await MainActor.run { NSWorkspace.shared.open(url) }
        return .ok("Opened \(s)")
    }
    private func revealFile(_ p: [String: String]) async -> Outcome {
        guard let path = p["path"], !path.isEmpty else { return .failure("no path") }
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        return .ok("Revealed in Finder")
    }
    private func copyText(_ p: [String: String]) async -> Outcome {
        let t = p["text"] ?? ""
        await MainActor.run { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
        return .ok("Copied to clipboard")
    }

    // MARK: EventKit

    private func addReminder(_ p: [String: String]) async -> Outcome {
        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: break
        case .notDetermined:
            let ok = (try? await store.requestFullAccessToReminders()) ?? false
            if !ok { return .failure("Reminders access not granted") }
        default: return .failure("Reminders access denied — System Settings ▸ Privacy ▸ Reminders")
        }
        let r = EKReminder(eventStore: store)
        r.title = p["title"] ?? "Reminder"
        r.calendar = store.defaultCalendarForNewReminders()
        if let due = p["due"], !due.isEmpty {
            guard let d = Self.parseDate(due) else { return .failure("couldn't parse due date: \(due)") }
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            r.addAlarm(EKAlarm(absoluteDate: d))
        }
        do { try store.save(r, commit: true); return .ok("Reminder added: \(r.title ?? "")") }
        catch { return .failure(error.localizedDescription) }
    }

    private func addEvent(_ p: [String: String]) async -> Outcome {
        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: break
        case .notDetermined:
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            if !ok { return .failure("Calendar access not granted") }
        default: return .failure("Calendar access denied — System Settings ▸ Privacy ▸ Calendars")
        }
        guard let title = p["title"], let startS = p["start"], let start = Self.parseDate(startS) else {
            return .failure("need title + start")
        }
        let end = p["end"].flatMap(Self.parseDate) ?? start.addingTimeInterval(3600)
        let ev = EKEvent(eventStore: store)
        ev.title = title; ev.startDate = start; ev.endDate = end
        ev.location = p["location"]; ev.notes = p["notes"]
        ev.calendar = store.defaultCalendarForNewEvents
        do { try store.save(ev, span: .thisEvent, commit: true); return .ok("Event added: \(title)") }
        catch { return .failure(error.localizedDescription) }
    }

    // MARK: AppleScript-backed

    private func createNote(_ p: [String: String]) -> Outcome {
        let title = esc(p["title"] ?? "Note")
        let body = esc(htmlBody(p["body"] ?? ""))
        let script = "tell application \"Notes\" to make new note at folder \"Notes\" with properties {name:\"\(title)\", body:\"<div>\(body)</div>\"}"
        return run(script, ok: "Note created: \(p["title"] ?? "")")
    }
    private func appendNote(_ p: [String: String]) -> Outcome {
        let title = esc(p["title"] ?? "")
        let body = esc(htmlBody(p["body"] ?? ""))
        // Create the note if none with that name exists (the model picked the title), else append.
        let script = """
        tell application "Notes"
        if (count of (notes whose name is "\(title)")) is 0 then
        make new note at folder "Notes" with properties {name:"\(title)", body:"<div>\(body)</div>"}
        else
        set n to first note whose name is "\(title)"
        set body of n to (body of n) & "<br>\(body)"
        end if
        end tell
        """
        return run(script, ok: "Saved to note: \(p["title"] ?? "")")
    }
    private func composeMail(_ p: [String: String]) -> Outcome {
        let subj = esc(p["subject"] ?? "")
        let body = esc(p["body"] ?? "")
        let to = esc(p["to"] ?? "")
        var script = "tell application \"Mail\"\nset m to make new outgoing message with properties {subject:\"\(subj)\", content:\"\(body)\", visible:true}\n"
        if !to.isEmpty { script += "tell m to make new to recipient at end of to recipients with properties {address:\"\(to)\"}\n" }
        script += "activate\nend tell"
        return run(script, ok: "Mail draft opened")   // never auto-sends — user reviews & sends in Mail
    }
    private func sendMessage(_ p: [String: String]) -> Outcome {
        guard let to = p["to"], !to.isEmpty else { return .failure("no recipient") }
        let text = esc(p["text"] ?? "")
        let script = "tell application \"Messages\"\nset svc to 1st service whose service type = iMessage\nsend \"\(text)\" to participant \"\(esc(to))\" of svc\nend tell"
        return run(script, ok: "Message sent to \(to)")
    }
    private func runShortcut(_ p: [String: String]) -> Outcome {
        guard let name = p["name"], !name.isEmpty else { return .failure("no shortcut name") }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        proc.arguments = ["run", name]
        if let input = p["input"] { proc.arguments?.append(contentsOf: ["-i", input]) }
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return .failure("\(error)") }
        let watchdog = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)
        proc.waitUntilExit()
        watchdog.cancel()
        return proc.terminationStatus == 0 ? .ok("Ran shortcut: \(name)") : .failure("shortcut exit \(proc.terminationStatus)")
    }

    // MARK: helpers

    static let isoFormatter = ISO8601DateFormatter()

    /// Lenient: accepts ISO-8601 with zone (Z/offset) AND the zone-less local forms the model emits.
    static func parseDate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
                    "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = .current
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    private func htmlBody(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// osascript runner that treats stderr / nonzero exit as failure (so the UI shows real errors).
    private func run(_ script: String, ok: String) -> Outcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice   // unused — discard so a large echo can't deadlock
        p.standardError = errPipe
        do { try p.run() } catch { return .failure("spawn: \(error)") }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        let e = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        p.waitUntilExit()
        watchdog.cancel()
        if p.terminationStatus != 0 || !e.isEmpty {
            if e.contains("-1743") { return .failure("Automation not allowed — grant it in System Settings ▸ Privacy ▸ Automation") }
            return .failure(e.isEmpty ? "osascript exit \(p.terminationStatus)" : e)
        }
        return .ok(ok)
    }
}
