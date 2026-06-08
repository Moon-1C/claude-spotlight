# 07 — Entitlements & App Sandbox

## Decision: Sandbox on or off?

| Option            | Pros                                   | Cons                                        |
| ----------------- | -------------------------------------- | ------------------------------------------- |
| **Sandbox ON**    | Required for Mac App Store; safer      | Some constraints; must declare each capability |
| **Sandbox OFF**   | Fewer surprises for a launcher utility | Cannot ship on MAS                          |

For a Developer-ID–distributed launcher (our v1, see `10-`), **either works**.
The global hotkey via `RegisterEventHotKey` works with the sandbox **on**.
Recommendation: **Sandbox ON** with the minimal set below, for hardened-runtime
+ notarization friendliness.

## Minimal entitlements (`ClaudeSpotlight.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- App Sandbox -->
  <key>com.apple.security.app-sandbox</key>
  <true/>

  <!-- Outbound network for OAuth + Claude API -->
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
```

That's the whole list for v1:
- `app-sandbox` — turn the sandbox on.
- `network.client` — needed for `URLSession` calls to Anthropic.

## Hardened Runtime entitlements

Notarization requires the **Hardened Runtime** (set in target → Signing &
Capabilities). It is separate from the sandbox. With pure Swift you typically need
**none** of the hardened-runtime exceptions. Only add things like
`com.apple.security.cs.allow-jit` if a dependency requires it (ours shouldn't).

## What we deliberately do NOT request

- ❌ Accessibility / input monitoring — not needed; `RegisterEventHotKey` doesn't
  require it (see `03-`). Avoiding it means no scary TCC prompt.
- ❌ File access entitlements — the app reads/writes only Keychain + UserDefaults.
- ❌ Keychain access groups — single app, no sharing (see `06-`).

## ASWebAuthenticationSession + sandbox

`ASWebAuthenticationSession` works under the sandbox (it's a system service). The
OAuth redirect comes back via the custom URL scheme; no extra entitlement needed
beyond `network.client`.

## Verifying

```bash
codesign -d --entitlements :- /path/to/ClaudeSpotlight.app
```

confirms the embedded entitlements after signing.

## Related

`06-keychain-storage.md` · `08-permissions-tcc.md` · `09-code-signing-notarization.md`
