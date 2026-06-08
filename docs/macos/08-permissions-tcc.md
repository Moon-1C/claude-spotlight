# 08 — Permissions (TCC)

TCC (Transparency, Consent, and Control) is macOS's permission system. The goal
for this app is to require **as few prompts as possible**.

## What we need vs. don't

| Capability             | Needed? | Why                                                   |
| ---------------------- | ------- | ----------------------------------------------------- |
| Network (outbound)     | ✅ yes  | OAuth + Claude API. Granted via entitlement, no prompt |
| Accessibility          | ❌ no   | Hotkey uses `RegisterEventHotKey`, not event taps     |
| Input Monitoring       | ❌ no   | same as above                                         |
| Apple Events / Automation | ❌ no | we don't script other apps (v1)                       |
| Screen Recording       | ❌ no   | no screen capture                                     |
| Files & Folders        | ❌ no   | only Keychain + UserDefaults                          |

> Key win: by using `RegisterEventHotKey`, the app needs **zero** TCC prompts on
> first launch. The only consent UI the user sees is the OAuth login in the
> browser sheet.

## If you ever add Accessibility (future)

Some features (global text-event monitoring, simulating keystrokes, reading the
frontmost app's selection) would need Accessibility. If so:

```swift
import ApplicationServices

func hasAccessibility() -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    return AXIsProcessTrustedWithOptions(opts as CFDictionary)
}
```

- This shows the system prompt and deep-links to System Settings → Privacy &
  Security → Accessibility.
- **Hardened Runtime caveat:** apps requiring Accessibility must be properly
  signed; ad-hoc/dev builds may be revoked when re-signed, forcing the user to
  re-grant. Document this for testers.

## Usage description strings (Info.plist)

Add purpose strings only for permissions you actually request. None are required
for v1's feature set. If you add, e.g., Apple Events later:

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Claude Spotlight needs this to …</string>
```

## First-run UX

Because no TCC prompts fire, first run should go straight to the **login** screen
(OAuth). Don't show a "grant permissions" wall — there's nothing to grant.

## Related

`03-global-hotkey.md` · `05-oauth-auth.md` · `07-entitlements-sandbox.md`
