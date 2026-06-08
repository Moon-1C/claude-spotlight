# CLAUDE.md

> AI-native guidance for the **claude-spotlight** repo. Read this first.
> Human-facing intro lives in `README.md`; deep macOS docs live in `docs/macos/`.

## What this project is

**claude-spotlight** is a macOS launcher app — a Spotlight-style command bar that you
summon with a global hotkey and use to talk to Claude. It is a native
**Swift / SwiftUI** app that:

1. Lives in the menu bar (no Dock icon — `LSUIElement` / accessory app).
2. Pops a borderless, floating "Spotlight" panel on a global hotkey (default `⌥Space`).
3. Collects candidates from local sources (files via Spotlight/`mdfind`, calendar
   via EventKit, …) with **no LLM** — Stage 1 of a 2-stage pipeline.
4. For ambiguous / natural-language queries, escalates to **Stage 2**: one reasoning
   call to rank/synthesize the candidates, then renders the result.

> ⚠️ **Engine pivot (see `docs/macos/13-decisions-and-status.md`).** The original
> "app-owned OAuth → Claude API" plan is **blocked + a ToS violation** — `/v1/messages`
> rejects OAuth tokens and reusing subscription OAuth in a third-party tool is
> prohibited (enforced 2026). The reasoning engine is now the **local `claude` CLI
> run headless** (`claude -p`) for local/personal use — the supported path (same one
> OpenClaw's surviving `claude-cli` mode uses). An optional user-supplied **API key
> (`x-api-key`)** path is the route for distribution. Docs `05`/`07`/`12` are
> superseded where they describe OAuth-into-the-API; see doc `13`.

## Tech stack (decided)

| Concern            | Choice                                              |
| ------------------ | --------------------------------------------------- |
| Language / UI      | Swift 5.9+, SwiftUI (AppKit bridges where needed)   |
| Min target         | macOS 14 (Sonoma) — adjust in `docs/macos/00-overview.md` |
| App type           | Menu-bar accessory (`LSUIElement = YES`)            |
| Window             | `NSPanel` (nonactivating, floating)                 |
| Global hotkey      | Carbon `RegisterEventHotKey` (see hotkey doc)       |
| Stage 1 (collect)  | Native, no LLM: `mdfind`/Spotlight + EventKit, parallel |
| Stage 2 (reason)   | **Local `claude -p` headless** (default); optional `x-api-key` for distribution |
| Sandbox            | **OFF** (data access needs it — reverses doc `07`); Hardened Runtime ON |
| Build              | SwiftPM now (CLI engine); Xcode project for the `.app` (Phase 2) |
| Status             | **Phase 0 done** — Stage-1 collector CLI (`swift run cspot "<q>"`) builds & verified |

## Where to look

All macOS-specific design + how-to docs are numbered in `docs/macos/`:

- `00-overview.md` — architecture, module map, data flow
- `01-project-structure.md` — folders, targets, naming
- `02-app-lifecycle-menubar.md` — accessory app, menu bar item, lifecycle
- `03-global-hotkey.md` — registering & handling the global shortcut
- `04-spotlight-panel.md` — the floating command panel (NSPanel)
- `05-oauth-auth.md` — OAuth 2.0 + PKCE login flow
- `06-keychain-storage.md` — secure token storage
- `07-entitlements-sandbox.md` — entitlements & App Sandbox
- `08-permissions-tcc.md` — TCC prompts (Accessibility, network, etc.)
- `09-code-signing-notarization.md` — signing, notarization, stapling
- `10-packaging-distribution.md` — `.app`/`.dmg`, Sparkle/auto-update
- `11-testing.md` — unit, UI, and manual test process
- `12-claude-api-integration.md` — calling the Claude API from Swift

## Working agreements (for AI agents)

- **Keep docs in sync with code.** If you change auth, hotkey, or entitlements
  behavior, update the matching doc in the same change.
- **Never hardcode secrets.** Client IDs that are public are fine; tokens go to
  Keychain only, never to disk/logs.
- **Verify before claiming "works."** Build with `xcodebuild` and run the
  relevant tests (`docs/macos/11-testing.md`) before reporting success.
- **Anything Anthropic/Claude-API-shaped:** consult the `claude-api` reference
  (model IDs, pricing, streaming) instead of answering from memory.
- **Placeholders are marked `TODO(verify)`** where an exact value (OAuth client
  ID, endpoint, Team ID) must be confirmed against the real source.
