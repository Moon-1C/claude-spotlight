# 09 — Code Signing & Notarization

To distribute outside the Mac App Store, the app must be **Developer ID signed**,
built with the **Hardened Runtime**, and **notarized** by Apple, then **stapled**.

## Prerequisites

- Apple Developer Program membership.
- **Developer ID Application** certificate in your login keychain.
- Your **Team ID** — `TODO(verify)`.
- App-specific password or App Store Connect API key for `notarytool`.

## 1. Sign (with hardened runtime)

Xcode does this automatically when the target's signing is set to Developer ID +
"Hardened Runtime" capability is enabled. For CI / manual:

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --entitlements ClaudeSpotlight/Entitlements/ClaudeSpotlight.entitlements \
  --deep \
  build/ClaudeSpotlight.app
```

> Prefer signing nested code first then the app, rather than `--deep`, for complex
> bundles. For a single-binary SwiftUI app `--deep` is usually fine.

Verify:

```bash
codesign --verify --strict --verbose=2 build/ClaudeSpotlight.app
spctl -a -vvv -t exec build/ClaudeSpotlight.app   # Gatekeeper assessment
```

## 2. Notarize

Notarize a zip or dmg of the signed app:

```bash
# store credentials once:
xcrun notarytool store-credentials "cs-notary" \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"

# submit (block until done):
ditto -c -k --keepParent build/ClaudeSpotlight.app build/ClaudeSpotlight.zip
xcrun notarytool submit build/ClaudeSpotlight.zip \
  --keychain-profile "cs-notary" --wait
```

## 3. Staple

```bash
xcrun stapler staple build/ClaudeSpotlight.app
xcrun stapler validate build/ClaudeSpotlight.app
```

Staple the **dmg** too if you ship a dmg (see `10-`).

## Common failures

| Symptom                                   | Cause / fix                                            |
| ----------------------------------------- | ------------------------------------------------------ |
| Notarization "Hardened Runtime missing"   | Enable Hardened Runtime; sign with `--options runtime` |
| "binary is not signed with a valid …"     | Wrong cert (need *Developer ID Application*)            |
| "The signature does not include a secure timestamp" | add `--timestamp`                            |
| Gatekeeper still blocks                    | not stapled, or stale download quarantine — re-staple  |

## CI note

Keep certs/keys out of the repo. In CI, import the cert from a secure secret into
a temporary keychain, and use a notarytool keychain profile or API key. See
`scripts/sign-notarize.sh` (to be written).

## Related

`07-entitlements-sandbox.md` · `10-packaging-distribution.md`
