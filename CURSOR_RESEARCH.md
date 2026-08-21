# Cursor Usage Research

**Status:** Implemented with offline contract tests; live on-device verification pending.
**Research date:** 2026-07-17
**Contract stability:** Unofficial and expected to drift.
**Endpoint liveness:** The three endpoints below were probed unauthenticated on
2026-07-17 and all exist (see §Evidence). Response *shapes* are cribbed from a
maintained third-party (CodexBar, MIT) and not yet re-verified against a live
authenticated response from this account.

## Purpose

`SPEC.md` lists Cursor as deferred with a one-line note: "No third-party OAuth;
the dashboard's JSON endpoints are gated on the `WorkosCursorSessionToken`
browser cookie … paste your session cookie onboarding." This document supersedes
that note. The situation is better than the SPEC implies: there **is** a
PKCE-style login flow (the one Cursor's own CLI uses) that is a clean fit for
iOS, so Ammo can get its own refreshable token pair instead of asking the user
to paste a browser cookie.

## Conclusion

Cursor usage is retrievable and a Cursor adapter fits Ammo's existing
architecture with **no server and no cookie-paste**. Recommended approach:

1. **Onboard via Cursor's CLI deep-link PKCE flow.** Generate a PKCE verifier +
   challenge and a random UUID, open `https://cursor.com/loginDeepControl` in
   `ASWebAuthenticationSession`, and **poll** `https://api2.cursor.sh/auth/poll`
   from the app until it returns `{accessToken, refreshToken}`. This is a
   poll-based flow with **no redirect URI and no loopback listener** — simpler
   than the Codex onboarding Ammo already ships.
2. **Fetch usage with a derived first-party cookie.** The usage endpoints are
   gated on the `WorkosCursorSessionToken` cookie, whose value is
   `<userID>::<accessToken>`. Both parts come from the access token itself (the
   token is a JWT; `userID` is derived from its `sub` claim), so the cookie is
   constructed on-device from the PKCE result — nothing is pasted.
3. **Refresh** via Cursor 3.7.27's `POST https://api2.cursor.sh/oauth/token`
   refresh-token grant.

Fallbacks, in declining order of appeal: (a) **paste a `WorkosCursorSessionToken`
cookie** copied from a desktop browser — the SPEC's original idea, kept as a
manual escape hatch; (b) on a future macOS build, read Cursor.app's local auth
from `state.vscdb` (zero-onboarding, macOS-only).

Open items before shipping: confirm the `usage-summary` JSON against a live
authenticated response from real personal and enterprise plans, confirm the
access-token lifetime, and confirm the refresh response/rotation behavior. Ammo now
shows Cursor Models / Other Models included usage plus every reported personal, team, and pooled
on-demand structure without merging their scopes.

## Terminology

- **Cursor** is the product; there is no separate model brand to disambiguate
  (unlike Gemini/Antigravity).
- **`WorkosCursorSessionToken`** is Cursor's first-party web session cookie
  (WorkOS is their auth provider). Its value is not opaque: it is
  `<userID>::<JWT access token>` (the `::` is percent-encoded as `%3A%3A` when
  placed in a cookie header).
- **Plan tiers** seen in `membershipType`: `hobby` (free), `pro`, `team`,
  `enterprise`.

## Evidence from this development machine (2026-07-17)

Checked without copying or displaying any credential values:

- Cursor.app is installed at `/Applications/Cursor.app`.
- Its local auth store exists at
  `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  (a SQLite DB; the desktop app keeps its session token here). Its *contents*
  were deliberately not dumped.
- Unauthenticated endpoint probes:
  - `GET https://cursor.com/api/usage-summary` → **401** (exists; auth required).
  - `GET https://cursor.com/api/auth/me` → **204** (exists; empty when
    unauthenticated).
  - `GET https://api2.cursor.sh/auth/poll?uuid=…&verifier=…` → **404** (this is
    the normal "not authorized yet" response the poll loop treats as "keep
    waiting", not an error).

## Authentication

Cursor offers no third-party OAuth app registration, but its CLI login is a
public PKCE deep-link flow that a native app can drive end to end.

### Onboarding — CLI deep-link PKCE flow (recommended)

Reverse-engineered from Cursor's CLI and reproduced by multiple MIT/OSS projects
(`pi-cursor-provider`, `opencode-cursor`).

1. **PKCE + UUID.** Cursor 3.7.27 generates a verifier from 32 random bytes;
   Ammo's existing RFC 7636-compliant `PKCE` helper is accepted by the same flow.
   `challenge` = base64url(SHA-256(verifier)); `uuid` = a random UUID.
2. **Open the login URL** in `ASWebAuthenticationSession` / `SFSafariViewController`:

   ```
   https://cursor.com/loginDeepControl
     ?challenge=<base64url(SHA256(verifier))>
     &uuid=<random uuid>
     &mode=login
     &supportsSelectedTeamLogin=true
   ```

   The user signs in and clicks "Yes, Log In". There is **no redirect back to the
   app** — the app learns the result by polling.
3. **Poll** until the token is issued. Cursor 3.7.27 polls every 500 ms for 30
   attempts; Ammo keeps that cadence but allows five minutes for phone sign-in:

   ```
   GET https://api2.cursor.sh/auth/poll?uuid=<uuid>&verifier=<verifier>
   ```

   - `404` → not ready; keep polling.
   - `200` → body `{ "accessToken": "<JWT>", "refreshToken": "…" }`.

4. **Derive the usage cookie** from `accessToken` (see §Building the cookie).

This flow is a *better* fit for iOS than the Codex loopback flow Ammo already
implements: no `NWListener`, no port 1455, no localhost redirect — just poll.

### Building the usage cookie

The usage endpoints authenticate with the `WorkosCursorSessionToken` cookie, not
a bearer header. Its value is assembled on-device:

- `accessToken` is a JWT. Base64url-decode its payload and read `sub` — it looks
  like `auth0|user_ABC123` (or similar). `userID` is the segment **after the last
  `|`** (e.g. `user_ABC123`).
- The cookie header is then:

  ```
  Cookie: WorkosCursorSessionToken=<userID>%3A%3A<accessToken>
  ```

  (`%3A%3A` is `::`.) This is exactly how the desktop app's session cookie is
  shaped, which is why the same value works against the web usage endpoints.

Ammo already has JWT-claim extraction in `CodexProvider.chatGPTAccountID(fromJWT:)`
— the same base64url-payload-decode helper applies here for reading `sub` and
`exp`.

### Token lifetime & refresh

- **Access token** is a JWT; read `exp` for expiry (the reference impls refresh
  5 min early). Exact lifetime not yet pinned down live — **verify on first
  implementation** (mirror the SPEC's Claude/Codex "verify live" caveats).
- **Refresh:**

  ```
  POST https://api2.cursor.sh/oauth/token
  Content-Type: application/json

  {
    "grant_type": "refresh_token",
    "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
    "refresh_token": "<refreshToken>"
  }
  ```

  Returns snake-case OAuth fields. Persist a rotated `refresh_token` immediately;
  current Cursor code uses the new `access_token` as the next refresh credential
  if a distinct refresh token is omitted. This still needs live verification.

### Fallback onboarding — paste a cookie

Keep the SPEC's original idea as a manual escape hatch: user pastes a
`WorkosCursorSessionToken=…` header copied from a logged-in desktop browser
(cursor.com). Stored with `tokensImported = true` and **never refreshed** (same
policy as an imported Codex `auth.json`), since a pasted cookie has no companion
refresh token. Also accepts the older cookie names
`__Secure-next-auth.session-token` / `next-auth.session-token`.

### Fallback (macOS only) — Cursor.app local auth

For the future `MenuBarExtra` build: read `state.vscdb`
(`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`), pull the
stored access token, derive the cookie exactly as above → zero-onboarding usage.
Out of scope for iOS.

## Usage contract

### Primary endpoint — modern (token/dollar-based) plans

```
GET https://cursor.com/api/usage-summary
Cookie: WorkosCursorSessionToken=<userID>%3A%3A<accessToken>
Accept: application/json
```

Response (fields Ammo would consume; **all monetary values are in cents**):

```jsonc
{
  "billingCycleStart": "2026-07-01T00:00:00.000Z",
  "billingCycleEnd":   "2026-08-01T00:00:00.000Z",   // → window reset
  "membershipType": "pro",                            // → plan
  "isUnlimited": false,
  "individualUsage": {
    "plan": {
      "used": 2000,            // cents  ($20.00 used)
      "limit": 2000,           // cents  ($20.00 included)
      "remaining": 0,
      "autoPercentUsed":  0.36,   // ALREADY a percent (0.36 means 0.36%)
      "apiPercentUsed":   12.0,
      "totalPercentUsed": 41.0,   // prefer this for the headline "% used"
      "breakdown": { "included": 2000, "bonus": 0, "total": 2000 }
    },
    "onDemand": { "enabled": true, "used": 550, "limit": 5000, "remaining": 4450 },
    "overall":  { /* enterprise/team personal cap, cents; present when no `plan` */ }
  },
  "teamUsage": {
    "onDemand": { /* cents */ },
    "pooled":   { /* shared team/enterprise pool, cents */ }
  }
}
```

Two identity/legacy companions, fetched alongside:

```
GET https://cursor.com/api/auth/me            → { email, name, sub, ... }  (account identity)
GET https://cursor.com/api/usage?user=<sub>   → legacy request-count plans (see below)
```

### Secondary endpoint — legacy request-based plans

Older plans meter **requests**, not dollars. Fetch only if `auth/me` yields a
`sub`; tolerate failure (not all plans expose it):

```jsonc
// GET https://cursor.com/api/usage?user=<sub>
{
  "gpt-4": { "numRequests": 123, "numRequestsTotal": 123, "maxRequestUsage": 500 },
  "startOfMonth": "2026-07-01T…"
}
```

Map `numRequestsTotal / maxRequestUsage` → a percent window.

## Mapping to Ammo's normalized model

`ProviderID.cursor` already exists in `Models.swift`. Implemented
`CursorProvider.fetchUsage` → `UsageSnapshot`:

| UsageSnapshot field             | Source                                                      |
|---------------------------------|-------------------------------------------------------------|
| `plan`                          | `membershipType` (`pro` / `hobby` / `team` / `enterprise`) |
| `windows[]` "Cursor Models"     | `plan.autoPercentUsed` (shared first-party pool: Grok, Composer, …) |
| `windows[]` "Other Models"      | `plan.apiPercentUsed` (third-party, API-priced models)      |
| both windows' `kind`            | `.monthly`                                                  |
| both windows' `resetsAt`        | `billingCycleEnd`                                           |
| `onDemand[]` personal           | `individualUsage.onDemand` (cents → USD)                    |
| `onDemand[]` personal allocation| `individualUsage.overall` (cents → USD)                     |
| `onDemand[]` team               | `teamUsage.onDemand` (cents → USD)                          |
| `onDemand[]` organization pool  | `teamUsage.pooled` (cents → USD)                            |

`totalPercentUsed`, monetary plan fields, and legacy request counts remain outside
the On-demand surface. Every present on-demand block is mapped independently,
including disabled blocks, and uses `billingCycleStart` / `billingCycleEnd` as its
period boundary. Compact widgets continue to show included Cursor Models / Other Models usage; the
app's dedicated On-demand tab owns monetary presentation.

**Gotchas to encode as tests/fixtures:**

1. **Percent fields are already percents**, even when fractional below 1.0
   (`0.36` = 0.36%, which the dashboard rounds to 0%). Do **not** multiply by 100.
2. **`billingCycleEnd` uses ISO 8601 with fractional seconds** — same parsing
   hazard the SPEC flags for Claude; strip to milliseconds or use
   `ISO8601DateFormatter` with `.withFractionalSeconds`.
3. **Money is in cents.** Convert `used`, `limit`, and `remaining` to major USD
   units exactly once. API percentage means Cursor's included API allowance; it is
   not the same as any `onDemand` block.
4. **Enterprise scopes stay distinct.** `individualUsage.overall`,
   `teamUsage.onDemand`, and `teamUsage.pooled` must retain stable, different IDs so
   the UI and future notification detector never attribute shared spend to a person.

## Adapter shape (sketch — matches `CodexProvider`)

A `CursorProvider: UsageProvider` would mirror the Codex adapter closely, since
both use bearer/cookie auth + JWT-claim extraction + a token-refresh POST:

- `fetchUsage(tokens:)` — build the cookie from `tokens.accessToken` + `sub`,
  `GET /api/usage-summary`, parse both included pools and every on-demand scope in the
  table above.
- `refresh(tokens:)` — `POST …/oauth/token` with the refresh-token JSON grant,
  persist rotation.
- `authorizationRequestURL(pkce:uuid:)` + `pollForTokens(uuid:verifier:)` — the
  deep-link + poll onboarding (new relative to Claude/Codex, which redirect).

`OAuthTokens` already carries `accessToken` / `refreshToken` / `expiresAt`; the
derived `userID` can ride in the existing `accountID` field (currently a
Codex-only ChatGPT id) or be recomputed from the JWT on each fetch.

## Re-deriving the contract (when it drifts)

1. **Cheapest:** CodexBar's `docs/cursor.md` and
   `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift` (MIT,
   actively maintained) — the source of most of this document.
2. **Onboarding flow:** inspect the installed Cursor bundle for the current
   `loginDeepControl` + `auth/poll` + `/oauth/token` contract, then compare with
   maintained open-source implementations.
3. **Live capture:** log into cursor.com in a browser, open devtools → Network,
   load the dashboard usage tab, and inspect the `usage-summary` / `auth/me`
   requests and responses; or replay the `WorkosCursorSessionToken` cookie with
   `curl` against the endpoints above.
4. Update this doc, the adapter, and test fixtures together, and re-date-stamp.

## Sources

- [CodexBar `docs/cursor.md`](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md)
  and `CursorStatusProbe.swift` (MIT) — endpoints, response shapes, cookie format.
- [`ndraiman/pi-cursor-provider` `auth.ts`](https://github.com/ndraiman/pi-cursor-provider/blob/main/auth.ts)
  — the PKCE deep-link + poll + refresh flow.
- [Cursor CLI authentication docs](https://cursor.com/docs/cli/reference/authentication)
  — confirms browser login + `NO_OPEN_BROWSER` manual-URL mode.
- [Cursor APIs overview](https://cursor.com/docs/api) — confirms the *official*
  APIs are team/enterprise-only, i.e. there is no sanctioned personal-usage API.
