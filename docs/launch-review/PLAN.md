# Ammo launch remediation plan

Derived from `docs/launch-review/app-review.md` and `docs/launch-review/red-team.md`.

**This file is the source of truth.** It is written to be picked up cold. An orchestrator
taking over mid-flight should read, in this order:

1. This file's **Status ledger** (below).
2. `gh pr list --repo Brandon1138/ammo --state all --limit 30`
3. `git branch -r | grep launch-`
4. Linear: Mikoshi team, **Ammo** project (`c1e6ebbd-5732-4625-ab54-d2774d797fcf`).

A row is only `done` when its PR is **merged** and the ledger says so. Worker self-reports
are not evidence — see *Orchestrator duties*.

---

## Ground truth established 2026-08-01 (verified, not inferred)

These were checked directly against the tree and the remote. They correct or sharpen the
two review documents.

### G1 — The repository is already public

`github.com/Brandon1138/ammo` is **PUBLIC** (`gh repo view --json isPrivate` → `false`).
`origin/main` already contains:

- `SPEC.md` — including "reverse-engineered" (`:10`, `:343`) and the `mitmproxy`
  re-derivation methodology (`:409-421`)
- `Apps/iOS/Assets/Official/codex-app-icon.png`, `cursor-app-icon.png` — provider app icons
- `Apps/iOS/Scripts/extract-provider-glyphs.py` — whose docstring says the glyphs were
  extracted from those icons
- `CURSOR_RESEARCH.md`, `ANTIGRAVITY_RESEARCH.md`
- **no `LICENSE`**

The review's Tier 3 is framed as "before the repo goes public". That framing is obsolete:
this is live exposure today. Tier 3 is therefore **promoted to run concurrently with
Tier 1**, not after it. It is the only tier whose clock is already running.

### G2 — The launch baseline is not `main`

- `main` == `origin/main`
- `feat/icon-and-branding` is **4 commits ahead** of `main` (through `557e726`,
  "chore: bump build number to 17") and **is pushed** to `origin`
- The working checkout `/Users/brandon/code/personal/ammo` sits on `feat/icon-and-branding`

Every worker must branch from one agreed, pinned SHA. See **Decision D1**.

### G3 — Verification works headlessly, with one trap

```sh
# from repo root — 66 tests, 13 suites, ~1s
swift test

# from Apps/iOS — 43 tests, 9 suites, ~35s
xcodegen && xcodebuild test -project Ammo.xcodeproj -scheme Ammo \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Both pass on `feat/icon-and-branding` as of 2026-08-01.

Three traps that will each burn a worker turn if not stated in the brief:

- **`iPhone 16` does not exist on this machine.** Available simulators are iPhone 17,
  17 Pro, 17 Pro Max, 17e, Air, iPad mini — on iOS 26.5 and 27.0. A worker guessing the
  conventional `iPhone 16` gets a destination error, not a test failure.
- **Do not pass `CODE_SIGNING_ALLOWED=NO`.** It builds, but `RotatedCredentialPersistenceTests`
  (3 tests in `Apps/iOS/AmmoTests/BackgroundRefreshTests.swift`) needs the Keychain access
  group from the entitlements and fails without it. Signing is satisfied locally by
  `DEVELOPMENT_TEAM: JN24JD42L3` in `Apps/iOS/project.yml:21`.
- **`*.xcodeproj` is gitignored**, so `xcodegen` must be run in every fresh worktree
  before `xcodebuild`.

The review's "66 offline tests pass" refers to `swift test` (UsageKit) only. The 43-test
iOS bundle is a **second, separate gate** and both must be green.

### G4 — `DEVELOPMENT_TEAM` relocation is interlocked with the whole plan

Tier 4 recommends moving `DEVELOPMENT_TEAM` out of `project.yml` into a gitignored
`.xcconfig`. Doing that **breaks the 3 Keychain tests in every worker worktree**, because a
gitignored file does not exist in a fresh checkout. This item is therefore sequenced
**last** (L13), after all code work has landed, and must ship with a documented local
`.xcconfig` template.

### G5 — Demo mode may not require `UserDefaults` at all

Both reviewers flagged an interlock: implementing demo mode via `@AppStorage`/`UserDefaults`
*creates* the required-reason API usage that does not exist today, making
`PrivacyInfo.xcprivacy` mandatory (`CA92.1`).

The existing simulator preview harness (`Apps/iOS/Ammo/Models/AccountStore.swift:150-153`)
already keys off **three** triggers — launch arguments, environment variables, and
`UserDefaults` — and only the third is a required-reason API. A reviewer-facing demo toggle
can be an in-memory `@Observable` flag with no persistence at all.

We ship the manifest anyway (it is ~15 lines and a standing Tier-4 should-fix), so this does
not gate L5. But the worker should not be told the interlock is unavoidable. See **D3**.

### G6 — Item 2.2 is more certain than described, and the stated fix will not work

`Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:50` tells the user, in the app's own
footer: *"Imported tokens are never refreshed by Ammo — that could log out your desktop CLI
— so you'll need to re-import when they expire."*

So for pasted Codex accounts, reaching the `.authentication` dead end is **certain**, not
incidental. And `UsageComponents.swift:324` excluding `.authentication` from
`canRetryImmediately` is *correct* — a retry genuinely cannot succeed. The fix is not to
enable retry. It is to give the `.authentication` notice a **Re-import / Re-authenticate**
action that reopens the relevant onboarding sheet.

### G7 — Worktree namespace is dirty

13 worktrees exist under `/Users/brandon/code/personal/ammo-worktrees/`, several 5+ commits
behind, plus one open draft PR (#7, `codex/release-history-launch-hardening`). Fan-out needs
a clean namespace or worktree adds will collide. See **D5**.

---

## Decisions required before dispatch

| ID | Decision | Why it blocks | Recommendation |
|----|----------|---------------|----------------|
| **D1** | Base branch for all workers | 4 unmerged commits including build 17; branching from `main` means every PR is missing the icon work and conflicts on merge | Land `feat/icon-and-branding` → `main` first (Brandon merges), pin that SHA, branch everything from it |
| **D2** | `Assets/Official/*` in git history | Deleting from HEAD leaves the provider app icons in the public history of a public repo | Delete from HEAD now (L4); treat history rewrite + force-push as a separate, explicit call |
| **D3** | Demo-mode persistence | Determines whether `PrivacyInfo.xcprivacy` is load-bearing or merely prudent | In-memory `@Observable` flag, **and** ship the manifest anyway |
| **D4** | Cursor in 0.1.0 | `CURSOR_RESEARCH.md:2-9` says the contracts were cribbed from CodexBar and never re-verified live | Ship 0.1.0 without Cursor unless Brandon can verify live before submission |
| **D5** | Stale worktree pruning | 13 worktrees, namespace collisions | Prune all except those holding unlanded work — needs Brandon's confirmation per worktree |

---

## Wave structure

Waves are cut on **file-domain disjointness**, not on topic. Two workers never hold the same
file. Where topics collide on a file, they are folded into one worker rather than serialized,
unless the combined brief would be too large.

### File-domain map

| Domain | Files | Owner |
|--------|-------|-------|
| `Apps/iOS/Shared/` (persistence) | `AccountDeletionStore`, `KeychainStore`, `RefreshLedger`, `UsageHistoryStore`, `SharedStore`, `UsageRefreshCoordinator` | **L1 exclusively** |
| `Sources/UsageKit/` | `CodexProvider`, `ClaudeProvider`, `CursorProvider` | L2, L10 |
| Root docs | `SPEC.md`, `README.md`, `LICENSE`, `*_RESEARCH.md` | L3 |
| Vendor assets | `ProviderAssets.xcassets/`, `Scripts/`, `Assets/Official/` | L4 |
| `Apps/iOS/Ammo/UI/` + `Models/` | `ContentView`, `AccountStore` | L5, then L7 |
| `Apps/iOS/Ammo/Onboarding/` | `LoopbackServer`, all three onboarding views | **L8 exclusively** |
| `Apps/iOS/Shared/UsageComponents.swift` | auth-notice copy + actions | L7 |

---

### Wave 0 — Ground truth and unblocking (no code)

| ID | Task | Actor |
|----|------|-------|
| **W0.1** | Resolve D1–D5 | Brandon |
| **W0.2** | Land `feat/icon-and-branding` → `main`, pin SHA into this file | Brandon merges, Orc records |
| **W0.3** | Prune stale worktrees (per D5), commit this file to `main` | Orc |
| **W0.4** | Create Linear issues L1–L13 in MIK/Ammo, link each row below | Orc |
| **S1** | Scout: classify all 22 `AccountDeletionStore.isDeleted` call sites — for each, does `unknown` mean abort or proceed, and what is lost if the choice is wrong | Scout |
| **S2** | Scout: demo-mode surface — every view/widget branch keyed on account presence; behaviour with no Keychain items; how a reviewer reaches the widgets | Scout |
| **S3** | Scout: sweep `origin/main` for public-exposure liabilities **beyond** the six the reviews named | Scout |
| **S4** | Scout: App Store Connect metadata inventory for `TARGETED_DEVICE_FAMILY: "1"` — exact required fields and screenshot dimensions | Scout |

Scouts are read-only and run as one parallel wave. S1 output is a required input to L1's brief.

---

### Wave 1 — Ship-stoppers and live exposure (4 workers, parallel)

| ID | Review item | Scope | Files | Worker |
|----|-------------|-------|-------|--------|
| **L1** | 2.1 credential destruction | Make `isDeleted` return `{active, deleted, unknown}`. Only a positively-read tombstone may authorize deletion. `unknown` aborts the write **without** deleting. Apply S1's per-site policy to all 22 call sites. Add a regression test that a lock failure during `save` does not delete. | `Shared/AccountDeletionStore.swift`, `Shared/KeychainStore.swift`, `Shared/RefreshLedger.swift`, `Shared/UsageHistoryStore.swift`, `Shared/SharedStore.swift`, `Shared/UsageRefreshCoordinator.swift`, `Ammo/Models/AccountStore.swift:65-77`, `AmmoTests/AccountDeletionTests.swift`, `AmmoTests/BackgroundRefreshTests.swift` | **Claude `opus`, effort `xhigh`** |
| **L2** | 4.1 + 4.4 | Replace `User-Agent: codex-cli` with `Ammo/0.1.0`; enforce the OAuth `state` round-trip in `ClaudeProvider` | `Sources/UsageKit/CodexProvider.swift`, `Sources/UsageKit/ClaudeProvider.swift`, `Tests/UsageKitTests/` | Codex `gpt-5.6-luna`, `high` |
| **L3** | Tier 3 docs | Add `LICENSE` (Apache-2.0); fix `SPEC.md:43` widget claim and `SPEC.md:17-18` Keychain class; document that `…ThisDeviceOnly` means accounts do **not** restore to a new iPhone; neutralize "reverse-engineered" / "private dashboard summary" / the `mitmproxy` recipe; add a "not affiliated" statement **in the binary**, not only in docs | `LICENSE`, `SPEC.md`, `README.md`, `CURSOR_RESEARCH.md`, `ANTIGRAVITY_RESEARCH.md` | Codex `gpt-5.6-luna`, `xhigh` |
| **L4** | Tier 3 assets | Delete `Apps/iOS/Assets/Official/`; rewrite `extract-provider-glyphs.py` docstring and provenance; produce a brand-kit re-sourcing checklist for Brandon (the worker cannot fetch official brand assets itself) | `Apps/iOS/Assets/Official/*`, `Apps/iOS/Scripts/extract-provider-glyphs.py`, `Apps/iOS/Shared/ProviderAssets.xcassets/**` | Codex `gpt-5.6-luna`, `xhigh` |

L1 holds `Apps/iOS/Shared/` alone. L3's "not affiliated" string lands in a view file — it must
be added to a file **not** held by L5, or deferred into L5. Assign it to `SPEC.md`/`README.md`
plus a single new `About` string constant.

---

### Wave 2 — Make the app reviewable (depends on L1 merging)

| ID | Review item | Scope | Files | Worker |
|----|-------------|-------|-------|--------|
| **L5** | 1.1 + 2.6 + 4.3 | Lift the existing demo fixtures (`AccountStore.swift:213-390`) out of `#if targetEnvironment(simulator)`; add an `isDemoMode` flag and a "See a demo" button to the empty state (`ContentView.swift:177-187`); label it visibly as sample data; keep it fully offline. Add a confirmation dialog to "Remove Account" (`ContentView.swift:270`). Add `PrivacyInfo.xcprivacy` to both targets. | `Ammo/Models/AccountStore.swift`, `Ammo/UI/ContentView.swift`, new `Ammo/Models/DemoData.swift`, `Apps/iOS/project.yml`, 2× `PrivacyInfo.xcprivacy` | Codex `gpt-5.6-luna`, `max` |
| **L7** | 2.2 | Give the `.authentication` notice a Re-import / Re-authenticate action that reopens the right onboarding sheet. Do **not** enable retry — see G6. | `Shared/UsageComponents.swift`, `Ammo/UI/ContentView.swift` | Codex `gpt-5.6-luna`, `high` |

L7 runs after L5 merges — both touch `ContentView.swift`.

---

### Wave 3 — Onboarding hardening (parallel with Wave 2, disjoint directory)

| ID | Review item | Scope | Files | Worker |
|----|-------------|-------|-------|--------|
| **L8** | 2.3 + 2.4 + 2.5 | Tear the loopback listener down on `scenePhase` change, not only in the awaited flow's `defer`; detect that another process owns port 1455 by actually reading `boundPort` and surfacing it; replace the plain `TextEditor` paste with a snapshot-protected field, clear `pastedJSON` on dismiss, and avoid the general pasteboard round-trip | `Ammo/Onboarding/LoopbackServer.swift`, `Ammo/Onboarding/{Claude,Codex,Cursor}OnboardingView.swift`, `Ammo/AmmoApp.swift`, `AmmoTests/SignInFlowTests.swift` | Codex `gpt-5.6-luna`, `max` |

Folded rather than split: 2.3 and 2.4 both edit `CodexOnboardingView.swift`, and 2.4/2.5 both
edit `LoopbackServer.swift`. One worker owns the whole `Onboarding/` directory.

---

### Wave 4 — Risk reduction

| ID | Review item | Scope | Worker |
|----|-------------|-------|--------|
| **L10** | 4.2 + 4.5 | Document the Cursor PKCE-verifier-in-query-string behaviour and add backoff to the ~600-poll sign-in loop; prepare a live re-verification harness for the three provider contracts. **Live verification itself is a human gate** — needs Brandon's accounts. | Codex `gpt-5.6-luna`, `xhigh` |
| **L11** | 4.6 | State in-app that "Remove Account" does not revoke upstream (~19 days for Anthropic) and link the provider's session page. Do not revoke — it would kill the user's desktop CLI session. | Codex `gpt-5.6-luna`, `high` |
| **L13** | 4.7 | Move `DEVELOPMENT_TEAM` to a gitignored `.xcconfig` **with a committed template**. Sequenced last — see G4. | Codex `gpt-5.6-luna`, `high` |

---

### Wave 5 — Submission assembly

| ID | Review item | Scope | Actor |
|----|-------------|-------|-------|
| **L12** | 0.1 | Draft the privacy policy and add it as a page in the `ammo-landing` repo | Codex `gpt-5.6-luna`, `xhigh` |
| **L14** | 0.2 + 0.3 | Draft all store metadata from `app-review.md:174-190`, the App Privacy answer sheet (**Data Not Collected** across the board; do **not** declare "User ID"), and the Review Notes from `app-review.md:752-816` (two bracketed placeholders to fill) | Codex `gpt-5.6-luna`, `xhigh` |
| **L15** | 0.3 | Capture App Store screenshots by driving the simulator against demo mode — automatable once L5 lands (`xcodebuild` + `simctl`) | Codex `gpt-5.6-luna`, `high` |
| **H1** | 0.4 | **Archive check** — confirm the app icon reaches the binary. Requires signing and Xcode. | **Brandon only** |
| **H2** | 0.1 | Deploy the privacy policy, obtain the public URL | **Brandon only** |
| **H3** | 0.2 | Enter the App Privacy answers in App Store Connect | **Brandon only** |
| **H4** | — | Re-verify all three provider contracts against live accounts | **Brandon only** |
| **H5** | — | Merge every PR (required `verify` check; no auto-merge) | **Brandon only** |

---

## Universal worker contract

Every worker brief includes verbatim:

- **Worktree**: `/Users/brandon/code/personal/ammo-worktrees/launch-<id>-<slug>`,
  branch `codex/launch-<id>-<slug>` (or `claude/…`), created from the pinned base SHA.
- **Verify before reporting done** — both gates, both green:
  ```sh
  swift test
  cd Apps/iOS && xcodegen && xcodebuild test -project Ammo.xcodeproj -scheme Ammo \
    -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
  Do **not** add `CODE_SIGNING_ALLOWED=NO`. Do **not** use `iPhone 16`. (See G3.)
- **File allowlist**: touch only the files listed for your ID. If the change requires a file
  outside it, **stop and signal** — do not widen scope.
- **Deliver**: commit, push, open a PR against the pinned base. **Do not merge.**
- **Report**: files changed, the tail of both test runs, and the PR URL.

## Orchestrator duties

Workers have historically reported "done" with a dirty tree. After every wave, for each ID:

```sh
git -C <worktree> status --short          # must be empty
git -C <worktree> log --oneline <base>..HEAD
gh pr view <n> --repo Brandon1138/ammo --json isDraft,mergeable,statusCheckRollup
```

Only then move the ledger row to `review`. Merging is Brandon's step.

If a `cyberdeck_workers_wait` call fails outright, worker state is **unknown, not failed**.
Re-wait the same `sessionId`/`completionTarget`, or call `cyberdeck_threads_list`, before
starting any replacement. A result marked `retrieval: "replay"` proves the work already ran.

---

## Status ledger

Legend: `blocked` · `ready` · `dispatched` · `review` · `merged` · `done`

| ID | Tier | Title | Branch | PR | Status | Blocked on |
|----|------|-------|--------|----|--------|------------|
| W0.1 | — | Resolve D1–D5 | — | — | `blocked` | Brandon |
| W0.2 | — | Land icon branch, pin base SHA | — | — | `blocked` | D1 |
| W0.3 | — | Prune worktrees, commit this file | — | — | `blocked` | D5 |
| W0.4 | — | Create Linear issues | — | — | `blocked` | W0.1 |
| S1 | — | Scout: `isDeleted` call-site policy | — | — | `ready` | — |
| S2 | — | Scout: demo-mode surface | — | — | `ready` | — |
| S3 | — | Scout: public-exposure sweep | — | — | `ready` | — |
| S4 | — | Scout: ASC metadata inventory | — | — | `ready` | — |
| L1 | 2 | Credential destruction → tri-state | — | — | `blocked` | W0.2, S1 |
| L2 | 4 | User-Agent + Claude `state` | — | — | `blocked` | W0.2 |
| L3 | 3 | LICENSE, SPEC corrections, language | — | — | `blocked` | W0.2 |
| L4 | 3 | Vendor asset provenance | — | — | `blocked` | W0.2, D2 |
| L5 | 1 | Demo mode + remove-confirm + manifest | — | — | `blocked` | L1, S2, D3 |
| L7 | 2 | Auth-error recovery action | — | — | `blocked` | L5 |
| L8 | 2 | Onboarding: teardown, port, paste | — | — | `blocked` | W0.2 |
| L10 | 4 | Cursor backoff + contract harness | — | — | `blocked` | W0.2, D4 |
| L11 | 4 | Upstream-revocation disclosure | — | — | `blocked` | L5 |
| L12 | 0 | Privacy policy draft | — | — | `blocked` | W0.1 |
| L13 | 4 | `DEVELOPMENT_TEAM` → `.xcconfig` | — | — | `blocked` | all code work |
| L14 | 0 | Store metadata + Review Notes | — | — | `blocked` | W0.1 |
| L15 | 0 | Screenshots via demo mode | — | — | `blocked` | L5 |
| H1 | 0 | Archive icon check | — | — | `blocked` | Brandon |
| H2 | 0 | Deploy privacy policy | — | — | `blocked` | L12 |
| H3 | 0 | App Privacy answers in ASC | — | — | `blocked` | L14 |
| H4 | — | Live provider contract re-verification | — | — | `blocked` | Brandon |
| H5 | — | Merge all PRs | — | — | `blocked` | Brandon |
