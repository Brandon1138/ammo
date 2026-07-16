# AMMO — Build-It-Yourself Spec

**Ammo** is an iOS app + home-screen widgets that show how much usage you have left
across your AI coding subscriptions — Claude Code and Codex today, Cursor and
Antigravity later.

This document is the deliverable. It exists so that **you can rebuild Ammo yourself**
by handing this spec to a coding agent (Claude Code or similar), instead of granting a
stranger's app OAuth access to your accounts. Everything an implementation needs is
here: the reverse-engineered API contracts, the auth flows, the architecture, and
instructions for re-deriving any contract that has drifted since this spec was written.

## Trust model (why DIY)

- **No server.** The app talks directly from your device to Anthropic/OpenAI. Nothing
  is proxied, logged, or aggregated anywhere.
- **Tokens never leave the device.** Credentials live in the iOS Keychain
  (`kSecAttrAccessibleAfterFirstUnlock`, non-synchronizable so they don't ride iCloud
  Keychain to other devices unless you choose otherwise).
- **No scoping-down is possible, so don't pretend.** The OAuth tokens these providers
  issue can do inference, not just read usage. There is no "rate limits only"
  permission. The DIY answer is not a narrower token — it's that the token is only
  ever held by code you built and can read.
- **You sign it.** Build with your own Apple Developer account. With a paid account
  the app is permanent; with a free account it must be re-signed every 7 days.

## Requirements

- Xcode 16+ / Swift 6 toolchain, iOS 17+ target.
- An Apple Developer account (free works, with the 7-day re-sign caveat).
- Logged-in subscriptions to the providers you want to track.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to
  generate the Xcode project from `project.yml` deterministically.

## Architecture

Three layers, strictly separated:

```
┌────────────────────────────────────────────────────┐
│  AmmoWidgets (WidgetKit extension)                 │
│  reads cached UsageSnapshots via App Group; never  │
│  touches the network or tokens directly            │
├────────────────────────────────────────────────────┤
│  Ammo (iOS app)                                    │
│  account onboarding (OAuth), Keychain storage,     │
│  fetch + token refresh, snapshot cache writes,     │
│  BGAppRefreshTask background updates               │
├────────────────────────────────────────────────────┤
│  UsageKit (platform-agnostic Swift package)        │
│  provider adapters, normalized models, OAuth       │
│  helpers; no UIKit/WidgetKit imports — reusable    │
│  for a macOS MenuBarExtra app later                │
└────────────────────────────────────────────────────┘
```

### UsageKit core types

```swift
enum ProviderID { case claude, codex, cursor, antigravity }
enum WindowKind { case session, weekly, monthly, modelScoped, unknown }

struct LimitWindow { kind, label, usedPercent, resetsAt }   // normalized unit
struct UsageSnapshot { provider, plan, windows: [LimitWindow],
                       resetCreditsAvailable, fetchedAt }
struct OAuthTokens { accessToken, refreshToken?, expiresAt?, accountID? }

protocol UsageProvider {
    var id: ProviderID { get }
    func fetchUsage(tokens: OAuthTokens) async throws -> UsageSnapshot
    func refresh(tokens: OAuthTokens) async throws -> OAuthTokens
}
```

Adapters are stateless; credentials are passed per call. **Multi-account is therefore
free**: an account is `(provider, user-chosen label, Keychain-stored OAuthTokens)`,
and any number of accounts per provider reuse one adapter.

### Data flow

1. App (foreground or `BGAppRefreshTask`) iterates enabled accounts.
2. For each: refresh token if `expiresAt` is near (persist rotated refresh tokens
   immediately), call `fetchUsage`, write the `UsageSnapshot` JSON into the shared
   App Group container.
3. Call `WidgetCenter.shared.reloadAllTimelines()`.
4. Widget timeline provider reads snapshots from the App Group, renders, and asks for
   a refresh ~every 30 minutes (WidgetKit budgets roughly 40–70 refreshes/day; each
   render also computes "resets in Xh Ym" locally from `resetsAt`, so countdowns stay
   fresh between fetches via `Text(_:style: .relative)`).

---

## Provider contracts

> **Date-stamped:** every contract below was verified live on **2026-07-16**. These
> are undocumented APIs; they drift. If a request fails or a field is missing, go to
> "Re-deriving the contracts" before changing any code.

### Claude (Anthropic) — VERIFIED 2026-07-16

**Usage endpoint**

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>          # sk-ant-oat01-…
anthropic-beta: oauth-2025-04-20
```

Response (fields Ammo consumes):

```jsonc
{
  "five_hour":  { "utilization": 36.0, "resets_at": "2026-07-16T15:19:59.837992+00:00" },
  "seven_day":  { "utilization": 4.0,  "resets_at": "…" },
  "limits": [                              // ← normalized source of truth; prefer this
    { "kind": "session",       "percent": 36, "resets_at": "…", "scope": null },
    { "kind": "weekly_all",    "percent": 4,  "resets_at": "…", "scope": null },
    { "kind": "weekly_scoped", "percent": 7,  "resets_at": "…",
      "scope": { "model": { "display_name": "Fable" } } }       // per-model bucket
  ],
  "extra_usage": { /* overage credits — optional display */ }
}
```

Mapping: `limits[]` entries → `LimitWindow`s (`session`→Session, `weekly_all`→Weekly,
`weekly_scoped`→modelScoped labeled by `scope.model.display_name`). Fall back to
`five_hour`/`seven_day` buckets if `limits` is absent. Timestamps are ISO 8601 with
**6-digit fractional seconds** — `ISO8601DateFormatter` rejects these; trim to
milliseconds before parsing.

**OAuth (PKCE, public client — the same client the Claude Code CLI uses)**

- Client ID: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (public; PKCE, no secret)
- Scopes: `user:profile user:inference user:sessions:claude_code user:mcp_servers`
- Authorize (the `code=true` variant renders the auth code on a page for the user to
  copy — **no callback needed, ideal for iOS**):

```
https://claude.ai/oauth/authorize?code=true
  &client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e
  &response_type=code
  &redirect_uri=https://platform.claude.com/oauth/code/callback
  &scope=user:profile%20user:inference%20user:sessions:claude_code%20user:mcp_servers
  &code_challenge=<base64url(SHA256(verifier))>&code_challenge_method=S256
  &state=<base64url random>
```

- Token exchange: `POST https://platform.claude.com/v1/oauth/token`, form-encoded:
  `grant_type=authorization_code, code (strip any #fragment), redirect_uri, client_id,
  code_verifier, state`. Returns `access_token` (8 h lifetime, `expires_in: 28800`),
  `refresh_token` (`sk-ant-ort01-…`, ~19-day lifetime).
- Refresh: same endpoint, `grant_type=refresh_token, refresh_token, client_id`.
  *(Standard grant; refresh specifically not yet exercised live — verify on first
  implementation and update this line.)*

**Onboarding UX**: open the authorize URL in `ASWebAuthenticationSession` /
`SFSafariViewController`, user logs in, copies the displayed code, pastes it into
Ammo. The phone gets its **own token pair** — it never shares tokens with, nor can it
invalidate, a CLI login elsewhere.

### Codex (OpenAI) — VERIFIED 2026-07-16

**Usage endpoint**

```
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <access_token>          # JWT from ChatGPT OAuth
ChatGPT-Account-Id: <account_id>
User-Agent: codex-cli
```

Response (fields Ammo consumes):

```jsonc
{
  "plan_type": "plus",
  "rate_limit": {
    "primary_window":   { "used_percent": 5, "limit_window_seconds": 604800,
                          "reset_after_seconds": 590909, "reset_at": 1784797038 },
    "secondary_window": null
  },
  "additional_rate_limits": null,          // shape unverified (null in the wild)
  "rate_limit_reset_credits": { "available_count": 1 }   // "1 reset available"
}
```

Mapping: classify each non-null window **by `limit_window_seconds`, never by
position** — OpenAI removed the 5-hour Codex session limit, so plans currently expose
a weekly window only, and windows may reshuffle again (<24 h → Session, <8 d → Weekly,
else Monthly). `reset_at` is epoch seconds. Surface `available_count` as
"N resets available".

**OAuth**

- Client ID: `app_EMoamEEZ73f0CkXaXp7hrann` (public, same as the Codex CLI)
- Login flow redirects to `http://localhost:1455/auth/callback` — there is **no
  code-paste variant**. Ammo's onboarding (chosen approach): start a loopback
  `NWListener` on port 1455 inside the app, open the auth URL in
  `ASWebAuthenticationSession`; when the provider redirects to localhost, the
  listener captures the code, completes PKCE exchange, and serves a tiny
  "return to Ammo" success page. Fallback onboarding: paste the `tokens` object from
  the desktop's `~/.codex/auth.json`.
- Token refresh: `POST https://auth.openai.com/oauth/token`, JSON body:
  `{"client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "grant_type": "refresh_token",
  "refresh_token": "…", "scope": "openid profile email"}`.
- ⚠️ **Rotation caution:** refresh may rotate the refresh token. If tokens were
  *imported* from a desktop CLI, refreshing from the phone may invalidate the CLI's
  copy — this is why on-device login (own token pair) is the primary onboarding, and
  why the dev harness never calls refresh.

### Desktop credential locations (dev harness / macOS app)

- Claude Code: macOS Keychain, generic password item **`Claude Code-credentials`** —
  JSON with `.claudeAiOauth.{accessToken, refreshToken, expiresAt (ms epoch),
  refreshTokenExpiresAt, scopes, subscriptionType}`. Linux/fallback:
  `~/.claude/.credentials.json`.
- Codex: `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) —
  `.tokens.{access_token, refresh_token, account_id}`, plus `last_refresh`.

---

## Known issues / deferred providers

- **Cursor** — deferred. No third-party OAuth; the dashboard's JSON endpoints are
  gated on the `WorkosCursorSessionToken` browser cookie. An adapter means "paste
  your session cookie" onboarding and periodic re-auth when it expires. Endpoint
  research exists in [CodexBar](https://github.com/steipete/CodexBar) (MIT), which
  ships a working Cursor provider to crib from.
- **Antigravity** (Google; the IDE — Gemini remains the model brand) — deferred.
  Auth is a Google account; the usage surface is not yet mapped. Needs a research
  spike (proxy the IDE's traffic, or check CodexBar's `gemini.md`/provider list for
  prior art) before an adapter is promised.
- **Claude refresh grant** — implemented per standard OAuth but not yet exercised
  live (see §Claude).
- **Codex `additional_rate_limits[]`** — always `null` in observed responses; decode
  is tolerant but the populated shape is unverified.
- **Codex token lifetime** — access-token JWT expiry not pinned down; the CLI
  refreshes when `last_refresh` > 8 days. Ammo refreshes reactively on HTTP 401.

## Re-deriving the contracts (when they drift)

1. **Cheapest:** check [CodexBar](https://github.com/steipete/CodexBar)'s
   `docs/claude.md`, `docs/codex.md`, `docs/codex-oauth.md` — actively maintained,
   MIT, and it tracks these same private APIs (plus Cursor/Gemini for later phases).
2. **Claude:** run `claude /usage` (or the CLI with `ANTHROPIC_LOG=debug`) and observe
   the request; or replay the Keychain token against the endpoint with `curl` and
   inspect the JSON.
3. **Codex:** run `codex -s read-only -a untrusted app-server` and call the JSON-RPC
   methods `account/read` / `account/rateLimits/read`; or proxy the CLI
   (`mitmproxy`) to see current endpoints/headers.
4. Update the contract section, the adapter, and the test fixtures together, and
   re-date-stamp the section.

## Widget design (phase 3 — to be hardened)

- **Small widget:** one account — provider glyph + name, one bar per window
  ("% left" framing, like the app that inspired this), "Resets in …" via relative
  date text.
- **Medium widget:** all enabled accounts, one compact row each (provider, best/worst
  window bar, %).
- **Lock-screen (accessory) widgets:** single gauge (`accessoryCircular`) for a
  chosen account+window.
- Per-widget configuration through `AppIntentConfiguration` (pick accounts/windows).
- Color semantics: normal → tint, ≥75% used → amber, ≥90% → red. Respect dark mode
  by using system materials — no hardcoded backgrounds.

## macOS (explicit non-goal for now)

`UsageKit` compiles for macOS unchanged. A later `MenuBarExtra` SwiftUI app can reuse
the desktop credential readers from the harness for zero-onboarding usage bars in the
menu bar. Nothing in the current codebase may import iOS-only frameworks into
UsageKit, precisely to keep this door open.

## Repository layout

```
ammo/
├── SPEC.md                    ← this file (the shareable deliverable)
├── Package.swift              ← UsageKit + ammo-harness (SwiftPM)
├── Sources/UsageKit/          ← models, adapters, OAuth helpers
├── Sources/AmmoHarness/       ← macOS CLI: proves adapters w/ real local creds
├── Tests/UsageKitTests/       ← decode tests over captured fixtures
└── Apps/iOS/                  ← (phase 3) project.yml → xcodegen → Ammo.xcodeproj
```

## Build & verify

```sh
swift test                 # decode/mapping tests over captured fixtures
swift run ammo-harness     # live check against your own logged-in CLIs (macOS)
# phase 3: cd Apps/iOS && xcodegen && open Ammo.xcodeproj
```

The harness intentionally **never refreshes tokens** (rotation could log out your
CLIs). If it reports an expired Claude token, run `claude` once and retry.
