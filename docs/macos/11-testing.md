# 11 — Testing Process

How we test claude-spotlight: automated (unit/UI) + a manual checklist. This is
the doc the user asked for first — keep it the source of truth for "is it working."

## Test layers

| Layer        | Tool            | What it covers                                  |
| ------------ | --------------- | ----------------------------------------------- |
| Unit         | XCTest          | PKCE, SSE parsing, token expiry/refresh, models |
| UI           | XCUITest        | panel show/hide, query submit, sign-out         |
| Manual       | checklist below | hotkey, OAuth, Keychain, notarized launch       |

## Running tests

```bash
# all tests
xcodebuild test \
  -project ClaudeSpotlight.xcodeproj \
  -scheme ClaudeSpotlight \
  -destination 'platform=macOS'

# a single test
xcodebuild test ... -only-testing:ClaudeSpotlightTests/PKCETests/testChallengeIsS256
```

## What to unit-test (high value, no network)

- **PKCE:** `challenge(for:)` is the base64url SHA-256 of the verifier; verifier is
  43–128 chars, URL-safe.
- **SSE parser:** splits on `\n\n`, parses `data:` lines, ignores comments/`[DONE]`.
- **Token store:** `expiresAt` math; "needs refresh within 60s" boundary.
- **Keychain:** round-trip set/get/delete (uses the real keychain; gate behind a
  test service name so CI is clean).

### Example

```swift
final class PKCETests: XCTestCase {
    func testChallengeIsDeterministicS256() {
        let v = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: v),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}
```

## Mocking the network

- Inject a `URLProtocol` stub into a custom `URLSession` for `ChatService` and the
  token exchange — assert request shape and decode canned responses, including a
  streamed SSE fixture.
- Never hit the real Claude API in unit tests.

## UI tests (XCUITest)

- Launch app, trigger the panel (UI tests can't fire a true global hotkey easily —
  expose a test hook / menu item that calls `panel.toggle()` so the test can drive
  it), type a query, assert a response view appears (with a stubbed backend via a
  launch argument like `-UITEST_STUB_API 1`).

## Manual test checklist

Run on a real Mac before any release.

- [ ] First launch shows login (no TCC prompts appear).
- [ ] OAuth login completes; returns to app; menu shows "Sign Out".
- [ ] Tokens are in Keychain (`security find-generic-password -s com.yourorg.claudespotlight.tokens`) and **not** in any plist/log.
- [ ] Global hotkey (⌥Space) opens the panel from another frontmost app.
- [ ] Esc and click-outside both dismiss the panel.
- [ ] A query streams a Claude response into the panel.
- [ ] Token refresh works after expiry (simulate by shortening `expires_in`).
- [ ] Sign Out clears Keychain; next open shows login again.
- [ ] Launch-at-login toggle persists across reboot.
- [ ] **Notarized build**: download dmg on a clean account → opens without
      Gatekeeper warning (`stapler validate` passed).

## CI

- `xcodebuild test` on every PR (macOS runner).
- Lint/format (`swiftformat`/`swiftlint`) if adopted — `TODO(decide)`.
- Release pipeline runs build → sign → notarize (see `09-`, `10-`).

## Definition of done (per change)

1. Code compiles (`xcodebuild build`).
2. Relevant unit tests pass.
3. If it touches auth/hotkey/panel/entitlements: run the matching manual items.
4. The matching doc in `docs/macos/` is updated.

## Related

`05-oauth-auth.md` · `12-claude-api-integration.md` · `10-packaging-distribution.md`
