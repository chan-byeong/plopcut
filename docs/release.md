# Release (signing, notarization, DMG)

Tracked by STA-76. Nothing secret is committed: the signing identity and notary profile come from environment variables.

## Distribution channel

Decided (owner, STA-75): Notedrop is distributed as a **Developer ID signed, notarized DMG**, downloaded directly. Mac App Store distribution is on hold: it requires App Sandbox, which conflicts with capturing selected text through the Accessibility API, sending the copy key event and reading the Chrome URL through Apple Events. Revisit it only if a sandbox-compatible product is decided.

## Files

| File | Role |
| --- | --- |
| `scripts/app-config.sh` | Single source of bundle ID, version, build number, minimum macOS. Sourced by both scripts. |
| `scripts/make-app.sh` | Builds `NotedropApp/.build/Notedrop.app`. Ad-hoc signs by default; with `SIGN_IDENTITY` set, signs with Hardened Runtime, secure timestamp and entitlements. |
| `scripts/Notedrop.entitlements` | `com.apple.security.automation.apple-events` (browser URL via Apple Events). Accessibility needs no entitlement. The app is not sandboxed. |
| `scripts/release.sh` | build, sign, DMG, notarize, staple, `spctl` verify. Output: `dist/Notedrop-<version>.dmg`. |

## Commands

```sh
scripts/release.sh --check   # report missing tools/env/identity; builds nothing
scripts/release.sh --adhoc   # local rehearsal: release build + ad-hoc DMG, no notarization (not distributable)
DEVELOPER_ID_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE=notedrop-notary \
  scripts/release.sh         # full release
```

Version policy: edit `APP_VERSION` / `APP_BUILD` in `scripts/app-config.sh` (or override via env). `APP_BUILD` must increase on every shipped build.

## What was verified locally (no Apple account on the build Mac)

- `sh -n` on all scripts, `release.sh --check`, `release.sh --adhoc` (release build, ad-hoc signed DMG, `hdiutil verify`), Info.plist lint, deployment target 14.0, and a Hardened Runtime + entitlements signing run with the ad-hoc identity.
- NOT verified: Developer ID signing, notarization, stapling, `spctl --assess` acceptance, and clean-Mac installs (Apple Silicon and Intel). Ad-hoc builds are rejected by Gatekeeper by design.

## Human-only steps

1. **Apple Developer Program** membership (paid) and a **Developer ID Application** certificate installed in the login keychain (Xcode > Settings > Accounts > Manage Certificates, or developer.apple.com). Confirm with `security find-identity -v -p codesigning`; the full name is `DEVELOPER_ID_IDENTITY`.
2. **Notary credentials**: create an app-specific password at account.apple.com, then
   ```sh
   xcrun notarytool store-credentials "notedrop-notary" --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```
   The profile name is `NOTARY_PROFILE`. (An App Store Connect API key via `--key/--key-id/--issuer` also works.)
3. Run `scripts/release.sh --check`, then the full command above. If notarization is rejected, fetch the log: `xcrun notarytool log <submission-id> --keychain-profile "$NOTARY_PROFILE"`.
4. Confirm `spctl --assess` passes (the script prints it) and `xcrun stapler validate dist/Notedrop-<version>.dmg`.
5. Test on clean Macs (Apple Silicon and Intel; macOS 14+): drag to Applications, first launch, Accessibility and Automation prompts, capture flow. The build is single-architecture (host arch). For an Intel + Apple Silicon DMG, build with `swift build -c release --arch arm64 --arch x86_64`; `make-app.sh` does not do this yet, so this is open work.
6. Upload/distribute the DMG.

## Open decision: bundle identifier

Kept as `app.notedrop.dev` (legacy). Changing it makes macOS treat the app as new, so users must re-grant Accessibility and Automation, and old grants for the legacy Tauri app (same ID) no longer apply. No technical blocker was found for keeping it; the only argument for changing is that `.dev` reads like a development ID for a public release. Decide before the first public release; once shipped, changing it is costly. To change: set `BUNDLE_ID` in `scripts/app-config.sh` and update `docs/swift-migration/spec.md` and the `tccutil` line in `behavior-checklist.md`.

Also note that the Developer ID certificate's team ID is part of the code signing requirement macOS stores for permissions; moving from an ad-hoc/dev signature to Developer ID may itself require a one-time re-grant (`tccutil reset Accessibility app.notedrop.dev`).
