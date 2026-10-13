# Release (signing, notarization, DMG)

Tracked by STA-76. Nothing secret is committed: the signing identity and notary profile come from environment variables.

## Distribution channel

Decided (owner, STA-75): plopcut is distributed as a **Developer ID signed, notarized DMG**, downloaded directly. Mac App Store distribution is on hold: it requires App Sandbox, which conflicts with capturing selected text through the Accessibility API, sending the copy key event and reading the Chrome URL through Apple Events. Revisit it only if a sandbox-compatible product is decided.

Publishing (decided, STA-85, replacing the STA-75 plan): plopcut is open source. The source repository `github.com/chan-byeong/plopcut` is the public home: the user docs are its README and `docs/`, and the DMGs are assets of its GitHub Releases. There is no separate release repository. The repository stays private until the open-source readiness checks (STA-86) are done.

## Files

| File | Role |
| --- | --- |
| `scripts/app-config.sh` | Single source of bundle ID, version, build number, minimum macOS. Sourced by both scripts. |
| `scripts/make-app.sh` | Builds `PlopcutApp/.build/plopcut.app`. Ad-hoc signs by default; with `SIGN_IDENTITY` set, signs with Hardened Runtime, secure timestamp and entitlements. |
| `scripts/plopcut.entitlements` | `com.apple.security.automation.apple-events` (browser URL via Apple Events). Accessibility needs no entitlement. The app is not sandboxed. |
| `scripts/release.sh` | build, sign, DMG, notarize, staple, `spctl` verify. Output: `dist/plopcut-<version>.dmg`. |

## Commands

```sh
scripts/release.sh --check   # report missing tools/env/identity; builds nothing
scripts/release.sh --adhoc   # local rehearsal: release build + ad-hoc DMG, no notarization (not distributable)
DEVELOPER_ID_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE=plopcut-notary \
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
   xcrun notarytool store-credentials "plopcut-notary" --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```
   The profile name is `NOTARY_PROFILE`. (An App Store Connect API key via `--key/--key-id/--issuer` also works.)
3. Run `scripts/release.sh --check`, then the full command above. If notarization is rejected, fetch the log: `xcrun notarytool log <submission-id> --keychain-profile "$NOTARY_PROFILE"`.
4. Confirm `spctl --assess` passes (the script prints it) and `xcrun stapler validate dist/plopcut-<version>.dmg`.
5. Test on clean Macs (Apple Silicon and Intel; macOS 14+): drag to Applications, first launch, Accessibility and Automation prompts, capture flow. The build is single-architecture (host arch). For an Intel + Apple Silicon DMG, build with `swift build -c release --arch arm64 --arch x86_64`; `make-app.sh` does not do this yet, so this is open work.
6. Upload/distribute the DMG.

## Bundle identifier

Decided (STA-85): `com.plopcut.app`, the reverse DNS of plopcut.com. Register plopcut.com before the first public release so the ID stays tied to a domain we own. The Notedrop-era ID was `app.notedrop.dev`.

macOS treats a new bundle ID as a new app, so users of an earlier Notedrop build must re-grant Accessibility and Automation once. Their drops, settings and log are moved by the legacy folder migration (`docs/swift-migration/spec.md` section 1.9). To change the ID again, set `BUNDLE_ID` in `scripts/app-config.sh` and update `spec.md` and the `tccutil` line in `behavior-checklist.md`. Once shipped, changing it is costly.

Also note that the Developer ID certificate's team ID is part of the code signing requirement macOS stores for permissions; moving from an ad-hoc/dev signature to Developer ID may itself require a one-time re-grant (`tccutil reset Accessibility com.plopcut.app`).
