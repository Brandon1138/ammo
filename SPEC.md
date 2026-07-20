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

- Xcode 16+ / Swift 6 toolchain, iOS 18+ app target.
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

1. Foreground activation, pull-to-refresh, `BGAppRefreshTask`, account creation, and
   WidgetKit timeline requests all enter one `UsageRefreshCoordinator`.
2. A persistent per-account ledger in the App Group enforces a 60-second minimum
   between upstream requests across the app and widget processes. An in-flight lease
   plus an in-process task table coalesces races; failures use exponential backoff,
   with a longer starting backoff for HTTP 429.
   Raw transport/provider errors are written only to private system logs. Persisted
   state stores a stable failure category so the app can show concise timeout,
   offline, authentication, service, response, and rate-limit messages without
   exposing developer diagnostics or provider response bodies to users.
3. For each eligible account: refresh its token if `expiresAt` is near (persist
   rotation immediately), call `fetchUsage`, and atomically commit the normalized
   `UsageSnapshot` to the App Group. Credentials use a dedicated Keychain Sharing
   access group common to the app and widget, remain non-synchronizable, and never
   leave the device.
4. App-owned fetches call `WidgetCenter.shared.reloadAllTimelines()`. Widget-owned
   fetches return the newly committed snapshot in the timeline being generated.
5. Passive scheduling follows observed activity rather than remaining percentage.
   A changed snapshot enters a 5-minute active cadence; the first unchanged fetch
   cools to 15 minutes and the next unchanged fetch returns to 30 minutes, even if
   only 5% remains. A known reset can request an earlier refresh just after its
   boundary. Foreground/manual work may bypass the adaptive wait but still obeys
   the shared 60-second floor and provider backoff. These dates are hints; iOS
   controls actual background execution.
6. Countdown UI is derived from absolute `resetsAt` values, never cached strings.
   The foreground app recomputes once per minute; widget timelines preload local
   5/15/60-minute display entries through the eight-day horizon plus exact reset
   boundaries. These entries do no networking. An expired unconfirmed snapshot
   retains its meter and says `Reset due`; an untouched Claude session with no
   reset timestamp says `Not started`.

### Future reset notifications

All successful fetches commit through `SharedStore.commit(snapshot:for:)`, which
captures both the previous and current snapshot as a `SnapshotTransition` before the
old value is replaced. A later notification feature should attach its detector at
this single seam so app-owned and widget-owned refreshes behave identically.

The detector should create durable, deduplicated events for: a window's `resetsAt`
advancing with utilization falling (scheduled 5-hour, weekly, or Cursor allocation
rollover); a material utilization drop without a corresponding scheduled rollover
(provider/account-specific reset); and an increase in Codex
`resetCreditsAvailable` (a newly banked usage reset). Notification authorization and
delivery remain separate from detection, allowing events to be recorded even when
notifications are disabled and delivered at most once if the user enables them.

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

### Cursor — IMPLEMENTED 2026-07-17; LIVE VERIFICATION PENDING

Cursor has no public individual-plan usage API. Ammo uses Cursor's first-party
PKCE browser login and its private dashboard summary directly from the device.
The full reverse-engineered contract and drift notes live in
[`CURSOR_RESEARCH.md`](CURSOR_RESEARCH.md).

```
GET https://cursor.com/api/usage-summary
Cookie: WorkosCursorSessionToken=<user_id>%3A%3A<access_token>
Accept: application/json
```

For this implementation, `individualUsage.plan.autoPercentUsed` (the dashboard's
current "First-party models" lane) maps to a monthly **Composer** window and
`apiPercentUsed` maps to a monthly **API** window. Both use `billingCycleEnd` as
their reset. `totalPercentUsed`, monetary plan fields, legacy request counts, and
all on-demand spending fields are deliberately ignored.

Onboarding opens `https://cursor.com/loginDeepControl` with a PKCE challenge and
UUID, then polls `https://api2.cursor.sh/auth/poll` until Cursor returns a token
pair. Refresh uses the current first-party `POST https://api2.cursor.sh/oauth/token`
refresh-token grant. The access-token JWT supplies both its expiry and the user id
needed to derive the web-session cookie.

### Desktop credential locations (dev harness / macOS app)

- Claude Code: macOS Keychain, generic password item **`Claude Code-credentials`** —
  JSON with `.claudeAiOauth.{accessToken, refreshToken, expiresAt (ms epoch),
  refreshTokenExpiresAt, scopes, subscriptionType}`. Linux/fallback:
  `~/.claude/.credentials.json`.
- Codex: `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) —
  `.tokens.{access_token, refresh_token, account_id}`, plus `last_refresh`.

---

## Known issues / deferred providers

- **Cursor live proof** — the adapter, mapping, PKCE URL, polling, JWT derivation,
  and refresh decoding have offline coverage, but the complete flow still needs to
  be exercised on-device against a real Cursor account. Its individual usage API is
  private and may drift.
- **Antigravity** (Google; Gemini remains the model brand) — implementation deferred.
  The available local and remote quota surfaces, authentication constraints,
  policy risk, architecture options, and required live proof are documented in
  [ANTIGRAVITY_RESEARCH.md](ANTIGRAVITY_RESEARCH.md). No adapter is promised until
  the direct-iOS OAuth and quota-fidelity questions in that document are validated.
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

## iOS app (phase 3 — implemented)

Generated project: `cd Apps/iOS && xcodegen` → `Ammo.xcodeproj` (gitignored;
`project.yml` is the source of truth). Two targets, both depending on the local
`UsageKit` package:

- **Ammo** (app, `com.brandon.ammo`) — sources in `Apps/iOS/Ammo/` + `Shared/`.
- **AmmoWidgets** (widget extension, `com.brandon.ammo.widgets`) — sources in
  `Apps/iOS/AmmoWidgets/` + `Shared/`.

Both targets carry the App Group `group.com.brandon.ammo`. `Shared/` is compiled
into each target (not a framework): `SharedStore` (accounts + latest snapshots as
JSON in the App Group; app writes, widget reads) and the usage color/glyph styling.

### Storage & trust boundaries

- **Keychain** (`KeychainStore`, service `com.brandon.ammo.tokens`): one generic
  password item per account UUID, `kSecAttrAccessibleAfterFirstUnlock` (so
  background work can read while locked), non-synchronizable, and shared with the
  widget extension through a dedicated Keychain Sharing access group.
- **`StoredAccount.tokensImported`**: set when tokens were pasted from a desktop
  CLI. The fetch pipeline **never calls refresh for imported accounts** (rotation
  could log the CLI out); on 401 it surfaces "re-import" instead.

### Fetch pipeline (`UsageRefreshCoordinator`)

Foreground, pull-to-refresh, widget timelines, and `BGAppRefreshTask` all use the
same cross-process claim. Per account: refresh if `expiresAt` is within 5 minutes
(persisting rotated tokens before the fetch can fail), `fetchUsage`, retry once
through refresh on 401, atomically commit `AccountState`, update adaptive activity
state, then request widget reloads after app-owned changes.

### Onboarding

- **Claude** (`ClaudeOnboardingView`): fresh `PKCE` per attempt →
  `ClaudeProvider.authorizationRequestURL` opened in `SFSafariViewController` →
  user copies the displayed code → `exchangeCode(_:verifier:state:)`. The phone
  gets its own token pair; no interaction with CLI logins.
- **Codex** (`CodexOnboardingView`): primary path `CodexAuthFlow` —
  `LoopbackServer` (NWListener, localhost:1455) captures the redirect during
  `ASWebAuthenticationSession` (started with a nil callback scheme; cancelled
  programmatically once the listener yields the code), state checked, then
  `CodexProvider.exchangeCode`; the ChatGPT account id is pulled from the JWT
  claims (`https://api.openai.com/auth` → `chatgpt_account_id`). Fallback:
  paste `~/.codex/auth.json` (whole file or its `tokens` object) → stored with
  `tokensImported = true`, never refreshed.

## Widget design (phase 3 — implemented)

- **Small widget** (`AmmoAccount`, systemSmall): one account — provider glyph +
  label, one bar per window ("% left" framing), and locally advancing reset
  countdowns. Untouched Claude sessions say `Not started`; unconfirmed elapsed
  resets say `Reset due` without changing the last provider-reported meter.
- **Medium widget** (`AmmoAllAccounts`, systemMedium): all accounts, one compact
  row each (glyph, label, worst-window bar, %).
- **Lock-screen** (`AmmoAccount`, accessoryCircular): gauge of "% left" for the
  account's most-consumed window.
- Per-widget account choice through `AppIntentConfiguration` (`SelectAccountIntent`
  → `AccountEntity`, hydrated from the App Group snapshot file).
- Timeline: local countdown entries plus an adaptive reload policy; timeline
  generation may fetch through the shared coordinator, and the app also forces a
  reload after every successful fetch.
- Color semantics: normal → tint, ≥75% used → amber, ≥90% → red. Dark mode via
  `containerBackground(.fill.tertiary, for: .widget)` — no hardcoded backgrounds.

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
├── Tests/UsageKitTests/       ← decode + onboarding tests
└── Apps/iOS/
    ├── project.yml            ← XcodeGen manifest (source of truth; .xcodeproj gitignored)
    ├── Shared/                ← compiled into app AND widget: App Group store, styling
    ├── Ammo/                  ← app: onboarding, Keychain, fetch pipeline, BG refresh, UI
    └── AmmoWidgets/           ← widget extension: intents, timelines, widget views
```

## Build & verify

```sh
swift test                 # decode/mapping/onboarding tests over fixtures
swift run ammo-harness     # live check against your own logged-in CLIs (macOS)
cd Apps/iOS && xcodegen    # generate Ammo.xcodeproj, then:
xcodebuild -project Ammo.xcodeproj -scheme Ammo \
  -destination 'generic/platform=iOS Simulator' build
open Ammo.xcodeproj        # set your team under Signing & Capabilities, run on device
```

The harness intentionally **never refreshes tokens** (rotation could log out your
CLIs). If it reports an expired Claude token, run `claude` once and retry.
