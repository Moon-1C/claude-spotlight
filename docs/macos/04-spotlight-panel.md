# 04 — Spotlight Panel

The command bar is a borderless, floating panel that appears centered-top on the
active screen, accepts text without stealing full app focus awkwardly, and
dismisses on Esc or focus loss.

## Why `NSPanel`, not a `Window`

`NSPanel` with the **nonactivating** style lets the panel receive keyboard input
while disturbing the previously-active app as little as possible — the Spotlight
behavior. A regular window would fully activate the app and is heavier.

```swift
final class SpotlightPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating                      // above normal windows
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
    // Allow a borderless panel to become key so the text field gets focus:
    override var canBecomeKey: Bool { true }
}
```

## Controller: show / hide / position

```swift
final class PanelController {
    private lazy var panel: SpotlightPanel = {
        let p = SpotlightPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 88))
        p.contentView = NSHostingView(rootView: CommandView())
        return p
    }()

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        positionTopCenter()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

    private func positionTopCenter() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height - vf.height * 0.18   // ~upper third
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

## Dismiss behavior

- **Esc:** handle in the SwiftUI view (`.onExitCommand { controller.hide() }`) or
  override `cancelOperation(_:)` on the panel.
- **Click outside / focus loss:** observe `NSWindow.didResignKeyNotification` for
  the panel and call `hide()`.

## SwiftUI content (sketch)

```swift
struct CommandView: View {
    @State private var query = ""
    @StateObject private var chat = ChatViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Ask Claude…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($focused)
                .onSubmit { chat.send(query) }
                .padding()
            if !chat.messages.isEmpty {
                ResponseView(messages: chat.messages)   // scrolls, grows panel
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { focused = true }
    }
}
```

## Visuals

- Use `.ultraThinMaterial` for the blurred Spotlight look.
- Rounded corners (~14pt), subtle shadow (panel `hasShadow`).
- Resize the panel height as the response grows (animate `setFrame`).

## Related

`03-global-hotkey.md` · `12-claude-api-integration.md`
