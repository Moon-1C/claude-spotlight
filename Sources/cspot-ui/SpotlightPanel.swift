import AppKit
import SwiftUI

/// Borderless floating panel that can become key (so the text field accepts input) while disturbing
/// the previously-active app as little as possible — the Spotlight behavior.
final class SpotlightPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 100),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows / hides / positions the panel and routes navigation keys (↑ ↓ ⏎ esc) to the view model.
/// All entry points are invoked on the main thread (AppKit delegate / main-dispatched hotkey).
final class PanelController {
    private let viewModel = SearchViewModel()
    private let panel = SpotlightPanel()
    private var keyMonitor: Any?

    init() {
        let hosting = NSHostingController(rootView: CommandView(vm: viewModel))
        hosting.sizingOptions = [.preferredContentSize]   // panel resizes to fit SwiftUI content
        panel.contentViewController = hosting
    }

    func toggle() { panel.isVisible ? hide() : show() }

    /// Show the panel pre-filled with a query (used by `--demo` for screenshots / quick checks).
    func showDemo(query: String) {
        show()
        viewModel.query = query   // triggers the live search via the view's onChange
    }

    /// Snapshot prep: render the panel with a query WITHOUT stealing key focus (so stray keystrokes
    /// can't land in the field) and without installing the nav key-monitor.
    func snapshotPrepare(query: String) {
        viewModel.reset()
        viewModel.query = query
        positionTopThird()
        panel.orderFrontRegardless()   // visible + backed, but not the key window
    }

    /// Ask the view model to run Stage 2 (for snapshots that show the answer banner).
    func askClaudeNow() { viewModel.askClaude() }

    /// Render the panel's own content view to a PNG — no Screen Recording permission needed
    /// (the app draws itself; it does not capture the display).
    @discardableResult
    func snapshot(to path: String) -> Bool {
        guard let view = panel.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        return SnapshotUtil.writePNG(of: view, to: path)
    }

    func show() {
        viewModel.reset()
        positionTopThird()
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func positionTopThird() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height - vf.height * 0.18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125: self.viewModel.moveSelection(1); return nil    // ↓
            case 126: self.viewModel.moveSelection(-1); return nil   // ↑
            case 36, 76:                                             // ⏎ / enter
                if event.modifierFlags.contains(.command) {
                    self.viewModel.askClaude()                       // ⌘↩ → Stage 2 (keep panel open)
                } else {
                    self.viewModel.openSelected()                   // ↩ → open selected
                    self.hide()
                }
                return nil
            case 53:                                                 // esc
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
