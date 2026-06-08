# 13 — Reconciled Decisions & Build Status

> This doc is the **current source of truth**. Where earlier docs (`05`, `07`, `08`, `12`)
> conflict with this, **this wins**. Produced after a design pass + web research that
> overturned two original assumptions.

## The two reversals

### A. Engine: NOT app-owned OAuth → the local `claude` CLI (headless)

The original plan — the app runs its own OAuth 2.0 + PKCE login and sends
`Authorization: Bearer <oauth>` to `/v1/messages` — **cannot be built**:

- **Technically blocked:** `/v1/messages` returns `401 "OAuth authentication is currently
  not supported"` for OAuth tokens. Sanctioned Messages-API auth is **API key (`x-api-key`)**
  or Workload Identity Federation only.
- **ToS violation:** reusing Claude Free/Pro/Max OAuth credentials (or Claude Code's
  `client_id`) in another product is prohibited and **actively enforced since ~2026-02**.

**What we do instead** (local/personal use, the chosen v1 path):

- **Stage 2 = spawn the user's own logged-in `claude` CLI headless:**
  `claude -p --output-format json --json-schema <schema>` (no `temperature`/`top_p`/
  `budget_tokens`). This runs the **genuine Anthropic product**, not a token/identity
  spoof — it is the supported path (the same surviving `claude-cli` mode OpenClaw uses
  after its OAuth mode was banned). Verified present on this Mac: `claude` v2.1.168 with
  `--output-format json` + `--json-schema`.
- **Boundaries (honest):** ✅ personal/local. ⚠️ distribution is OK only if each user
  brings their own installed+logged-in Claude Code and we drive the genuine binary (never
  spoof headers / extract tokens / scrape the credentials keychain item). Subscription
  rate limits apply.
- **Distribution route:** a drop-in `x-api-key` reasoner (user pastes a `sk-ant-api03`
  Console key; pay-per-use, separate from Pro/Max). Build Stage 2 behind a small
  `Reasoner` protocol so `ClaudeCLIReasoner` (now) and `APIKeyReasoner` (later) swap freely.
- **Forbidden:** OAuth/subscription token → `/v1/messages`; reusing Claude Code's
  `client_id`; scraping the credentials Keychain item.

### B. App Sandbox: OFF (reverses doc `07`)

Doc `07` said "Sandbox ON" (written for a pure chat client). The launcher's data layer
breaks it: home-scoped `mdfind`, spawning `Process` (mdfind/osascript/shortcuts), and
later Full Disk Access (Messages/Mail) are **incompatible with the sandbox**.

- **Verdict:** Sandbox **OFF**, Hardened Runtime **ON**, Developer-ID signed + notarized
  `.dmg`, **not** Mac App Store. Entitlements near-empty (`app-sandbox=false`).
- **TCC reality:** grants key off **bundle id + code signature**. The grants this terminal
  holds do **not** transfer to the future signed app — it re-earns Calendar (EventKit) and
  Full Disk Access under its own identity. A **stable signing identity** is a correctness
  requirement (this Mac currently has **0 codesigning identities** → release blocker).

## Architecture (unchanged core, from DESIGN.md)

```
⌥Space → NSPanel → ParsedQuery
                      │
            STAGE 1 (no LLM, parallel, ~instant)
              ├─ FileSource: mdfind -attr (name+content+recent flavors, Tier-A scope + exclusions)
              └─ CalendarSource: EventKit in-process
                      │ [Candidate]  → LocalRanker → Branch.decide
            ┌─────────┴──────────┐
         STOP (simple/lexical)   ESCALATE (NL/ambiguous/tie)
         render Stage-1 list     │ compact top-N projection
                                 ▼
                       STAGE 2  (exactly 1 reasoning call)
                       Reasoner = claude -p (local)  |  x-api-key (distribution)
                       structured output: ranked ids + optional answer
                                 │  (any failure → degrade to Stage-1 ranking)
                                 ▼
                       render ranked list → ⏎ opens file / reveals event
```
Reads are automatic; writes (none in v1) would require confirmation.

## Build status

| Phase | What | Status |
|-------|------|--------|
| **0** | SwiftPM CLI harness: Stage-1 collector (files+calendar) + `Candidate` schema + `LocalRanker` + `Branch` → ranked JSON. No auth/network/UI. | ✅ **Done & verified** |
| 1 | Stage 2 behind `Branch`: `ClaudeCLIReasoner` (`claude -p`) + structured ranking; degrade-to-Stage-1. | next |
| 2 | macOS `.app` shell (needs full Xcode): LSUIElement menu bar + `RegisterEventHotKey` + NSPanel + SwiftUI list; reuse `CSpotKit`. | needs Xcode install |
| 3 | More Stage-1 sources (Contacts, Notes/Mail via osascript, Shortcuts) + lazy TCC. | later |
| 4 | (optional) `x-api-key` reasoner for distribution. | later |
| 5 | FDA sources (Messages/Mail/Safari), signing/notarization, `.dmg`, auto-update. | last |

### Phase 0 — how to run / verify
```bash
swift build
swift run cspot "report"                       # ranked file candidates as JSON
swift run cspot "the budget deck last week"     # → shouldEscalate: true
swift run cspot "=invoice"                       # forced Stage-1 (literal)
swift run cspot "?what did I do yesterday"       # forced Stage-2 (askLLM)
swift run cspot "recent:"                         # recency flavor (fast, ~200ms)
```
Verified on this Mac (macOS 26.3, Swift 6.1.2, CLT-only — no Xcode):
- Builds with the Command-Line-Tools toolchain (no Xcode needed for the CLI).
- File results are clean (exclusion filter drops `/Library/`, `/Cache(s)/`, `venv`,
  `site-packages`, `__pycache__`, `node_modules`, `.git`, `.app/`, dotdirs, `.pyc`).
- `Branch` matches spec (`=`→stop, `?`→escalate, NL markers / ≥5 tokens → escalate).
- JSON is schema-correct and round-trips through `jq`.
- **Calendar caveat:** EventKit returns 0 here because this terminal process has only
  `writeOnly` (raw=4) calendar TCC, not `fullAccess` (raw=3). Code is correct; it skips
  gracefully and will work once the Phase-2 app requests full access under its own identity.

### Latency note
Name/recent flavors are fast (~200ms). The `content` flavor (`kMDItemTextContent`) is broad
and slow (~0.9–1.4s, can match 1000s of files). The live app will: debounce input (~120ms),
render name hits first, run content as a progressive enhancement, and read mdfind output
incrementally to cap early — none of which the harness needs to prove the mechanics.

## Open decisions / external verifications
- Deployment target floor (docs say 14; this Mac is 26.3).
- Official bundle id + Developer ID Team (0 codesigning identities today).
- Whether to ship the `x-api-key` reasoner in v1 or defer to distribution time.
- Privacy: which Stage-1 sources may send snippet/body text into Stage 2.
