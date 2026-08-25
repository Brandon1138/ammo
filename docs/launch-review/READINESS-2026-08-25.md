# Ammo App Store readiness audit — 2026-08-25

**Scope.** Re-verdicts every row of `docs/launch-review/PLAN.md`'s status ledger and every
decision D1–D5 against the tree as it stands on `claude/mik-166-readiness-audit`
(`main` @ `51b9b9b`). Review-only: nothing outside this file was changed.

**Method.** Every verdict below is backed by a `grep`, a file-presence check, `git log`, or a
test run performed on 2026-08-25. The ledger's own status column was **not** used as
evidence — it was last reconciled against ground truth dated 2026-08-01 and every row in it
still reads `blocked` or `ready`, which is demonstrably wrong.

**Baseline facts re-established today**

| Fact | Evidence |
|---|---|
| Repository is still **public** | `gh repo view Brandon1138/ammo --json isPrivate` → `{"isPrivate":false,"visibility":"PUBLIC"}` |
| Version 0.1.0, build 17 | `Apps/iOS/project.yml:18-19` (`MARKETING_VERSION: 0.1.0`, `CURRENT_PROJECT_VERSION: 17`) |
| `feat/icon-and-branding` is merged | `git merge-base --is-ancestor feat/icon-and-branding main` → true |
| No open PRs | `gh pr list --repo Brandon1138/ammo --state open` → `[]` |
| UsageKit gate green | `swift test` → "Test run with 204 tests in 23 suites passed" |
| Most remediation landed as one squash | `git log --diff-filter=A -- LICENSE NOTICE docs/privacy-policy.md Apps/iOS/Ammo/PrivacyInfo.xcprivacy Apps/iOS/Shared/DemoModeStore.swift` → `e9d1d14` (2026-08-14, "fix: remediate App Store launch review NO-SHIP blockers") |

**Ledger drift note.** The ledger enumerates `L1–L5, L7, L8, L10–L15`. There is no `L6` and
no `L9` row anywhere in `PLAN.md` — the IDs were never allocated. The plan's `launch-<id>`
branch namespace was never used either; the work was tracked as `MIK-nnn` branches instead
(`git branch -a`), which is why the ledger's Branch/PR columns are empty.

---

## 1. Per-row verdicts

Legend: **done** · **open** (includes partially-landed) · **moot** · **superseded**

### Wave 0 — ground truth and unblocking

| ID | Verdict | Evidence |
|---|---|---|
| **W0.1** — Resolve D1–D5 | **superseded** | No decision record exists in the tree. The individual decisions were resolved *de facto* by code that landed (see §D below) rather than by an explicit D1–D5 sign-off, and the dispatch model the decisions gated was abandoned. |
| **W0.2** — Land icon branch, pin base SHA | **done** | `git merge-base --is-ancestor feat/icon-and-branding main` succeeds; build 17 is on `main` at `Apps/iOS/project.yml:19`; the icon itself exists at `Apps/iOS/Ammo/AppIcon.icon` and is wired via `Apps/iOS/project.yml:59` (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`). No SHA was pinned into `PLAN.md`, but the interlock it protected is gone. |
| **W0.3** — Prune worktrees, commit this file | **done** (file half) | `git ls-files docs/launch-review/` lists `PLAN.md`, `app-review.md`, `red-team.md`. Pruning did not happen — `git worktree list` now returns **50** entries across two different roots (`ammo-worktrees/` and `ammo/worktrees/`), up from the 13 the plan recorded. Not App Store-blocking; see D5. |
| **W0.4** — Create Linear issues L1–L13 | **superseded** | No `L*` branches exist. `git branch -a` shows `codex/mik-1xx-*` and `claude/mik-1xx-*` throughout, so issue tracking moved to the MIK numbering. Cannot be verified further without Linear access. |
| **S1** — Scout `isDeleted` call-site policy | **done** | No scout artifact in the tree, but its deliverable is visibly consumed: `Apps/iOS/Shared/AccountDeletionStore.swift:9-18` defines the tri-state and the two distinct policies (`authorizesCredentialDeletion`, `permitsPersistence`), and all 22 call sites are accounted for (`grep -rn "isDeleted\|deletionState" --include='*.swift' Apps Sources Tests` → 22 hits). |
| **S2** — Scout demo-mode surface | **done** | Deliverable consumed: `Apps/iOS/Shared/DemoModeStore.swift`, `Apps/iOS/Ammo/UI/ContentView.swift:161-162,208,319-325`, `Apps/iOS/Shared/SharedStore.swift:141` (widget path), `Apps/iOS/Shared/WidgetInvalidation.swift:11` (`.demoModeChanged`), `Apps/iOS/AmmoTests/DemoModeTests.swift`. |
| **S3** — Public-exposure sweep | **done** | Output is recognisable in `docs/launch-remediation-operator-checklist.md` and in the `NOTICE` file's trademark/attribution block. The sweep did **not** clear the exposure it was scoped to find — see L4. |
| **S4** — ASC metadata inventory | **open** | Nothing in `docs/` enumerates required App Store Connect fields or screenshot dimensions; `grep -rln "keyword\|subtitle\|Review Notes" docs/ *.md` returns only the review documents themselves and the operator checklist, which prescribes actions without listing the field inventory. Branch `claude/mik-167-submission-metadata` exists and is unmerged. |

### Wave 1 — ship-stoppers and live exposure

| ID | Verdict | Evidence |
|---|---|---|
| **L1** — Credential destruction → tri-state | **done** | `Apps/iOS/Shared/AccountDeletionStore.swift:9-18` — `enum Status { active, deleted, unknown }`, `:15` `authorizesCredentialDeletion` is true only for `.deleted`, `:18` `permitsPersistence` only for `.active`. `Apps/iOS/Shared/KeychainStore.swift:33-45` switches on `status(for:timeout:5)` and throws `StatusUnavailableError()` on `.unknown` **without deleting**, keeping the freshly rotated pair. Readers use the non-fail-closed `deletedIDs(timeout:)` (`AccountDeletionStore.swift:91-114`). Regression coverage at `Apps/iOS/AmmoTests/AccountDeletionTests.swift:31` (`#expect(!status.authorizesCredentialDeletion)`). |
| **L2** — User-Agent + Claude `state` | **open** (half landed) | `state` round-trip **is** enforced: `Sources/UsageKit/ClaudeProvider.swift:79` sends `state`, `:86-94` requires it back on `exchangeCode`, `Apps/iOS/Ammo/Onboarding/WebAuth.swift:80` constructs `LoopbackServer(expectedState: pkce.state)`, `:103-106` documents/implements `isCallbackStateValid`, `Apps/iOS/Ammo/Onboarding/LoopbackServer.swift:226-238` drops non-matching callbacks. The User-Agent was **not** changed: `Sources/UsageKit/CodexProvider.swift:30` still sends `"User-Agent": "codex-cli"`. `grep -rn "Ammo/0" --include='*.swift' Sources Apps` → no hits. |
| **L3** — LICENSE, SPEC corrections, language | **open** (mostly landed) | Landed: `LICENSE` exists (**MIT**, not the Apache-2.0 the plan recommended — a deviation, not a defect); `NOTICE:1-7` carries the non-affiliation and trademark statements; `SPEC.md:10` now reads "the provider contracts **observed from authenticated clients**" (no "reverse-engineered" anywhere — `grep -rn "reverse-engineer" SPEC.md README.md` → no hits); `SPEC.md:17-18` states the `…ThisDeviceOnly` non-transfer consequence, echoed in `README.md:11-13`; the widget claim at `SPEC.md:43` is qualified ("may refresh through shared Keychain credentials"). Still open: `SPEC.md:389` and `Sources/UsageKit/CursorProvider.swift:6-7` both still say "**private dashboard summary**"; `SPEC.md:512-523` still publishes the `mitmproxy` re-derivation recipe; and the non-affiliation statement is **not in the binary** — `grep -rni "affiliat\|trademark" --include='*.swift' Apps Sources` returns zero hits, so it lives only in `NOTICE` and `docs/privacy-policy.md:5-7`. |
| **L4** — Vendor asset provenance | **open** | Unchanged and live. `git ls-files Apps/iOS/Assets/` → `Apps/iOS/Assets/Official/codex-app-icon.png`, `Apps/iOS/Assets/Official/cursor-app-icon.png`, both present on disk (615 KB / 27 KB) in a repository `gh` confirms is PUBLIC. `Apps/iOS/Scripts/extract-provider-glyphs.py:2` still reads *"Remove app-icon tiles while preserving the official provider glyph pixels"*, `:12` still points `SOURCES` at `Assets/Official`, and `:121,:126` still name the two icon files. No brand-kit re-sourcing checklist exists in `docs/`. |

### Wave 2 — make the app reviewable

| ID | Verdict | Evidence |
|---|---|---|
| **L5** — Demo mode + remove-confirm + manifest | **open** (demo mode done; two sub-items outstanding) | **Done:** demo mode is real and reachable — `Apps/iOS/Ammo/UI/ContentView.swift:208` `Button("See a demo")` in the empty state, `:161-162` an "Exit Demo" toolbar button, `:319-325` a "Sample data" capsule on every account header, fixtures in `Apps/iOS/Shared/DemoModeStore.swift` (`DemoData`, four `D0000000-…` sample accounts), widget path covered by `Apps/iOS/Shared/SharedStore.swift:141` and `Apps/iOS/Shared/UsageHistoryStore.swift:20`, network suppressed via `Apps/iOS/Ammo/Models/AccountStore.swift:219,242,311`, tests at `Apps/iOS/AmmoTests/DemoModeTests.swift`. Both manifests exist and are byte-identical (`Apps/iOS/Ammo/PrivacyInfo.xcprivacy`, `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy`). **Open (a):** the manifests declare `<key>NSPrivacyAccessedAPITypes</key><array/>` — empty — while the app does use a required-reason API: `Sources/UsageKit/Notifications/NotificationPreferencesStorage.swift:7-16` constructs `UserDefaults(suiteName:)` for the App Group, reached from `Apps/iOS/Ammo/Models/NotificationSettingsModel.swift:20` and `Apps/iOS/Ammo/Services/UsageNotificationService.swift:14`. Apple assigns same-App-Group access reason `1C8F.1`; the `UserDefaults.standard` read at `AccountStore.swift:396` is simulator-only and does not justify `CA92.1` in device binaries. `1C8F.1` is undeclared. **Open (b):** there is no confirmation on the destructive action — `Apps/iOS/Ammo/UI/ContentView.swift:347` calls `store.remove(state.account)` directly, and `grep -n "confirmationDialog\|alert(" Apps/iOS/Ammo/UI/ContentView.swift` returns nothing. |
| **L7** — Auth-error recovery action | **open** (partially superseded) | The `.authentication` notice still renders no action: `Apps/iOS/Shared/UsageComponents.swift:321-324` keeps `canRetryImmediately == false` for `.authentication` (correct per G6), and `:273`, `:292` gate `actionTitle`/`action` on that same flag, so the card has no button at all. The copy at `:350` tells the user to *"Remove and add this \(providerName) account again to resume updates."* That advice is now **wrong**: `Apps/iOS/Ammo/UI/ContentView.swift:340-342` offers "Sign In Again" (`reconnect`), which MIK-156 made identity-preserving, so following the notice destroys history the menu would have kept. Recovery exists; the notice does not point at it. |

### Wave 3 — onboarding hardening

| ID | Verdict | Evidence |
|---|---|---|
| **L8** — Onboarding: teardown, port, paste | **done** | Scene-phase teardown: `Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:92-94` calls `authFlow.cancelForBackground()`, implemented at `Apps/iOS/Ammo/Onboarding/WebAuth.swift:97-99` → `fail()` at `:126` stops the server. Port contention is detected rather than hung on: `Apps/iOS/Ammo/Onboarding/LoopbackServer.swift:102` exposes `boundPort`, and `WebAuth.swift:78` awaits `waitUntilReady(expectedPort: 1455, timeout: 3)`, surfacing `ListenerUnavailableError` / `TimeoutError` before the browser opens. Paste handling: `CodexOnboardingView.swift:59` `.privacySensitive()`, `:88-89` `onDisappear { pastedJSON = "" }`, `:127` `defer { pastedJSON = "" }`; same pattern in `ClaudeOnboardingView.swift:43,88` and `OpenRouterOnboardingView.swift:40,79`. No general-pasteboard round-trip anywhere: `grep -rn "UIPasteboard\|PasteButton" --include='*.swift' Apps` → zero hits. App-switcher snapshots are shielded by `Apps/iOS/Ammo/AmmoApp.swift:18` + `SnapshotPrivacyPolicy` (`AmmoApp.swift:55-58`, `.background` only, deliberate per MIK-146). The field is still a `TextEditor` (`CodexOnboardingView.swift:54`) rather than a bespoke secure control, but `.privacySensitive()` plus the shield covers the stated threat. |

### Wave 4 — risk reduction

| ID | Verdict | Evidence |
|---|---|---|
| **L10** — Cursor backoff + contract harness | **open** (documentation half only) | The verifier-in-query-string behaviour **is** documented: `Sources/UsageKit/CursorProvider.swift:106` ("…approval to the polling request that carries the PKCE verifier") and `:119-123` where `verifier` is placed in a `URLQueryItem`. Backoff was **not** added: `Apps/iOS/Ammo/Onboarding/WebAuth.swift:202-209` still runs `for _ in 0..<600` with a flat `try await Task.sleep(for: .milliseconds(500))`. No re-verification harness file was added (`swift run ammo-harness` predates this plan — `README.md:28`). |
| **L11** — Upstream-revocation disclosure | **open** | `grep -rni "revoke\|revocation" --include='*.swift' Apps Sources` returns no product-code hits (only a comment in `Apps/iOS/AmmoTests/AccountDeletionTests.swift:52`). Nothing in the app or in `docs/privacy-policy.md` tells the user that "Remove Account" leaves the upstream provider session alive, and no provider session-management link is offered. |
| **L13** — `DEVELOPMENT_TEAM` → `.xcconfig` | **open** | `Apps/iOS/project.yml:21` still hard-codes `DEVELOPMENT_TEAM: JN24JD42L3`. `find . -name '*.xcconfig'` → nothing, and `.gitignore` (6 lines) has no `.xcconfig` entry. Sequenced last by design (G4), so this being open is expected, not a slip. |

### Wave 5 — submission assembly

| ID | Verdict | Evidence |
|---|---|---|
| **L12** — Privacy policy draft | **done** | `docs/privacy-policy.md` exists (effective 2026-08-14), added in `e9d1d14`. Covers no-backend, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, App Group storage, no analytics/ads/telemetry SDKs, demo-mode data handling, deletion/retention, provider processing, contact. Deployment is a separate row (H2). |
| **L14** — Store metadata + Review Notes | **open** | No metadata draft anywhere in the tree. `docs/launch-remediation-operator-checklist.md:6-25` *prescribes* the answers (App Privacy = no data collected by developer or partners; Review Notes must say "tap **See a demo**"; avoid provider trademarks in name/subtitle/keywords) but contains no drafted description, subtitle, keyword list, or Review Notes text with the two bracketed placeholders the plan called for. Branch `claude/mik-167-submission-metadata` exists, unmerged, no PR. |
| **L15** — Screenshots via demo mode | **open** | `Screenshots/` contains eleven device captures, all stamped `build13` (e.g. `ammo-device-final-build13-loaded.png`, `ammo-device-final-build13-widget.png`) plus `ammo-simulator-empty-debug.jpg`. None is from build 17, none is a demo-mode capture, and none is in an App Store-required iPhone screenshot size set. Branch `codex/mik-165-appstore-screenshots` exists, unmerged, no PR. |
| **H1** — Archive icon check | **open** | Brandon-only and unrun. Precondition is in place: `Apps/iOS/Ammo/AppIcon.icon` (Icon Composer) exists and `Apps/iOS/project.yml:59` names it. The archive-and-verify commands are already written out in `docs/launch-remediation-operator-checklist.md:26-51`. |
| **H2** — Deploy privacy policy, get URL | **open** | The document exists locally (`docs/privacy-policy.md`) but no public URL is recorded anywhere in the tree, and the `ammo-landing` repo the plan named is not present in this workspace. |
| **H3** — App Privacy answers in ASC | **open** | Brandon-only; unverifiable from the tree. The answer sheet it depends on (L14) is itself open. |
| **H4** — Live provider contract re-verification | **open** (Cursor evidenced) | Cursor has evidence in-tree: `Screenshots/ammo-device-final-build13-cursor-live-refresh.png`. Claude, Codex, and OpenRouter have no equivalent in-tree evidence, and the documents still assert the opposite for Cursor (`SPEC.md:386` "LIVE VERIFICATION PENDING", `CURSOR_RESEARCH.md:3` "live on-device verification pending"). Also note the plan says "all three providers"; the app now ships **four** (`ProviderID.supported` drives `ContentView.swift:165` and includes OpenRouter). |
| **H5** — Merge every PR | **superseded** | No `launch-*` PRs were ever opened. `gh pr list --state open` → `[]`; the last 30 commits on `main` are merged `MIK-nnn` PRs (#18–#31). The merge queue this row describes does not exist. |

### Decisions

| ID | Verdict | Evidence |
|---|---|---|
| **D1** — Base branch for all workers | **moot** | The interlock is gone: `feat/icon-and-branding` is an ancestor of `main`, and build 17 sits at `Apps/iOS/project.yml:19` on `main` @ `51b9b9b`. Nothing left to pin. |
| **D2** — `Assets/Official/*` in git history | **open** | Neither half was executed. The files are still in HEAD (`git ls-files Apps/iOS/Assets/`), so the "delete from HEAD now" step never happened, and the history question was never called. The repo remains PUBLIC. This is the single named exposure that has outlived the entire plan. |
| **D3** — Demo-mode persistence | **superseded** | Neither of the plan's two options was taken. `Apps/iOS/Shared/DemoModeStore.swift:7-22` persists a **marker file** in the App Group container (`demo-mode-enabled`), not `@AppStorage` and not an in-memory `@Observable` flag. The manifest shipped anyway, as recommended. Consequence: the demo toggle creates no `UserDefaults` required-reason usage — but the app has independent same-App-Group `UserDefaults` access requiring `1C8F.1` that the manifests fail to declare (see L5 open item (a)). The interlock the decision was about is real, just located elsewhere than predicted. |
| **D4** — Cursor in 0.1.0 | **moot** | Cursor ships and has been live-verified (operator-confirmed; corroborated in-tree by `Screenshots/ammo-device-final-build13-cursor-live-refresh.png` and by four merged Cursor fixes since — MIK-152, MIK-154, MIK-159, MIK-164). Residual: `SPEC.md:386` and `CURSOR_RESEARCH.md:3` still say verification is pending, which is now a stale-doc gap rather than a ship decision. |
| **D5** — Stale worktree pruning | **moot** | The fan-out the pruning protected never used that namespace. Pruning also did not happen — `git worktree list` now returns 50 entries across `/Users/brandon/code/personal/ammo-worktrees/` and `/Users/brandon/code/personal/ammo/worktrees/`. Operator hygiene only; no App Store impact. |

### Verdict counts

| Verdict | Count | IDs |
|---|---|---|
| **done** | 8 | W0.2, W0.3, S1, S2, S3, L1, L8, L12 |
| **open** | 16 | S4, L2, L3, L4, L5, L7, L10, L11, L13, L14, L15, H1, H2, H3, H4, D2 |
| **moot** | 3 | D1, D4, D5 |
| **superseded** | 4 | W0.1, W0.4, H5, D3 |
| **total** | 31 | (`L6` and `L9` were never allocated) |

---

## 2. Remaining gaps, prioritized

### Ship-stoppers — submission will fail, be rejected, or is legally exposed

1. **Privacy manifest under-declares same-App-Group UserDefaults reason `1C8F.1`.**
   `Apps/iOS/Ammo/PrivacyInfo.xcprivacy` and `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy`
   both ship `<key>NSPrivacyAccessedAPITypes</key><array/>`, while production notification
   preferences use `UserDefaults(suiteName: AppGroup.id)` through
   `NotificationPreferencesStorage`
   (`Sources/UsageKit/Notifications/NotificationPreferencesStorage.swift:7-16`, reached
   from `NotificationSettingsModel.swift:20` and `UsageNotificationService.swift:14`).
   Apple's required-reason taxonomy assigns `1C8F.1` to access within the same App Group.
   The separate `UserDefaults.standard` read in `AccountStore.swift:396` is simulator-only.
   Undeclared production access can trigger `ITMS-91053`. From L5. *(Gap A)*

2. **Extracted provider app icons remain in a public repository.**
   `Apps/iOS/Assets/Official/codex-app-icon.png` and `cursor-app-icon.png` are tracked
   (`git ls-files`), and `Apps/iOS/Scripts/extract-provider-glyphs.py:2,12,121,126` narrates
   how the shipped glyphs were derived from them. Live exposure since before 2026-08-01;
   the only named item in the plan that survived it untouched. From L4/D2. *(Gap B)*

3. **No App Store Connect metadata, App Privacy answer sheet, or Review Notes exist.**
   Nothing draftable is in the tree; `docs/launch-remediation-operator-checklist.md:6-25`
   states the policy but supplies no copy. Submission cannot be assembled. From L14/S4.
   *(Gap C)*

4. **No App Store screenshots.** `Screenshots/` holds build-13 documentation captures only,
   none in demo mode, none in a required iPhone size. Screenshots are a hard field on the
   submission form. From L15. *(Gap D)*

5. **`User-Agent: codex-cli` still impersonates OpenAI's CLI.**
   `Sources/UsageKit/CodexProvider.swift:30`. A one-line change that has sat unmade since
   the review; it is both a review-notes liability and a provider-relations one. From L2.
   *(Gap E)*

6. **Human submission steps not started** — signed archive verification (H1), privacy-policy
   deployment and URL (H2), App Privacy entry (H3), live re-verification of Claude / Codex /
   OpenRouter (H4). See §4. *(Gaps H1–H4)*

### Should-fix — quality, correctness, and review-surface risk

7. **Destructive "Remove Account" has no confirmation.**
   `Apps/iOS/Ammo/UI/ContentView.swift:347` deletes Keychain credentials and local history on
   a single tap, with no `confirmationDialog`. From L5. *(Gap F)*

8. **The `.authentication` notice is a dead end pointing the wrong way.**
   `Apps/iOS/Shared/UsageComponents.swift:273,292,321-324` render no action; `:350` advises
   "Remove and add this account again", which is worse than the identity-preserving
   "Sign In Again" the app already offers at `ContentView.swift:340-342`. From L7. *(Gap G)*

9. **No in-app disclosure that removal does not revoke upstream.** No product-code hit for
   `revoke` anywhere. Users will believe removing the account ended the provider session.
   From L11. *(Gap I)*

10. **Residual public-language and in-binary-attribution gaps.** `SPEC.md:389` and
    `Sources/UsageKit/CursorProvider.swift:6-7` still say "private dashboard summary";
    `SPEC.md:512-523` still publishes the `mitmproxy` re-derivation recipe; and no
    non-affiliation string exists in any `.swift` file, so the disclaimer never reaches the
    binary. From L3. *(Gap J)*

11. **Cursor sign-in polls 600 times at a flat 500 ms.**
    `Apps/iOS/Ammo/Onboarding/WebAuth.swift:202-209`. From L10. *(Gap K)*

12. **Docs still declare Cursor unverified.** `SPEC.md:386`, `CURSOR_RESEARCH.md:3`. A
    reviewer or contributor reading the public repo learns the shipping provider is
    unverified. From L10/D4/H4. *(Gap L)*

### Nice-to-have — hygiene, not blocking

13. **`DEVELOPMENT_TEAM` is committed.** `Apps/iOS/project.yml:21`; no `.xcconfig` exists.
    Deliberately sequenced last (G4). From L13. *(Gap M)*

14. **`PLAN.md` ledger is stale in-tree.** Every row still reads `blocked`/`ready` against a
    2026-08-01 baseline. Anyone picking it up cold — which is what it was written for — is
    misled. This document supersedes it; the file should say so. *(Gap N)*

15. **LICENSE is MIT where the plan recommended Apache-2.0.** `LICENSE:1`. Worth a conscious
    confirmation (Apache-2.0's patent grant and `NOTICE` convention were the stated reason)
    rather than silent drift, especially since a `NOTICE` file already exists. *(Gap O)*

16. **50 git worktrees across two roots.** `git worktree list`. Operator hygiene. *(Gap P)*

---

## 3. Proposed Linear issues

> The orchestrator files these. Titles are ready to paste; bodies are self-contained.

### A. `fix(privacy): declare same-App-Group UserDefaults (1C8F.1) in both manifests`

Both `Apps/iOS/Ammo/PrivacyInfo.xcprivacy` and `Apps/iOS/AmmoWidgets/PrivacyInfo.xcprivacy`
currently ship an empty `NSPrivacyAccessedAPITypes` array, while production notification
preferences use `UserDefaults(suiteName: AppGroup.id)` through
`Sources/UsageKit/Notifications/NotificationPreferencesStorage.swift:7-16`, reached from
`NotificationSettingsModel.swift:20` and `UsageNotificationService.swift:14`. Apple's
required-reason taxonomy assigns `1C8F.1` to access within the same App Group; the
`UserDefaults.standard` read in `AccountStore.swift:396` is simulator-only and does not
justify `CA92.1` in device binaries. Undeclared production access can trigger
`ITMS-91053` before human review. Add
`NSPrivacyAccessedAPICategoryUserDefaults` reason `1C8F.1` to both manifests, audit for
other required-reason categories, and verify both manifests in the archived app and widget
bundles per `docs/launch-remediation-operator-checklist.md:26-51`.

### B. `chore(assets): remove Apps/iOS/Assets/Official from the public repo and re-source glyph provenance`

`Apps/iOS/Assets/Official/codex-app-icon.png` and `cursor-app-icon.png` are still tracked in
a repository that `gh repo view` confirms is public, and
`Apps/iOS/Scripts/extract-provider-glyphs.py:2,12,121,126` documents that the shipped provider
glyphs in `Apps/iOS/Shared/ProviderAssets.xcassets/` were carved out of those icons. This was
identified as live exposure on 2026-08-01 (PLAN.md G1, item L4, decision D2) and is the only
named exposure that has survived every subsequent wave untouched. Delete the directory from
HEAD, rewrite the script so it reads from a locally supplied path rather than a committed
vendor asset, and replace the docstring's "official provider glyph pixels" framing with the
actual licensing basis for each shipped glyph. Produce a re-sourcing checklist naming, per
provider, the official brand-kit URL and its usage terms, since an agent cannot fetch those
assets itself. Treat the separate question of rewriting git history and force-pushing as an
explicit follow-up decision, not part of this change.

### C. `docs(launch): draft App Store Connect metadata, App Privacy answers, and Review Notes`

No submission copy exists in the tree; `docs/launch-remediation-operator-checklist.md:6-25`
prescribes the policy but supplies no drafted text, and branch
`claude/mik-167-submission-metadata` is unmerged with no PR. Draft the full metadata set for
version 0.1.0 build 17: app name, subtitle, promotional text, description, keywords, support
URL, marketing URL, and category — avoiding provider trademarks in name, subtitle, and
keywords, and stating in the description that Ammo is independent and requires the user's own
provider accounts. Draft the App Privacy answer sheet as **Data Not Collected** across every
category for both the developer and third-party partners, and explicitly do *not* declare
"User ID". Draft Review Notes telling the reviewer to tap **See a demo** on first launch,
noting that the sample data is labeled, fully offline, and covers Usage, On-demand, History,
and widgets, and explaining why paid third-party provider credentials cannot be supplied.
Land it as a document under `docs/` so the answers are reviewable before they are typed into
App Store Connect.

### D. `chore(release): capture App Store screenshots from build 17 demo mode`

`Screenshots/` currently holds only build-13 device captures (`ammo-device-final-build13-*`)
plus one simulator debug JPEG — none from build 17, none in demo mode, and none in an
App Store-required iPhone screenshot size. Screenshots are a mandatory submission field, so
this blocks the form regardless of code readiness. Now that demo mode is reachable via
**See a demo** (`Apps/iOS/Ammo/UI/ContentView.swift:208`) and is fully offline, the capture is
automatable: `cd Apps/iOS && xcodegen`, build to `platform=iOS Simulator,name=iPhone 17`,
enable demo mode, and drive `simctl io … screenshot` across Usage, On-demand, History, and a
widget gallery view. Produce every currently required iPhone display size, verify no
credential or personal label is visible, and confirm the "Sample data" capsule
(`ContentView.swift:319-325`) appears in each frame so the reviewer can tell fixtures from
live data. Branch `codex/mik-165-appstore-screenshots` exists and may be a starting point.

### E. `fix(codex): stop sending User-Agent: codex-cli`

`Sources/UsageKit/CodexProvider.swift:30` still sets `"User-Agent": "codex-cli"` on requests
to `chatgpt.com/backend-api`, impersonating OpenAI's own command-line client from a
third-party App Store binary. `grep -rn "Ammo/0" --include='*.swift' Sources Apps` confirms no
Ammo-identifying User-Agent exists anywhere. Replace it with `Ammo/0.1.0`, ideally derived
from `CFBundleShortVersionString` rather than hard-coded so it does not drift from
`Apps/iOS/project.yml:18`. Check the other adapters in the same pass — `ClaudeProvider`,
`CursorProvider`, and the OpenRouter adapter — and give them the same honest identifier.
Update or add the corresponding fixture assertions in `Tests/UsageKitTests/` and confirm
`swift test` stays green at 204 tests.

### F. `fix(app): confirm before removing an account`

`Apps/iOS/Ammo/UI/ContentView.swift:347` wires the destructive "Remove Account" menu item
straight to `store.remove(state.account)`, and there is no `confirmationDialog` or `alert`
anywhere in the file. One stray tap permanently deletes the account's Keychain credentials
and its local usage history, and for on-device OAuth accounts re-adding requires a full
browser sign-in. Add a `confirmationDialog` naming the account label and stating plainly what
is deleted and that the provider session upstream is unaffected. This pairs naturally with
the upstream-revocation disclosure issue, and the two could ship together. Add a UI-level
test alongside the existing `Apps/iOS/AmmoTests/` suites asserting that the destructive path
is gated.

### G. `fix(ui): give the .authentication notice a Sign In Again action and correct its copy`

`Apps/iOS/Shared/UsageComponents.swift:321-324` keeps `canRetryImmediately == false` for
`.authentication` — correctly, since a retry genuinely cannot succeed — but `:273` and `:292`
gate `actionTitle` and `action` on that same flag, so the card renders no button at all. Worse,
the message at `:350` tells the user to *"Remove and add this account again to resume
updates"*, which is now actively harmful advice: `ContentView.swift:340-342` offers
"Sign In Again", and MIK-156 made that path preserve account identity so history and widget
attachments survive. Introduce a recovery action distinct from retry that opens
`ProviderSignInSheet(provider:reconnecting:)` for the affected account, and rewrite the
`.authentication` copy to point at it. Keep `canRetryImmediately` false — this is about a
second, separate action, not about re-enabling retry.

### H. `feat(app): disclose that Remove Account does not revoke the upstream provider session`

`grep -rni "revoke\|revocation" --include='*.swift' Apps Sources` returns no product-code
hits, so nothing in the app or in `docs/privacy-policy.md` tells the user that removing an
account leaves the provider-side session alive — for Anthropic, roughly 19 days. Users
reasonably read "Remove Account" as a revocation and will not go revoke the session
themselves. Add a short disclosure at the point of removal and in Settings, stating that Ammo
deletes only the local copy and linking each provider's session-management page. Do **not**
revoke programmatically: for imported Codex credentials that would log the user out of their
desktop CLI, which the app already warns about at
`Apps/iOS/Ammo/Onboarding/CodexOnboardingView.swift:64`. Mirror the same statement in the
"Deletion and retention" section of `docs/privacy-policy.md`.

### I. `docs: neutralize remaining public-exposure language and put non-affiliation in the binary`

Three items from the original L3 scope did not land. `SPEC.md:389` and
`Sources/UsageKit/CursorProvider.swift:6-7` both still describe the Cursor endpoint as a
"private dashboard summary"; `SPEC.md:512-523` still publishes a step-by-step `mitmproxy`
recipe for re-deriving provider contracts; and `grep -rni "affiliat\|trademark"
--include='*.swift' Apps Sources` returns zero hits, meaning the non-affiliation statement
lives only in `NOTICE` and `docs/privacy-policy.md:5-7` and never reaches the shipped app.
Rewrite the two "private dashboard" descriptions in neutral observational terms consistent
with the already-corrected `SPEC.md:10`, replace the `mitmproxy` recipe with a pointer to
first-party debugging affordances, and surface the `NOTICE` non-affiliation and trademark
text inside the app — an About row in `SettingsView` is the natural home. Also confirm the
MIT choice in `LICENSE` is deliberate, since the plan recommended Apache-2.0 and a `NOTICE`
file already exists.

### J. `fix(cursor): back off the sign-in poll loop and refresh the verification date stamps`

`Apps/iOS/Ammo/Onboarding/WebAuth.swift:202-209` polls `CursorProvider.pollForTokens` 600
times at a flat 500 ms interval for a full five minutes, which is a lot of unthrottled traffic
at an undocumented endpoint if the user walks away mid-login. Replace the flat interval with
exponential backoff capped at a few seconds, keeping the overall five-minute deadline and the
existing cancellation paths intact. Separately, the documents still contradict reality:
`SPEC.md:386` reads "LIVE VERIFICATION PENDING" and `CURSOR_RESEARCH.md:3` says "live
on-device verification pending", even though Cursor has been verified live and has shipped
four fixes since (MIK-152, MIK-154, MIK-159, MIK-164). Update both date stamps to reflect the
verification actually performed, and record the date and build so the claim is auditable.

### K. `chore(build): move DEVELOPMENT_TEAM into a gitignored xcconfig with a committed template`

`Apps/iOS/project.yml:21` hard-codes `DEVELOPMENT_TEAM: JN24JD42L3`, and `find . -name
'*.xcconfig'` confirms no override file exists. The plan deliberately sequenced this last
(PLAN.md G4) because a gitignored `.xcconfig` does not exist in a fresh worktree, and the
three `RotatedCredentialPersistenceTests` in
`Apps/iOS/AmmoTests/BackgroundRefreshTests.swift` need the Keychain access group that signing
provides. Introduce `Local.xcconfig` (gitignored) plus a committed `Local.xcconfig.template`,
wire it through `project.yml`, add the ignore entry to `.gitignore`, and document the one-line
setup step in `README.md`. Land this only after the other code issues in this batch have
merged, and verify by running both gates in a fresh clone: `swift test` at the root, then
`cd Apps/iOS && xcodegen && xcodebuild test -project Ammo.xcodeproj -scheme Ammo -destination
'platform=iOS Simulator,name=iPhone 17'` — without `CODE_SIGNING_ALLOWED=NO`.

### L. `docs(launch): retire PLAN.md's stale status ledger`

`docs/launch-review/PLAN.md` is explicitly written to be picked up cold and declares itself
"the source of truth", but its ground truth is dated 2026-08-01 and every row of its status
ledger still reads `blocked` or `ready` — including rows that demonstrably shipped in
`e9d1d14` on 2026-08-14 (LICENSE, NOTICE, demo mode, both privacy manifests, the privacy
policy, the tri-state deletion store). Its branch namespace (`launch-<id>`) was never used,
and its `L*` IDs were replaced by MIK numbering. Add a header pointing at
`docs/launch-review/READINESS-2026-08-25.md` as the current state, and either reconcile the
ledger rows against that audit or mark the ledger historical. The two review documents
(`app-review.md`, `red-team.md`) remain valid as findings and should stay as-is.

### M. `chore: prune stale git worktrees`

`git worktree list` returns 50 entries spread across two different roots —
`/Users/brandon/code/personal/ammo-worktrees/` and
`/Users/brandon/code/personal/ammo/worktrees/` — up from the 13 recorded on 2026-08-01
(PLAN.md G7). Most correspond to MIK issues whose PRs are merged (`gh pr list --state open`
returns `[]`, and #18–#31 are all merged on `main`). Walk the list, confirm each worktree's
branch is an ancestor of `main` or holds no unpushed commits, and `git worktree remove` the
ones that are settled. Keep anything with uncommitted or unmerged work and record why. Purely
operator hygiene with no App Store impact, but it makes future fan-out safe.

---

## 4. What Brandon must do by hand

Ordered by when it is needed. None of these can be done by an agent.

1. **Decide the `Assets/Official` history question** (Gap B / D2). Deleting from HEAD is
   agent-work and is proposed above. Whether to also rewrite git history and force-push a
   public repository is a call only you can make — it breaks every existing clone and fork.
2. **Publish the privacy policy and capture the URL** (H2). `docs/privacy-policy.md` is
   drafted and current. Deploy it to a stable HTTPS page, open it in a logged-out browser to
   confirm it renders, and record that URL — App Store Connect requires it, and a repository
   blob URL only works while the repo stays public.
3. **Confirm the GitHub Issues support route** (operator checklist item 3). The privacy policy
   already points contact at `https://github.com/Brandon1138/ammo/issues`; confirm Issues are
   enabled and that the same URL is entered as the Support URL.
4. **Live-verify Claude, Codex, and OpenRouter contracts** (H4). Cursor has in-tree evidence;
   the other three do not. Use one operator-owned account per provider on a real device
   against the release build, exercise one token refresh for the on-device OAuth accounts
   without invalidating your desktop CLI credentials, and record timestamps. Procedure is
   already written at `docs/launch-remediation-operator-checklist.md:52-63`.
5. **Run the signed archive and verify the icon reaches the binary** (H1). Requires Xcode and
   your signing identity. The exact commands and the four `codesign`/`plutil` assertions are
   at `docs/launch-remediation-operator-checklist.md:26-51`. Confirm both bundles contain
   `PrivacyInfo.xcprivacy` — do this *after* Gap A lands, or you will archive the
   under-declared manifest.
6. **Run the on-device privacy and lifecycle checks** (operator checklist items 1–5, lines
   64-79). Backgrounding during paste, port-1455 contention, token rotation under a locked
   App Group, interrupted add/remove, and Keychain attribute inspection — all need a physical
   device.
7. **Create the App Store Connect record and enter the App Privacy answers** (H3). Bundle ID
   `com.brandon.ammo`, name `Ammo`, **Data Not Collected** across every category for both
   developer and partners, no "User ID" declaration. Do this after the metadata draft
   (Gap C) is reviewed, so you are transcribing rather than composing.
8. **Upload screenshots and Review Notes, then submit** — after Gap D produces build-17 demo
   captures in the required sizes.
9. **Merge the PRs.** The `verify` check is required and auto-merge is off, so every PR from
   the issues above needs your click.
