# Development and TestFlight

The SwiftUI app targets iOS 17+, iPhone and iPad. The project is generated from
`ios/project.yml`. The controller uses Node built-ins, SQLite and the existing
Herdr CLI. No provider API key is embedded in the app.

## Native verification

Regular tests cover HTTPS validation, encoded agent identities, wire decoding,
unknown states, stale machines, uncertain operations, demo navigation, disabled
demo input, pairing defaults and stale attention labels.

Live pairing is explicitly separate. Build the tests, launch the unpaired app
on a simulator, then run only
`HerdrUITests/HerdrUITests/testPreparedLivePairing` with `test-without-building`.
While it waits, run:

```sh
node scripts/prepare-simulator-pairing.mjs SIMULATOR_UUID
```

The script delivers a one-use link directly to that simulator without printing
it. The test connects, verifies the real machine list, and revokes its own access.
Do not export pairing-form screenshots containing a code.

## Apple configuration

- Display name: **Herdr**; App Store Connect name: **Herdr Shared**
- Bundle ID: `xyz.verdalecres.herdr`
- Team: `V8W579ZBVB`
- SKU: `herdr-ios-mark`
- Primary language: English (Australia)
- Version: 0.1.0; build: 2
- Push Notifications enabled on the registered bundle identifier

App Store Connect app ID: `6809146693`. The app record, developer bundle ID
and APNs provider key are configured. Apple API access is working; private
keys stay outside this repository. The Mark internal group is
`538ff12a-979b-414d-af4e-cdd092e0745b`, with only the account holder enrolled.

`scripts/apple-api.mjs` supports JSON API requests using the installed key.
Optional environment variables: `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_PATH`.

## Archive, upload and distribution

```sh
bash scripts/archive-testflight.sh
# Increment the build number for any subsequent upload:
bash scripts/archive-testflight.sh --upload
```

Outputs: `build/Herdr.xcarchive` and `build/Export/Herdr.ipa`. Xcode export signs
for App Store Connect. Verify the exported app has `aps-environment=production`
and the expected bundle ID. Increment `CURRENT_PROJECT_VERSION` before uploading
another build after Apple has accepted the previous number.

After upload, wait for Apple processing, resolve any actual export-compliance
questions, add the processed build to an internal TestFlight group, and verify
that the tester can install it. Do not call an archive, successful upload or
processing state a completed distribution.

Suggested TestFlight “What to Test”:

> Connect through Tailscale, pair with the Mac, verify the Mac and Home PC agent
> lists, read output, send a harmless message, and confirm it reaches the intended
> machine. Enable notifications and test an alert. Check reconnection after
> switching networks. The work laptop is intentionally marked Setup pending.

Push verification needs an APNs key uploaded through `/setup` and an installed
iPhone that has granted permission. In Herdr Settings, send a test alert, confirm
Apple accepted it, then confirm the alert visibly arrives. Test a real agent
state transition separately. iOS Focus and notification settings affect display.

## First release verification

Build 0.1.0 (1) was uploaded successfully on 6 September 2026. Apple reports
`VALID` / `IN_BETA_TESTING`, and the Mark group has the build and one account-holder
tester whose state is `INSTALLED`. Australian English test notes include the
private pairing URL and verification steps. The phone is paired and registered
for production APNs. Apple accepted the test alert. See `releases/0.1.0-1.json` for
resource IDs and evidence. Mark confirmed that the test alert appeared on the iPhone.

## Compact list update

Build 0.1.0 (2) is available in the Mark internal TestFlight group. Apple reports
`VALID` and `IN_BETA_TESTING` for build `04dba3dc-42de-4dcb-a844-3294441199a5`.
The group still contains only the account holder. Australian English test notes
describe the compact rows, machine filters, long names and larger text support.

Five unit tests and five UI tests passed. Three focused UI checks passed again
after the final accessibility adjustment. Simulator screenshots cover eight
agents, long names, stale state and the largest accessibility text size. The
exported build passed signature checks with production APNs entitlements.
The controller is unchanged. Physical installation of build 2 remains unconfirmed;
the phone pairing and push delivery were verified on build 1. See
`release-status.json` for current evidence.

## Release boundaries

No secrets, signing material, generated build artifacts, logs or runtime
databases belong in Git. The initial implementation is uncommitted in this
checkout. No shared branch has been pushed or repository PR merged. Follow
Mark’s PR-first release instructions when a repository release is requested.
