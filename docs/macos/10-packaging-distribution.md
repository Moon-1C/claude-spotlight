# 10 — Packaging & Distribution

## Build the release `.app`

```bash
xcodebuild -project ClaudeSpotlight.xcodeproj \
  -scheme ClaudeSpotlight \
  -configuration Release \
  -derivedDataPath build \
  clean build
# product at: build/Build/Products/Release/ClaudeSpotlight.app
```

Then sign + notarize + staple per `09-code-signing-notarization.md`.

## Package as `.dmg`

A drag-to-Applications dmg is the standard distribution form.

```bash
# simplest: create-dmg (brew install create-dmg)
create-dmg \
  --volname "Claude Spotlight" \
  --window-size 540 380 \
  --icon "ClaudeSpotlight.app" 140 190 \
  --app-drop-link 400 190 \
  "ClaudeSpotlight.dmg" \
  "build/Build/Products/Release/ClaudeSpotlight.app"
```

Sign + notarize + staple the **dmg** as well, so Gatekeeper passes on the
downloaded file:

```bash
codesign --sign "Developer ID Application: Your Name (TEAMID)" --timestamp ClaudeSpotlight.dmg
xcrun notarytool submit ClaudeSpotlight.dmg --keychain-profile "cs-notary" --wait
xcrun stapler staple ClaudeSpotlight.dmg
```

## Auto-update

Recommended: **Sparkle 2** (SwiftPM). It needs:

- An EdDSA key pair; the **public** key in Info.plist
  (`SUPublicEDKey`), the private key kept secret for signing updates.
- An `appcast.xml` hosted somewhere (GitHub Releases, S3, etc.).
- `SUFeedURL` in Info.plist pointing at the appcast.

`TODO(decide)` whether v1 ships auto-update or manual download only.

## Versioning

- `CFBundleShortVersionString` = marketing version (e.g. `1.0.0`).
- `CFBundleVersion` = monotonically increasing build number (CI build #).
- Tag releases `v1.0.0`; attach the stapled dmg to the GitHub Release.

## Release checklist

1. [ ] Bump versions.
2. [ ] `xcodebuild` Release.
3. [ ] Sign (Developer ID + hardened runtime).
4. [ ] Notarize + staple the `.app`.
5. [ ] Build `.dmg`, sign + notarize + staple it.
6. [ ] `spctl -a -vvv -t exec` and `stapler validate` both pass.
7. [ ] Smoke test on a clean Mac / fresh user account.
8. [ ] (If Sparkle) update + sign `appcast.xml`.
9. [ ] Create GitHub Release, upload dmg.

## Related

`09-code-signing-notarization.md` · `11-testing.md`
