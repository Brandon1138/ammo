# Ammo launch operator checklist

Run from submitted release commit. Record date, device, iOS/Xcode versions,
archive path, and App Store Connect build number. Do not reuse older evidence.

## App Store Connect

1. Create or select app record for bundle ID `com.brandon.ammo`.
2. Publish `docs/privacy-policy.md` at a stable HTTPS URL. Open it logged out and
   enter that URL in App Privacy. Do not use repository blob URL unless public.
3. Set Support URL to a public page with working contact route, such as
   `https://github.com/Brandon1138/ammo/issues`, after confirming Issues enabled.
4. App Privacy answer: developer and third-party partners collect no data. Recheck
   this answer if analytics, crash reporting, backend proxying, or SDKs are added.
5. Export compliance must agree with `ITSAppUsesNonExemptEncryption = false`.
   Content Rights: third-party content/marks are present; confirm rights before
   answering Yes. Age rating target: 4+, subject to current questionnaire.
6. Use app name `Ammo`; avoid provider trademarks in name, subtitle, and keywords.
   Description must state independence and need for users' own provider accounts.
7. Review Notes must tell reviewer: first launch, tap **See a demo**; sample data
   is labeled, offline, and covers Usage, On-demand, History, and widgets. Explain
   why paid third-party demo credentials cannot be supplied.
8. Upload current required iPhone screenshot sizes from this exact build. Check no
   credential, personal label, or unrelated device bezel appears.

## Signed archive and entitlements

```sh
cd Apps/iOS
xcodegen
xcodebuild -project Ammo.xcodeproj -scheme Ammo -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/Ammo-launch.xcarchive archive
```

After successful signed archive:

```sh
plutil -p /tmp/Ammo-launch.xcarchive/Products/Applications/Ammo.app/Info.plist
find /tmp/Ammo-launch.xcarchive/Products/Applications/Ammo.app -name PrivacyInfo.xcprivacy -print
codesign -d --entitlements :- /tmp/Ammo-launch.xcarchive/Products/Applications/Ammo.app
codesign -d --entitlements :- /tmp/Ammo-launch.xcarchive/Products/Applications/Ammo.app/PlugIns/AmmoWidgets.appex
```

Confirm app icon keys and emitted icon files exist. Confirm both bundles contain
privacy manifests. Confirm app and widget entitlements include
`group.com.brandon.ammo` and `$(AppIdentifierPrefix)com.brandon.ammo.shared` after
prefix expansion. Confirm embedded distribution profiles grant same values and
`get-task-allow` is false. Export with App Store method, upload, wait for processing,
and resolve every validation warning before review submission.

## Live provider contracts

On current release build and real device, add one operator-owned test account per
provider. Refresh Claude, Codex, Cursor, and OpenRouter. Record successful timestamps
and verify included windows, reset times, plan, and on-demand values against provider
UI or, for OpenRouter, the ordinary key's documented `GET /api/v1/key` response.
Exercise one token refresh for on-device OAuth accounts without importing or
invalidating desktop credentials. OpenRouter's imported key is intentionally
non-refreshable; verify finite and no-limit key presentation without a synthetic
percentage window. If a provider cannot be verified, remove it from shipping UI and
metadata; do not call fixture decode proof live-contract proof.

## Privacy and lifecycle device checks

1. Open Codex fallback paste field with non-production test text. Background app.
   App switcher must show blank privacy shield, not field. Return, complete both
   success and failure imports, and verify rendered field clears. Clear pasteboard.
2. Start Codex sign-in, background app, return. Flow must stop and show retryable
   error. Occupy port 1455 with controlled test app/process; Ammo must fail before
   browser launch instead of hanging. Complete normal Codex sign-in afterward.
3. Rotate Claude/Codex token while forcing App Group protected-data/lock failure.
   Verify new Keychain item remains. Retry after unlock and verify refresh recovers.
4. Interrupt account add after Keychain write and account removal after tombstone.
   Relaunch. Pending add must roll back or finish only when both stores exist;
   pending removal must remain hidden and finish cleanup.
5. Inspect Keychain item attributes on device: ThisDeviceOnly, non-synchronizable,
   correct shared access group. Inspect encrypted backup expectations separately.

## Widgets and accessibility

Add each widget family using demo and live data. Verify small/medium,
light/dark, tinted, and clear rendering; account picker must list demo samples.
(Lock Screen accessory widgets are deferred to a post-launch build; the
pre-removal state lives on the `deferred/lockscreen-widgets` branch.)
Confirm no token or pasted credential appears in widget/App Group files. With
VoiceOver enabled, traverse every tab, account menu, error notice, demo controls,
and widget configuration. With Accessibility Large text, verify no clipped actions,
percentages, reset times, or destructive controls. Record screen captures and any
unlabeled element before submission.
