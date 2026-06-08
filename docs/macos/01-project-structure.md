# 01 — Project Structure

Proposed layout for the Xcode project. Create with Xcode (App template, SwiftUI,
no storyboard) then reorganize to match.

```
claude-spotlight/
├── CLAUDE.md
├── README.md
├── docs/macos/                      # these docs
├── ClaudeSpotlight.xcodeproj
├── ClaudeSpotlight/
│   ├── App/
│   │   ├── ClaudeSpotlightApp.swift # @main, NSApplicationDelegate adapter
│   │   └── AppDelegate.swift        # lifecycle, status item bootstrap
│   ├── MenuBar/
│   │   ├── MenuBarController.swift   # NSStatusItem + menu
│   │   └── MenuBarView.swift
│   ├── Hotkey/
│   │   ├── HotkeyManager.swift       # RegisterEventHotKey wrapper
│   │   └── KeyCombo.swift
│   ├── Panel/
│   │   ├── SpotlightPanel.swift      # NSPanel subclass
│   │   ├── PanelController.swift     # show/hide, positioning
│   │   └── CommandView.swift         # SwiftUI search/chat UI
│   ├── Auth/
│   │   ├── AuthManager.swift         # OAuth+PKCE orchestration
│   │   ├── PKCE.swift                # verifier/challenge gen
│   │   ├── OAuthConfig.swift         # client id, scopes, endpoints
│   │   └── TokenStore.swift          # token model + expiry
│   ├── Keychain/
│   │   └── Keychain.swift            # generic Keychain helper
│   ├── Chat/
│   │   ├── ChatService.swift         # Claude API client
│   │   ├── SSEParser.swift           # server-sent events parsing
│   │   └── Models.swift              # request/response DTOs
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── Preferences.swift         # UserDefaults wrapper
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Info.plist
│   └── Entitlements/
│       └── ClaudeSpotlight.entitlements
├── ClaudeSpotlightTests/            # unit tests (XCTest)
├── ClaudeSpotlightUITests/          # UI tests
└── scripts/
    ├── build.sh                     # xcodebuild wrappers
    ├── sign-notarize.sh
    └── make-dmg.sh
```

## Naming conventions

- Types: `UpperCamelCase`; files named after the primary type.
- One `NS*`/AppKit bridge per file; keep SwiftUI views separate from controllers.
- Async APIs: prefer `async/await`; no completion-handler pyramids.
- Feature folders over layer folders (group by `Auth/`, `Chat/`, not `Views/`).

## Targets

| Target                  | Type        | Notes                              |
| ----------------------- | ----------- | ---------------------------------- |
| `ClaudeSpotlight`       | App         | the menu-bar app                   |
| `ClaudeSpotlightTests`  | Unit tests  | logic: PKCE, SSE, token expiry     |
| `ClaudeSpotlightUITests`| UI tests    | panel show/hide, query flow        |

## Config / secrets

- Non-secret config (OAuth client id, endpoints) → `OAuthConfig.swift` or a
  `Config.plist` checked in. Public client IDs are not secrets.
- No private keys, client secrets, or tokens in the repo. PKCE means **no client
  secret** is needed for a native app.
