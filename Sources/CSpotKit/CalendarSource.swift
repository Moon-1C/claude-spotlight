import Foundation
import EventKit

/// Stage-1 calendar collector: EventKit in-process (no subprocess). Reads a ±2-week window and
/// keeps events whose title/notes/location match every query token (case- & diacritic-insensitive).
///
/// TCC note: from this CLI harness the grant belongs to the terminal/Claude-Code process. The real
/// app (Phase 2) earns its own Calendar grant under its bundle id + signature.
public struct CalendarSource: CandidateSource {
    public let name = "calendar"
    public init() {}

    public func collect(_ q: ParsedQuery) async -> [Candidate] {
        let store = EKEventStore()

        let status = EKEventStore.authorizationStatus(for: .event)
        var granted = false
        switch status {
        case .fullAccess:
            granted = true
        case .notDetermined:
            // Only attempt a request when undetermined. (A request without an Info.plist usage
            // string can hard-trap; on this Mac status is already fullAccess so this won't fire.)
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        default:
            granted = false
        }

        guard granted else {
            FileHandle.standardError.write(
                Data("[cspot] calendar access not granted (status raw=\(status.rawValue)); skipping calendar\n".utf8))
            return []
        }

        let cal = Calendar.current
        let now = Date()
        let start = q.dateHint?.start ?? cal.date(byAdding: .day, value: -1, to: now)!
        let end = q.dateHint?.end ?? cal.date(byAdding: .day, value: 14, to: now)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: pred)

        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let tokens = q.tokens.map { $0.folding(options: opts, locale: nil) }

        return events.compactMap { ev -> Candidate? in
            let hay = [ev.title, ev.notes, ev.location]
                .compactMap { $0 }
                .joined(separator: " ")
                .folding(options: opts, locale: nil)
            let matched = tokens.isEmpty || tokens.allSatisfy { hay.contains($0) }
            guard matched else { return nil }

            var c = Candidate(
                id: "cal:\(ev.eventIdentifier ?? UUID().uuidString)",
                source: .calendar,
                title: ev.title ?? "(untitled event)",
                matchKind: tokens.isEmpty ? .recent : .fieldMatch
            )
            c.subtitle = Self.timeRange(ev)
            c.startAt = ev.startDate
            c.endAt = ev.endDate
            c.snippet = ev.notes.map { String($0.prefix(160)) }
            if let ext = ev.calendarItemExternalIdentifier { c.uri = "x-apple-calevent://\(ext)" }
            c.meta = ["calendar": ev.calendar.title, "allDay": ev.isAllDay ? "true" : "false"]
            return c
        }
    }

    static func timeRange(_ ev: EKEvent) -> String {
        let cal = ev.calendar.title
        guard let s = ev.startDate else { return cal }
        if ev.isAllDay {
            let d = DateFormatter()
            d.dateStyle = .medium
            d.timeStyle = .none
            return "\(d.string(from: s)) (all-day), \(cal)"
        }
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d, HH:mm"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let endStr = ev.endDate.map { "–\(tf.string(from: $0))" } ?? ""
        return "\(df.string(from: s))\(endStr), \(cal)"
    }
}
