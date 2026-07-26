# Antigravity Usage Research

**Status:** Research complete; no implementation has been attempted.
**Research date:** 2026-07-17
**Contract stability:** Unofficial and expected to drift.

## Purpose

Ammo was always intended to include Antigravity because Antigravity CLI is used
headlessly in an automated pipeline. The useful number is therefore the quota of
the Google account running that pipeline, not token counts from an interactive
Gemini chat session.

This document records the available usage surfaces, the likely integration
contract, authentication constraints, policy risk, and the validation required
before any provider code is written.

## Conclusion

Antigravity usage appears technically retrievable, including while the desktop
IDE is closed. There are two plausible architectures:

1. **Direct iOS OAuth and remote quota requests.** This best matches Ammo's
   existing no-server architecture, but relies on private Google endpoints,
   unresolved mobile OAuth details, and a meaningful account-policy risk.
2. **A Mac-side companion/exporter.** This asks the already-authenticated `agy`
   process for quota and syncs only a normalized snapshot to the phone. It keeps
   Google credentials out of Ammo, but introduces a Mac dependency and a sync
   mechanism.

For a personal, side-loaded build, the direct route is worth a narrow proof of
concept. It should not be treated as a promised public feature until authentication,
quota fidelity, and policy questions are resolved. The Mac-side route is the
fallback if direct mobile OAuth is rejected or considered too risky.

## Terminology and product direction

- **Gemini** is the model family/brand.
- **Antigravity** is the current agent product and CLI (`agy`) whose quota Ammo
  needs to display.
- The older Gemini CLI OAuth quota integration is not the right long-term target.
  Google's current Gemini Code Assist quota documentation says that, beginning
  2026-06-18, individual, Google AI Pro, and Google AI Ultra users should migrate
  from Gemini CLI/Code Assist to Antigravity.
- Antigravity's documented `/usage` command (alias `/quota`) refreshes quota from
  the backend and displays its Model Quotas panel.

## Evidence from this development machine

The following was checked without copying or displaying credential values:

- Antigravity CLI is installed at `~/.local/bin/agy`.
- The installed version on 2026-07-17 was `1.1.3`.
- Its application data is under `~/.gemini/antigravity-cli`.
- Recent CLI logs showed successful consumer OAuth authentication and headless
  sessions. The account email is deliberately omitted from this document.
- Gemini CLI `0.45.2` is also installed, with `oauth-personal` selected, but its
  cached OAuth credential was expired. This reinforces that the Antigravity
  surface, not the legacy Gemini surface, is the relevant target.
- Antigravity's official CLI documentation says authentication is stored in the
  operating system's secure keyring (Apple Keychain on macOS), rather than in an
  ordinary token JSON file suitable for importing into Ammo.

## What Antigravity exposes

### Official user-facing surface

Antigravity documents quota through `/usage` or `/quota`. Current plan
documentation describes:

- a shared Gemini-model quota pool;
- a separate constrained pool for third-party models where available;
- five-hour refreshes for applicable paid tiers;
- a binding weekly limit;
- usage weighted by the amount of agent work, so one prompt is not necessarily
  one fixed unit of quota.

The official surface is a TUI panel, not a documented public quota API.

### Local `agy` quota service

CodexBar's current open-source Antigravity provider documents and implements a
local probe against the HTTPS service embedded in `agy`. It launches or reuses an
authenticated CLI process, discovers its loopback port, and calls:

```text
POST /exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary
POST /exa.language_server_pb.LanguageServerService/GetUserStatus
POST /exa.language_server_pb.LanguageServerService/GetCommandModelConfigs
```

`RetrieveUserQuotaSummary` is the preferred response. In current Antigravity 2.x
payloads it exposes two groups:

- `Gemini Models`
- `Claude and GPT models`

Each group can contain a five-hour/session bucket and a weekly bucket. The local
service is the richest observed source, but it only exists on the Mac running
`agy`; an iPhone cannot call its loopback interface.

### Remote OAuth-backed quota service

CodexBar also demonstrates remote refreshes while the IDE and CLI are closed.
Its current provider calls private Cloud Code Assist endpoints at
`https://cloudcode-pa.googleapis.com`:

```text
POST /v1internal:loadCodeAssist
POST /v1internal:onboardUser
POST /v1internal:fetchAvailableModels
POST /v1internal:retrieveUserQuota
POST /v1internal:retrieveUserQuotaSummary
```

Requests use a Google OAuth bearer token with the `cloud-platform` and
`userinfo.email` scopes. The observed flow is:

1. Call `loadCodeAssist` with Antigravity metadata to discover plan/tier and a
   Cloud AI Companion project.
2. If the account has no project yet, call `onboardUser`, then poll
   `loadCodeAssist` until the project appears.
3. Fetch quota-bearing models with `fetchAvailableModels`.
4. Use `retrieveUserQuota` as a fallback and to verify suspicious responses in
   which every model appears to have 100% remaining.
5. Prefer quota-summary groups if `retrieveUserQuotaSummary` returns the richer
   Antigravity shape.

The remote responses can be less complete than the local `agy` response. Some
accounts expose only model buckets or model availability, and some deny the
quota endpoint entirely. A successful HTTP response must therefore not be
treated automatically as authoritative usage.

## Normalized Ammo representation

When the rich quota summary exists, it maps naturally to four Ammo windows:

| Antigravity group | Antigravity bucket | Ammo label | Ammo kind |
| --- | --- | --- | --- |
| Gemini Models | five-hour/session | Gemini 5-hour | `session` |
| Gemini Models | weekly | Gemini weekly | `weekly` |
| Claude and GPT models | five-hour/session | Claude/GPT 5-hour | `session` |
| Claude and GPT models | weekly | Claude/GPT weekly | `weekly` |

`remainingFraction` must be converted to Ammo's normalized value as
`usedPercent = 100 - remainingFraction * 100`. Reset timestamps are ISO-8601.

If only model buckets are returned, the UI should avoid pretending that each raw
model is an independent allowance. Current evidence says multiple models collapse
into shared Gemini and Claude/GPT pools. A defensible fallback is to choose the
most constrained known text-model bucket in each pool and clearly label the
snapshot as limited-detail data.

Ammo's existing `UsageSnapshot.windows` model can already hold these windows; the
research found no need for a new top-level usage model.

## Authentication findings

### Do not import the pipeline's credential

Ammo should not extract or import the refresh token used by `agy`. The phone should
receive its own token grant for the same Google account, so refreshing Ammo cannot
damage the pipeline's signed-in state. This follows the same isolation principle
already used by Ammo's Codex onboarding.

### Antigravity OAuth client coupling

CodexBar does not register an independent Google client. It discovers Antigravity's
OAuth client ID and client secret from an installed Antigravity application, then
uses Google's installed-application authorization-code flow.

That creates an unresolved iOS problem:

- The iPhone has no Antigravity application bundle from which to discover the
  client configuration.
- Embedding extracted Antigravity client values would be brittle and would tie
  Ammo to an implementation detail owned by Google.
- Registering Ammo's own Google iOS OAuth client would provide the correct mobile
  redirect scheme, but it is not yet proven that the private Cloud Code Assist
  endpoints will accept tokens issued to an unrelated client.

### Redirect handling

CodexBar's macOS login uses an HTTP listener on a random loopback port. Ammo already
has a loopback listener for Codex, but Google explicitly marks loopback redirects
as deprecated for iOS OAuth client types. A proper iOS OAuth client and custom URL
scheme is the supported mobile shape. Reusing a desktop client with a loopback
redirect on iPhone might work in a personal build, but it is not a stable public
design.

### Storage and refresh

If direct OAuth is validated:

- access token, refresh token, expiration, account identity, and discovered
  project ID belong in the iOS Keychain;
- refreshed credentials must be persisted before quota fetching continues;
- a 401 should allow one refresh-and-retry;
- a 403 from a quota endpoint should be surfaced as "limits unavailable," not as
  zero usage;
- no credential material should enter the App Group or widget extension.

## Architecture options

| Option | Advantages | Costs and risks |
| --- | --- | --- |
| Direct iOS OAuth | No Mac dependency; background refresh works like Claude and Codex; no server | Private API; unresolved OAuth client/redirect; policy risk; remote data may be incomplete |
| Mac companion plus snapshot sync | Reuses the exact `agy` account and richer local quota summary; Google tokens remain in the official client | Requires a running Mac, scheduled probe, and iCloud/other snapshot transport |
| Manual `/usage` inspection | Official and lowest-risk | Does not satisfy the widget or automation goal |

A Mac companion should sync only normalized percentages, reset times, plan label,
and fetch time. It should never sync OAuth tokens or raw Antigravity responses.

## Policy and account risk

Google's Antigravity FAQ says that using an Antigravity login with third-party
software, tools, or services violates its Terms of Service and may result in
suspension or termination. The FAQ discusses using the login to access Antigravity,
not specifically a read-only quota viewer, so it does not conclusively classify
Ammo. Nevertheless, a direct private-API integration is close enough to that
boundary to treat the risk as real.

Consequences for Ammo:

- Do not present this as an official Google integration.
- Keep the provider explicitly experimental if it is built.
- Do not promise it in a public binary until the policy interpretation is
  acceptable.
- Prefer a personal source build and an independent on-device grant during the
  proof stage.
- If account safety is the priority, use the Mac-side snapshot design or retain
  manual `/usage` rather than sending private API requests from Ammo.

## Required proof before implementation

No production UI or provider adapter should be built before a narrow proof answers
these questions:

1. Can an iPhone obtain an independent Google token without importing `agy`'s
   credential?
2. Which OAuth client type and redirect mechanism succeeds on a physical iPhone?
3. Does `loadCodeAssist` accept that token and identify the expected plan/project?
4. Which quota endpoint is permitted for this account?
5. Does the remote result match `agy /usage` at the same moment?
6. After one normal pipeline run, does the corresponding Ammo bucket decrease?
7. Do five-hour and weekly reset times match the official Antigravity panel?
8. Can the phone refresh its token without changing or invalidating the pipeline's
   login?
9. Does a background refresh return the same data while the Mac and `agy` are
   closed?
10. How does the provider behave when Google returns model availability without
    authoritative remaining fractions?

The proof should log only endpoint name, status code, decoded field names, and
normalized values. Tokens and raw identity claims must be redacted.

## Acceptance criteria for a future provider

- The displayed Gemini quota tracks the account used by the headless pipeline.
- Rich responses show the four session/weekly windows without duplicating shared
  model pools.
- Limited responses are labeled honestly rather than rendered as exact limits.
- A response containing no authoritative usage does not render as 0% used or
  100% remaining.
- Ammo's token is independently issued and stored only in its Keychain.
- Removing the Ammo account deletes Ammo's credential without signing `agy` out.
- Widgets continue to read cached snapshots only.
- Offline, expired-token, 401, 403, and schema-drift cases have fixture coverage.
- The provider contract and verification date are recorded in `SPEC.md` once the
  proof succeeds.

## Expected repository touch points if approved later

This is an orientation list, not an implementation plan or authorization to edit
these files:

- `Sources/UsageKit/AntigravityProvider.swift` — remote contract and mapping.
- `Sources/UsageKit/Models.swift` — only if project metadata cannot fit the current
  credential model cleanly.
- `Apps/iOS/Ammo/Onboarding/` — independent Google sign-in.
- `Apps/iOS/Ammo/Models/AccountStore.swift` — provider registration.
- `Apps/iOS/Ammo/UI/ContentView.swift` — Add Antigravity entry.
- `Apps/iOS/Shared/ProviderLogo.swift` and assets — provider presentation.
- `Tests/UsageKitTests/` — offline response and failure fixtures.
- `SPEC.md` — verified, date-stamped contract after live validation.

## Sources

All web sources were checked on 2026-07-17.

- [Google Antigravity plans](https://antigravity.google/docs/plans)
- [Antigravity CLI Model Quotas (`/usage`)](https://antigravity.google/docs/cli/commands/usage)
- [Antigravity CLI installation and authentication](https://antigravity.google/docs/cli-install)
- [Antigravity FAQ and third-party-login warning](https://antigravity.google/docs/faq)
- [Gemini Code Assist quotas and Antigravity migration notice](https://developers.google.com/gemini-code-assist/resources/quotas)
- [Google OAuth for native apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [CodexBar Antigravity provider notes at inspected commit](https://github.com/steipete/CodexBar/blob/0397529ae6e5d86df78cca7c18362fb720572c50/docs/antigravity.md)
- [CodexBar remote Antigravity fetcher at inspected commit](https://github.com/steipete/CodexBar/blob/0397529ae6e5d86df78cca7c18362fb720572c50/Sources/CodexBarCore/Providers/Antigravity/AntigravityRemoteUsageFetcher.swift)
- [CodexBar local Antigravity probe at inspected commit](https://github.com/steipete/CodexBar/blob/0397529ae6e5d86df78cca7c18362fb720572c50/Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift)
- [CodexBar OAuth login flow at inspected commit](https://github.com/steipete/CodexBar/blob/0397529ae6e5d86df78cca7c18362fb720572c50/Sources/CodexBar/Providers/Antigravity/AntigravityLoginRunner.swift)
