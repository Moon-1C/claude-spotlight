import Foundation

/// A snapshot of what the user is currently looking at — the running app they had frontmost,
/// plus window/browser/document context. Read via AppleScript Automation (no Accessibility needed;
/// AX-based selected-text comes later via AXReader). `deep` reads add body/selection/Finder paths.
public struct AppContext: Codable, Sendable {
    public var app: String
    public var windowTitle: String?
    public var url: String?
    public var urlTitle: String?
    public var selectionText: String?     // selected text (browser JS selection; later AX)
    public var bodyText: String?          // page innerText / mail body / note / doc text
    public var selectionPaths: [String]?  // Finder selection

    public init(app: String) { self.app = app }

    public var summary: String {
        if let urlTitle, let url { return "\(urlTitle) — \(url)" }
        if let url { return url }
        if let windowTitle { return "\(windowTitle) — \(app)" }
        return app
    }
}

public enum ContextCapture {
    static let chromeFamily: Set<String> = ["Google Chrome", "Chrome", "Arc", "Brave Browser",
                                            "Microsoft Edge", "Chromium", "Vivaldi"]

    /// Capture context for `appName` (or the current frontmost app if nil).
    /// `deep` adds body/selection/Finder reads (each may trigger a per-app Automation prompt).
    public static func capture(appName: String? = nil, deep: Bool = false) async -> AppContext? {
        await Task.detached {
            guard let app = (appName ?? frontmostAppName()), !app.isEmpty else { return nil }
            var ctx = AppContext(app: app)

            // Light: cheap, on every panel open.
            if app == "Safari" {
                if let (u, t) = safariTab() { ctx.url = u; ctx.urlTitle = t; ctx.windowTitle = t }
            } else if chromeFamily.contains(app) {
                if let (u, t) = chromeTab(app: app) { ctx.url = u; ctx.urlTitle = t; ctx.windowTitle = t }
            } else {
                ctx.windowTitle = frontWindowTitle(app: app)
            }

            if deep { fillDeep(&ctx, app: app) }
            return ctx
        }.value
    }

    // MARK: light readers

    static func frontmostAppName() -> String? {
        runOSA("tell application \"System Events\" to get name of first process whose frontmost is true")
    }
    static func safariTab() -> (String, String)? {
        twoLine("tell application \"Safari\" to get (URL of current tab of front window) "
              + "& linefeed & (name of current tab of front window)")
    }
    static func chromeTab(app: String) -> (String, String)? {
        twoLine("tell application \"\(app)\" to get (URL of active tab of front window) "
              + "& linefeed & (title of active tab of front window)")
    }
    static func frontWindowTitle(app: String) -> String? {
        runOSA("tell application \"\(app)\" to get name of front window")
    }

    // MARK: deep readers

    static func fillDeep(_ ctx: inout AppContext, app: String) {
        if app == "Safari" || chromeFamily.contains(app) {
            if let (text, sel) = browserContent(app: app) {
                ctx.bodyText = text
                if let sel, !sel.isEmpty { ctx.selectionText = sel }
            }
        } else if app == "Finder" {
            ctx.selectionPaths = finderSelection()
        } else if app == "Mail" {
            ctx.bodyText = mailSelected()
        } else if app == "Notes" {
            ctx.bodyText = notesFront().map(stripHTML).map { String($0.prefix(8000)) }
        } else if app == "TextEdit" {
            ctx.bodyText = runOSA("tell application \"TextEdit\" to get text of front document").map { String($0.prefix(8000)) }
        } else if app == "Messages" {
            ctx.bodyText = messagesRecent()
        }
    }

    /// Browser page innerText + selection via JavaScript. Needs "Allow JavaScript from Apple Events"
    /// (per-browser flag, NOT TCC). When OFF (Chrome err 12 / Safari err 8) we degrade to URL+title.
    static func browserContent(app: String) -> (String?, String?)? {
        let js = "(function(){var s=(window.getSelection?window.getSelection().toString():'');"
               + "var t=document.body?document.body.innerText:'';"
               + "return JSON.stringify({sel:s.slice(0,4000),text:t.slice(0,12000)});})()"
        let script: String
        if app == "Safari" {
            script = "tell application \"Safari\" to do JavaScript \"\(js)\" in current tab of front window"
        } else {
            script = "tell application \"\(app)\" to execute active tab of front window javascript \"\(js)\""
        }
        let (out, err) = runOSA2(script)
        if let err, err.contains("(12)") || err.contains("(8)") || err.contains("Allow JavaScript") {
            return nil   // JS-from-Apple-Events disabled → light URL/title already captured
        }
        guard let out, let data = out.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return (j["text"].map(collapseWS), j["sel"])
    }

    static func finderSelection() -> [String]? {
        let script = """
        tell application "Finder"
        set out to ""
        repeat with i in (get selection)
        set out to out & (POSIX path of (i as alias)) & linefeed
        end repeat
        if out is "" then set out to (POSIX path of (target of front window as alias))
        return out
        end tell
        """
        guard let out = runOSA(script) else { return nil }
        let paths = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return paths.isEmpty ? nil : paths
    }

    static func mailSelected() -> String? {
        let script = """
        tell application "Mail"
        set sel to selection
        if (count of sel) = 0 then return ""
        set m to item 1 of sel
        return (sender of m) & linefeed & (subject of m) & linefeed & ((date received of m) as string) & linefeed & "----" & linefeed & (content of m)
        end tell
        """
        return runOSA(script).map { String($0.prefix(8000)) }
    }

    static func notesFront() -> String? {
        runOSA("tell application \"Notes\" to return (name of note 1) & linefeed & (body of note 1)")
    }

    static func messagesRecent() -> String? {
        runOSA("tell application \"Messages\" to return (text of (messages of (first chat)))")
            .map { String($0.prefix(4000)) }
    }

    // MARK: helpers

    static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
         .replacingOccurrences(of: "&nbsp;", with: " ")
         .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func collapseWS(_ s: String) -> String {
        s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
         .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func twoLine(_ script: String) -> (String, String)? {
        guard let out = runOSA(script) else { return nil }
        let parts = out.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let url = parts.first, !url.isEmpty else { return nil }
        return (url, parts.count > 1 ? parts[1] : "")
    }

    static func runOSA(_ script: String) -> String? {
        runOSA2(script).out
    }

    /// osascript runner that also surfaces stderr (needed to detect the browser JS-flag-OFF state).
    static func runOSA2(_ script: String) -> (out: String?, err: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (nil, "spawn") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: od, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(decoding: ed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (out.isEmpty ? nil : out, err.isEmpty ? nil : err)
    }
}
