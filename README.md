# claude-spotlight

A macOS **Spotlight-style launcher for Claude**. Summon a floating command bar
with a global hotkey (default `⌥Space`), ask Claude anything, and get a streamed
answer — without leaving whatever app you're in.

- 🪟 Lives in the **menu bar** (no Dock icon)
- ⌨️ **Global hotkey** to open the command panel from anywhere
- 🔐 **Sign in with your own Anthropic account** (OAuth 2.0 + PKCE)
- ⚡️ Streams responses from the **Claude API**

Native **Swift / SwiftUI**, macOS 14+.

## Status

Early scaffolding. The macOS design + how-to docs are written first (this is an
AI-native repo); app code follows.

## Run / Install (Phase 0 — Stage-1 collector CLI)

From the repo (no install):

```bash
swift run -q cspot "report"          # ranked candidate JSON
swift run -q cspot "recent:"          # recent files (fast)
swift run -q cspot "=invoice"         # force Stage-1 only
swift run -q cspot "?find my budget"  # force Stage-2 escalate flag
```

Install as a global `cspot` command (no Homebrew needed):

```bash
./scripts/install.sh                  # build release → ~/.local/bin/cspot
cspot "report" | jq                   # run from anywhere
./scripts/uninstall.sh                # remove it
```

Homebrew: a ready formula lives in [`Formula/cspot.rb`](Formula/cspot.rb). It needs the
repo pushed to GitHub first (Homebrew installs from a source URL), then:
`brew install --HEAD Moon-1C/claude-spotlight/cspot`. See the formula header for steps.

> Requires Swift (Xcode Command Line Tools are enough — full Xcode not needed for the CLI).
> Stage 2 (LLM ranking via `claude -p`) is not wired yet; calendar needs the app's own
> TCC grant (Phase 2). See [`docs/macos/13-decisions-and-status.md`](docs/macos/13-decisions-and-status.md).

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — guidance for AI agents working in this repo
- [`docs/macos/`](docs/macos/) — the macOS design & implementation docs:

| # | Doc | Topic |
|---|-----|-------|
| 00 | [overview](docs/macos/00-overview.md) | architecture & data flow |
| 01 | [project-structure](docs/macos/01-project-structure.md) | folders, targets, naming |
| 02 | [app-lifecycle-menubar](docs/macos/02-app-lifecycle-menubar.md) | accessory app, menu bar |
| 03 | [global-hotkey](docs/macos/03-global-hotkey.md) | system-wide shortcut |
| 04 | [spotlight-panel](docs/macos/04-spotlight-panel.md) | the floating command bar |
| 05 | [oauth-auth](docs/macos/05-oauth-auth.md) | OAuth 2.0 + PKCE login |
| 06 | [keychain-storage](docs/macos/06-keychain-storage.md) | secure token storage |
| 07 | [entitlements-sandbox](docs/macos/07-entitlements-sandbox.md) | entitlements & sandbox |
| 08 | [permissions-tcc](docs/macos/08-permissions-tcc.md) | TCC permission prompts |
| 09 | [code-signing-notarization](docs/macos/09-code-signing-notarization.md) | signing & notarization |
| 10 | [packaging-distribution](docs/macos/10-packaging-distribution.md) | `.dmg`, updates |
| 11 | [testing](docs/macos/11-testing.md) | test process & checklist |
| 12 | [claude-api-integration](docs/macos/12-claude-api-integration.md) | calling the Claude API |

## License

TBD.
