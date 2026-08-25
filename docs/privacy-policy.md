# Ammo Privacy Policy

Effective: August 14, 2026

Ammo is an independent iOS app for viewing usage limits from services you
already use. Ammo is not affiliated with, endorsed by, or sponsored by
Anthropic, OpenAI, Cursor/Anysphere, or OpenRouter.

## Data handling

- Ammo has no developer-operated backend. Network requests go directly from
  your device to the provider you choose.
- Provider credentials are stored in iOS Keychain items configured with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. They do not synchronize
  through iCloud Keychain and do not migrate to another device from a backup.
- Account labels, usage snapshots, refresh scheduling data, and usage history
  are stored locally in Ammo's App Group container so its widgets can render.
- Ammo includes no analytics, advertising, attribution, crash-reporting, or
  telemetry SDK. Ammo does not sell or share personal data.
- Demo mode uses generated sample data, stores no provider credentials, and
  makes no network requests.

## Deletion and retention

Removing an account inside Ammo deletes its Keychain credentials and local
usage records. Remove accounts before uninstalling if you want an explicit
Keychain deletion; iOS controls uninstall-time Keychain retention and does not
provide apps an uninstall callback. App Group files are managed by iOS with the
app and extension containers.

## Provider processing

When you refresh usage or sign in, the selected provider receives requests and
processes them under its own privacy policy. Ammo receives the response only on
your device and does not transmit it to Ammo's developer.

## Contact

Questions or deletion issues: <https://github.com/Brandon1138/ammo/issues>

Source: <https://github.com/Brandon1138/ammo>
