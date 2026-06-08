# 02 — App Lifecycle & Menu Bar

## Accessory app (no Dock icon)

The app should not appear in the Dock or app switcher — it lives in the menu bar.

**Info.plist:**

```xml
<key>LSUIElement</key>
<true/>
```

This makes the app run as `NSApplication.ActivationPolicy.accessory`. You can also
set it programmatically if you need to toggle (e.g., to show a real Settings
window with Dock presence):

```swift
NSApp.setActivationPolicy(.accessory)
```

## Entry point

SwiftUI `App` + an `NSApplicationDelegate` adapter so we get full AppKit lifecycle
control (status item, panel, hotkey).

```swift
@main
struct ClaudeSpotlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // No WindowGroup — UI is the menu bar + NSPanel.
        Settings { SettingsView() }   // gives a standard Settings window
    }
}
```

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var hotkey: HotkeyManager!
    private var panel: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        panel   = PanelController()
        hotkey  = HotkeyManager { [weak self] in self?.panel.toggle() }
        hotkey.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
    }
}
```

## Menu bar item

```swift
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: .variableLength)

    init() {
        item.button?.image = NSImage(systemSymbolName: "sparkle",
                                     accessibilityDescription: "Claude Spotlight")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Claude Spotlight  (⌥Space)",
                     action: #selector(open), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
    // @objc handlers omitted
}
```

## Launch at login

Use `SMAppService` (macOS 13+):

```swift
import ServiceManagement
try? SMAppService.mainApp.register()    // enable
try? SMAppService.mainApp.unregister()  // disable
```

Expose this as a toggle in Settings.

## Lifecycle notes

- The app keeps running with no windows open — that's expected for an accessory.
- `applicationShouldTerminateAfterLastWindowClosed` → return `false` (default for
  accessory is fine).
- Clean up the hotkey on terminate (see above) to avoid a stale Carbon handler.

## Related

`03-global-hotkey.md` · `04-spotlight-panel.md`
