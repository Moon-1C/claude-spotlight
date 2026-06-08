# 03 — Global Hotkey

The app is summoned by a system-wide shortcut (default **⌥Space**), working even
when another app is frontmost.

## Approach

Use the Carbon **`RegisterEventHotKey`** API. It is the most reliable way to get a
true global hotkey that does **not** require Accessibility permission. (Listening
to global key events via `NSEvent.addGlobalMonitorForEvents` *does* require
Accessibility and is less precise — avoid it for the main trigger.)

> Carbon is old but `RegisterEventHotKey` is still fully supported and is what
> most launchers (Alfred-style) use. No TCC prompt needed.

## Minimal wrapper

```swift
import Carbon.HIToolbox

final class HotkeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) { self.onFire = onFire }

    func register(keyCode: UInt32 = UInt32(kVK_Space),
                  modifiers: UInt32 = UInt32(optionKey)) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            mgr.onFire()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let id = EventHotKeyID(signature: OSType(0x434C5350 /* 'CLSP' */), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }
}
```

## Modifier constants

Carbon uses its own masks: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
Combine with bitwise OR, e.g. `UInt32(optionKey | cmdKey)`.

## User-configurable shortcut

For v1 a fixed default is fine. To let users rebind:

- Store the `keyCode` + `modifiers` in `UserDefaults` (`Preferences`).
- Re-`register()` after `unregister()` when changed.
- For a nice recorder UI, consider the `KeyboardShortcuts` SwiftPM package
  (sindresorhus) instead of hand-rolling — it wraps the Carbon dance and gives a
  SwiftUI recorder view. `TODO(decide)` whether to add the dependency.

## Conflicts

- ⌥Space is usually free; ⌘Space is Spotlight (avoid as default).
- If `RegisterEventHotKey` returns a non-`noErr` status, the combo is taken —
  surface a message and let the user pick another.

## Related

`02-app-lifecycle-menubar.md` · `08-permissions-tcc.md`
