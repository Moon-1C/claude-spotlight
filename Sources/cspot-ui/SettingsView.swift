import SwiftUI
import AppKit
import CSpotKit

struct SettingsView: View {
    @AppStorage(Prefs.modelKey) private var model = "sonnet"
    @AppStorage(Prefs.searchContentKey) private var searchContent = false
    @AppStorage(Prefs.includeCalendarKey) private var includeCalendar = false
    @AppStorage(Prefs.extraDirsKey) private var extraDirs = ""

    private var extraList: [String] {
        extraDirs.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section("Reasoning — ⌘↩ ask Claude") {
                Picker("Model", selection: $model) {
                    Text("Sonnet — balanced").tag("sonnet")
                    Text("Haiku — fastest").tag("haiku")
                    Text("Opus — best").tag("opus")
                }
                Text("Stage 2 runs your local Claude Code (claude -p) — uses your subscription, no API key.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Search") {
                Toggle("Search inside file contents (slower)", isOn: $searchContent)
                Toggle("Include Calendar events", isOn: $includeCalendar)
                if includeCalendar {
                    Text("Requires granting Calendar access to the app (full version).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Search folders") {
                ForEach(FileSource.tierADirs(), id: \.self) { dir in
                    Label(abbreviate(dir), systemImage: "folder")
                        .foregroundStyle(.secondary)
                }
                ForEach(extraList, id: \.self) { dir in
                    HStack {
                        Label(abbreviate(dir), systemImage: "folder.badge.plus")
                        Spacer()
                        Button(role: .destructive) { removeDir(dir) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") { addFolder() }
            }

            Section("Hotkey") {
                LabeledContent("Show launcher", value: "⌥ Space")
                Text("Rebinding arrives with the packaged app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func removeDir(_ dir: String) {
        extraDirs = extraList.filter { $0 != dir }.joined(separator: "\n")
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            var list = extraList
            for url in panel.urls where !list.contains(url.path) { list.append(url.path) }
            extraDirs = list.joined(separator: "\n")
        }
    }
}

/// Hosts the Settings window for the menu-bar accessory app.
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            w.title = "claude-spotlight — Settings"
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func snapshot(to path: String) -> Bool {
        guard let view = window?.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        return SnapshotUtil.writePNG(of: view, to: path)
    }
}

/// Renders an NSView's own content to a PNG. Works without Screen Recording TCC because it draws
/// the app's own view hierarchy rather than capturing the display.
enum SnapshotUtil {
    @discardableResult
    static func writePNG(of view: NSView, to path: String) -> Bool {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
}
