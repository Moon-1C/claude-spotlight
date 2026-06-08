import AppKit

// Raycast-style launcher, run unbundled via SwiftPM (no full Xcode / .app bundle needed).
// `swift run cspot-ui` → menu-bar icon + ⌥Space toggles a floating search panel.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon (menu-bar accessory)
app.run()
