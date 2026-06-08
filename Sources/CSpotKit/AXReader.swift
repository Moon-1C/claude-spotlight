import Foundation
import AppKit
import ApplicationServices

/// What the Accessibility API can read from the frontmost app — selected text, the focused field's
/// value, and the focused window title. The AX C-API works the moment the responsible process
/// (our signed .app) is trusted in System Settings ▸ Privacy ▸ Accessibility.
public struct AXSnapshot: Codable, Sendable {
    public var role: String?
    public var selectedText: String?
    public var focusedValue: String?
    public var windowTitle: String?
}

public enum AXReader {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the one-time system prompt (only shows once per app identity).
    public static func promptForTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Read the focused element of the app with `pid`. Returns nil if not trusted.
    public static func snapshot(pid: pid_t, selCap: Int = 4000, valueCap: Int = 8000) -> AXSnapshot? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)   // never freeze panel-open on a wedged app

        var snap = AXSnapshot()
        if let focused = element(app, kAXFocusedUIElementAttribute) {
            snap.role = string(focused, kAXRoleAttribute)
            snap.selectedText = string(focused, kAXSelectedTextAttribute).map { String($0.prefix(selCap)) }
            snap.focusedValue = string(focused, kAXValueAttribute).map { String($0.prefix(valueCap)) }
        }
        if let win = element(app, kAXFocusedWindowAttribute) {
            snap.windowTitle = string(win, kAXTitleAttribute)
        }
        return snap
    }

    public static func snapshotForFrontmost() -> AXSnapshot? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return snapshot(pid: pid)
    }

    // MARK: AX helpers

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        if let s = value as? String, !s.isEmpty { return s }
        return nil
    }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success, let v = value else { return nil }
        guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
}
