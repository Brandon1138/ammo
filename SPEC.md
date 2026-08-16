# AMMO — Build-It-Yourself Spec

**Ammo** is an iOS app + home-screen widgets that show how much included and
on-demand usage you have left across your AI coding subscriptions — Claude Code,
Codex, Cursor, and OpenRouter today; Antigravity later.

This document is the deliverable. It exists so that **you can rebuild Ammo yourself**
by handing this spec to a coding agent (Claude Code or similar), instead of granting a
stranger's app OAuth access to your accounts. Everything an implementation needs is
here: the provider contracts observed from authenticated clients, the auth flows, the architecture, and
instructions for re-deriving any contract that has drifted since this spec was written.

## Trust model (why DIY)

- **No server.** The app talks directly from your device to Anthropic/OpenAI. Nothing
  is proxied, logged, or aggregated anywhere.
- **Tokens never leave the device.** Credentials live in the iOS Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non-synchronizable, excluded
  from backup migration, and never transferred to another device).
- **Do not overstate credential scope.** Claude, Codex, and Cursor OAuth tokens can
  do more than read usage. OpenRouter uses an ordinary inference key because its
  current-key endpoint accepts that key; Ammo never asks for the more powerful
  Management key. The DIY boundary is that credentials stay in inspectable code
  on the device, not that every provider offers a usage-only permission.
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
│  reads cached UsageSnapshots via App Group and may │
│  refresh through shared Keychain credentials       │
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
enum ProviderID { case claude, codex, cursor, openRouter, antigravity }
enum WindowKind { case session, weekly, monthly, modelScoped, unknown }
enum OnDemandKind { case creditBalance, spendingLimit, personalAllocation,
                    teamBudget, pooledBudget }
enum OnDemandScope { case personal, team, organization }

struct LimitWindow { kind, label, usedPercent, resetsAt }   // normalized unit
struct OnDemandUsage { id, label, kind, scope, isEnabled, isUnlimited,
                       currencyCode, used, limit, remaining, usedPercent,
                       periodStart, resetsAt }
struct UsageSnapshot { provider, plan, windows: [LimitWindow],
                       resetCreditsAvailable, onDemand: [OnDemandUsage]?, fetchedAt }
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

### Local usage history

Every successfully accepted snapshot also enters a local App Group history file.
History is downsampled to at most one observation per account every 15 minutes,
except that confirmed cycle changes are always retained. Samples expire after 90
days and are deleted with their account. No history leaves the device.

The app presents `Usage`, `On-demand`, and `History` as three native tabs. Included
rate-limit windows remain in Usage; monetary balances and spending controls remain
separate in On-demand and are never blended into a synthetic percentage. History is
scoped to one account and one provider limit at a time. Its 12-week activity grid sums positive,
reset-aware changes in `usedPercent` on the day Ammo first observed them; it does
not imply exact prompt, message, or token counts. The remaining-allowance chart uses
the original observations, marks confirmed rollovers, and breaks the line across
large observation gaps rather than interpolating missing data.

### Future reset notifications

All successful fetches commit through `SharedStore.commit(snapshot:for:)`, which
captures both the previous and current snapshot as a `SnapshotTransition` before the
old value is replaced. A later notification feature should attach its detector at
this single seam so app-owned and widget-owned refreshes behave identically.

The detector should create durable, deduplicated events for: a window's `resetsAt`
advancing with utilization falling (scheduled 5-hour, weekly, or Cursor allocation
rollover); a material utilization drop without a corresponding scheduled rollover
(provider/account-specific reset); an increase in Codex `resetCreditsAvailable` (a
newly banked usage reset); on-demand spend beginning after included usage is
exhausted; low remaining balance; an exhausted balance/cap; and provider
replenishment. `OnDemandUsage.id` is the stable comparison key. Notification
authorization and delivery remain separate from detection, allowing events to be
recorded even when notifications are disabled and delivered at most once if the
user enables them. The implementation comment at `SharedStore.commit` marks this
integration seam; notification delivery is outside the current on-demand scope.

---

## Provider contracts

> **Date-stamped:** the core endpoints and captured account fixtures were verified
> live on **2026-07-16**. The expanded on-demand shapes were rechecked on
> **2026-07-21** against the current maintained CodexBar parsers and tests; Cursor's
> authenticated live proof remains explicitly pending below. These are undocumented
> APIs and may drift. If a request fails or a field is missing, go to "Re-deriving
> the contracts" before changing code.

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
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 2000,     // minor currency units ($20.00)
    "used_credits": 520,       // minor currency units ($5.20)
    "utilization": 26.0,
    "currency": "USD"
  }
}
```

Mapping: `limits[]` entries → `LimitWindow`s (`session`→Session, `weekly_all`→Weekly,
`weekly_scoped`→modelScoped labeled by `scope.model.display_name`). Fall back to
`five_hour`/`seven_day` buckets if `limits` is absent. Timestamps are ISO 8601 with
**6-digit fractional seconds** — `ISO8601DateFormatter` rejects these; trim to
milliseconds before parsing.

`extra_usage` maps to one personal `OnDemandUsage.spendingLimit`. Convert
`monthly_limit` and `used_credits` from minor to major currency units, retain the
provider-reported utilization, and preserve `is_enabled == false` as an explicit
disabled entry rather than treating the field as absent.

**Plan profile (best effort)**

```
GET https://api.anthropic.com/api/oauth/profile
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

Fetch this alongside usage so it adds no serial latency. Plan metadata is supplemental:
profile HTTP or decode failure must never fail the usage refresh. Prefer
`subscription_type`, then organization `organization_type`, then `rate_limit_tier` /
`seat_tier`; normalize only recognized Pro, Max, Team, Enterprise, and Ultra values.
The current Claude CLI exposes this profile surface, but it is undocumented and must
remain tolerant of missing or moved fields.

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

### Codex (OpenAI) — VERIFIED 2026-07-21

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
  "plan_type": "self_serve_business_usage_based",
  "rate_limit": {
    "primary_window":   { "used_percent": 5, "limit_window_seconds": 604800,
                          "reset_after_seconds": 590909, "reset_at": 1784797038 },
    "secondary_window": null
  },
  "additional_rate_limits": null,          // shape unverified (null in the wild)
  "credits": {
    "has_credits": true, "unlimited": false, "balance": null,
    "overage_limit_reached": false
  },
  "spend_control": {
    "individual_limit": {                  // enterprise/personal spend control
      "limit": 100, "used": 37.5, "remaining_percent": 62.5,
      "resets_at": 1784797038
    }
  },
  "rate_limit_reset_credits": { "available_count": 1 }   // "1 reset available"
}
```

Mapping: classify each non-null window **by `limit_window_seconds`, never by
position** — OpenAI removed the 5-hour Codex session limit, so plans currently expose
a weekly window only, and windows may reshuffle again (<24 h → Session, <8 d → Weekly,
else Monthly). `reset_at` is epoch seconds. Surface `available_count` as
"N resets available".

Map `self_serve_business_usage_based` to the user-facing badge **Business**; unknown
raw tags get word-wise formatting instead of exposing underscores. `credits` is a
provider-credit unit, not USD. For Business it is organization-scoped, and
`balance: null` means only that OAuth cannot read the amount—not that the balance is
zero. Decode `credits.overage_limit_reached`. Decode the current
`spend_control.individual_limit` nesting, while retaining the older top-level and
`rate_limit.individual_limit` fallbacks. Purchased usage credits and
`rate_limit_reset_credits` are different products and must never share a label or
normalized field.

**Workspace billing and credit provenance**

Codex OAuth and `wham/usage` are the only sources for values Ammo displays. Preserve
an exact balance when that response supplies one; when it reports `balance: null`,
render **Balance unavailable** without fabricating or enriching it. Snapshots written
before source attribution are treated as unverified and any exact Codex balance,
expiry, or local-currency conversion they contain is removed at load time.

`Update workspace balance` never embeds ChatGPT or reads its page, cookies, session,
account ID, DOM, or private endpoints. It offers a confirmation explaining that the
user must be a Workspace Owner, sign in to ChatGPT, and choose the correct workspace,
then opens `https://chatgpt.com/admin/billing` in the system browser. Because Ammo has
no external-purchase entitlement, this purchase-related call to action is enabled
only when StoreKit reports the `USA` storefront; non-US and unknown storefronts fail
closed. `View Codex usage` is a separate system-browser action to
`https://chatgpt.com/codex/settings/usage`.

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
The full observed contract and drift notes live in
[`CURSOR_RESEARCH.md`](CURSOR_RESEARCH.md).

```
GET https://cursor.com/api/usage-summary
Cookie: WorkosCursorSessionToken=<user_id>%3A%3A<access_token>
Accept: application/json
```

For included usage, `individualUsage.plan.autoPercentUsed` (the dashboard's current
"First-party models" lane) maps to a monthly **Composer** window and
`apiPercentUsed` maps to a monthly **API** window. Both use `billingCycleEnd` as
their reset. Percent fields are already percentages, including fractional values
below one; do not multiply by 100.

Cursor's monetary structures are all decoded independently and converted from cents
to major USD units:

- `individualUsage.onDemand` → personal on-demand spending limit.
- `individualUsage.overall` → enterprise/team member personal allocation.
- `teamUsage.onDemand` → team on-demand budget.
- `teamUsage.pooled` → shared organization pool.

Each present block remains a distinct `OnDemandUsage` entry, including an explicitly
disabled block. Do not collapse personal and shared money into one preferred balance.
`billingCycleStart` and `billingCycleEnd` provide the period boundaries. If an
enterprise payload contains monetary data but no Composer/API percentages, the
snapshot remains valid so its On-demand tab can still render.
An enabled block with omitted `used`/`limit`/`remaining` is **amount unavailable**,
not implicitly unlimited; only an explicit `isUnlimited` value can claim unlimited.

Onboarding opens `https://cursor.com/loginDeepControl` with a PKCE challenge and
UUID, then polls `https://api2.cursor.sh/auth/poll` until Cursor returns a token
pair. Refresh uses the current first-party `POST https://api2.cursor.sh/oauth/token`
refresh-token grant. The access-token JWT supplies both its expiry and the user id
needed to derive the web-session cookie.

### OpenRouter — DOCUMENTED CONTRACT VERIFIED 2026-08-17; LIVE DEVICE PROOF PENDING

Ammo stores an ordinary OpenRouter inference key in its existing Keychain item and
uses exactly one authenticated endpoint:

```
GET https://openrouter.ai/api/v1/key
Authorization: Bearer <ordinary inference API key>
Accept: application/json
```

`limit` and `limit_remaining` are USD key-budget values. The matching
`usage_daily`, `usage_weekly`, or `usage_monthly` value supplies active-period spend
when `limit_reset` names that cadence; otherwise total `usage` is used. BYOK spend is
included only when `include_byok_in_limit` is true. Daily boundaries are midnight
UTC, weekly boundaries are Monday 00:00 UTC, and monthly boundaries are the first
day 00:00 UTC. The aggregate fields are money, never synthetic `LimitWindow`s.

A missing `limit` is a valid no-limit key: Ammo persists the reported spend but no
remaining balance, credit substitute, percentage, or reset timestamp. Imported keys
are non-refreshable. Management/provisioning keys are rejected.

OpenRouter documents S256 PKCE at `https://openrouter.ai/auth` and code exchange at
`POST https://openrouter.ai/api/v1/auth/keys`, including localhost callbacks on any
port. Ammo intentionally ships API-key import until that callback, generated-key
limit behavior, exchange response, and `/api/v1/key` access are exercised end to end
on a physical iPhone. `/api/v1/credits`, `/api/v1/activity`, and key administration
require a Management key and are out of scope.

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
- **OpenRouter live proof** — API-key import and the documented `/api/v1/key`
  contract have deterministic coverage. A real ordinary key response and the
  documented PKCE localhost/code-exchange flow still require physical-iPhone
  validation before replacing import onboarding or claiming live support.
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
JSON in the App Group; both processes read and may update it under shared locks)
and the usage color/glyph styling. Widget timelines can contact providers through
`UsageRefreshCoordinator`; credentials remain in shared Keychain items and never
enter App Group files.

The app shell uses three tabs: **Usage** for included allowance, **On-demand** for
prepaid balances and personal/team/organization spend controls, and **History** for
local rate-limit observations. A compact row in each Usage account section links to
On-demand when that provider reports monetary capacity.

### Storage & trust boundaries

- **Keychain** (`KeychainStore`, service `com.brandon.ammo.tokens`): one generic
  password item per account UUID, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  (so background work can read after first unlock), non-synchronizable, excluded
  from backup migration, and shared with the widget extension through a dedicated
  Keychain Sharing access group.
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
- **Accounts widget** (`AmmoAllAccounts`): systemSmall shows the first two configured
  accounts as compact cards; systemMedium shows the first four as rows; systemLarge
  shows full details for the first two. Each instance exposes ordered First–Fourth
  account slots. With no explicit configuration, accounts with quota windows sort
  first, metered-only accounts follow, and unavailable accounts are last.
- **Lock-screen** (`AmmoAccount`, accessoryCircular): gauge of "% left" for the
  account's most-consumed window.
- **Activity widget** (`AmmoActivity`, systemSmall/systemMedium): a configurable
  account + limit heatmap. Small shows seven weeks; medium shows thirteen weeks
  beside the current remaining percentage. Tapping opens that exact limit in the
  app's History tab.
- Per-widget account choice through `AppIntentConfiguration`: `SelectAccountIntent`
  chooses one account, while `SelectAccountsIntent` stores the ordered multi-account
  slots. Both hydrate `AccountEntity` values from the App Group snapshot file.
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
