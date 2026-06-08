# 00 — Architecture Overview

## Goal

A menu-bar–resident macOS app that, on a global hotkey, shows a Spotlight-style
command panel for talking to Claude. Auth is the app's own OAuth login.

## Platform targets

- **Min deployment target:** macOS 14.0 (Sonoma). `TODO(verify)` lower if needed.
- **Architectures:** universal (`arm64` + `x86_64`).
- **Distribution:** Developer ID signed + notarized `.dmg` (not Mac App Store
  initially — see `09-` and `10-`). MAS would require sandbox constraints that
  affect the global hotkey; revisit later.

## High-level architecture

```
┌──────────────────────────────────────────────────────────┐
│  claude-spotlight.app  (LSUIElement, no Dock icon)         │
│                                                            │
│  ┌────────────┐   hotkey    ┌─────────────────────────┐   │
│  │ MenuBar     │────────────▶│ SpotlightPanel (NSPanel)│   │
│  │ (NSStatusItem)            │  SwiftUI content view   │   │
│  └────────────┘             └───────────┬─────────────┘   │
│                                          │ query           │
│  ┌──────────────┐   tokens   ┌───────────▼─────────────┐  │
│  │ AuthManager   │◀──────────▶│ ChatService             │  │
│  │ OAuth+PKCE    │  Keychain  │ URLSession SSE stream   │  │
│  └──────┬───────┘            └───────────┬─────────────┘  │
│         │                                 │                │
└─────────┼─────────────────────────────────┼───────────────┘
          ▼                                 ▼
   Anthropic OAuth                   Claude API (Messages)
```

## Modules

| Module          | Responsibility                                              |
| --------------- | ---------------------------------------------------------- |
| `App`           | Entry point, `NSApplicationDelegate`, lifecycle            |
| `MenuBar`       | `NSStatusItem`, menu, settings entry                       |
| `Hotkey`        | Global shortcut registration + dispatch                    |
| `Panel`         | `NSPanel` host + SwiftUI command/search UI                 |
| `Auth`          | OAuth 2.0 + PKCE, token refresh, sign-out                  |
| `Keychain`      | Secure token read/write                                    |
| `Chat`          | Claude API client, streaming, message state               |
| `Settings`      | User prefs (hotkey, model, theme) via `UserDefaults`       |

## Data flow (one query)

1. User presses hotkey → `Hotkey` posts an event → `Panel` is shown & focused.
2. User types a prompt, hits ⏎.
3. `Panel` asks `Auth` for a valid access token (refresh if expired).
4. `Chat` calls the Claude API with streaming; tokens render incrementally.
5. Esc or focus-loss hides the panel; conversation state is kept in memory
   (persistence is out of scope for v1 — `TODO`).

## Out of scope (v1)

- Mac App Store build, iCloud sync, multi-window history, plugins.
- Reading Claude Code's existing credentials (explicitly not done).

## Related docs

`01-project-structure.md` · `05-oauth-auth.md` · `12-claude-api-integration.md`
