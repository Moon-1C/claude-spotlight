import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyManager!
    private var panel: PanelController!
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "claude-spotlight")
            button.image?.isTemplate = true
            button.toolTip = "claude-spotlight — ⌥Space"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open  (⌥Space)", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit claude-spotlight", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu

        hotkey = HotkeyManager { [weak self] in self?.panel.toggle() }
        hotkey.register()

        let demoQuery = Self.argValue("--demo")

        // --snapshot <dir> [--ask]: render panel (+settings) to PNGs and quit. Self-render, no TCC.
        if let dir = Self.argValue("--snapshot") {
            runSnapshots(into: dir, query: demoQuery ?? "the report I worked on", ask: CommandLine.arguments.contains("--ask"))
            return
        }

        if let demoQuery {
            panel.showDemo(query: demoQuery)   // pre-filled launcher for quick checks
        } else {
            panel.show()                       // show once at launch so the UI is immediately visible
        }
    }

    private func runSnapshots(into dir: String, query: String, ask: Bool) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        panel.snapshotPrepare(query: query)   // render without stealing key focus
        // Let the live search populate first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.panel.snapshot(to: "\(dir)/panel.png")
            if ask {
                self.panel.askClaudeNow()   // also capture the Stage-2 answer once it returns
                DispatchQueue.main.asyncAfter(deadline: .now() + 40.0) {
                    self.panel.snapshot(to: "\(dir)/panel-answer.png")
                    self.finishSnapshots(dir: dir)
                }
            } else {
                self.finishSnapshots(dir: dir)
            }
        }
    }

    private func finishSnapshots(dir: String) {
        settings.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.settings.snapshot(to: "\(dir)/settings.png")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    private static func argValue(_ flag: String) -> String? {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: flag), i + 1 < a.count, !a[i + 1].hasPrefix("--") { return a[i + 1] }
        return nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
    }

    @objc private func openPanel() { panel.show() }
    @objc private func openSettings() { settings.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
