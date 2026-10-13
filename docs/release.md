# Release (signing, notarization, DMG)

Tracked by STA-76. Nothing secret is committed: the signing identity and notary profile come from environment variables.

## Distribution channel

Decided (owner, STA-75): the official release is a **Developer ID signed, notarized DMG**, downloaded directly. A beta without Apple signing comes first (see "Beta channel"). Mac App Store distribution is on hold: it requires App Sandbox, which conflicts with capturing selected text through the Accessibility API, sending the copy key event and reading the Chrome URL through Apple Events. Revisit it only if a sandbox-compatible product is decided.

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

Version policy: edit `APP_VERSION` / `APP_BUILD` / `APP_CHANNEL` in `scripts/app-config.sh` (or override via env). `APP_BUILD` must increase on every shipped build. `APP_CHANNEL` (default `beta.1`) only labels the DMG name (`plopcut-0.1.0-beta.1.dmg`); `Info.plist` keeps the plain `APP_VERSION` because `CFBundleShortVersionString` must be dotted integers. Set `APP_CHANNEL=` (empty) for the official release.

## Beta channel (STA-87)

Decided (owner): plopcut ships as a beta first, before joining the Apple Developer Program. The official signed release follows after testing (STA-88).

- **Build:** `scripts/release.sh --adhoc` makes a release build signed ad hoc (Hardened Runtime and entitlements still applied) and packs it into `dist/plopcut-<version>-beta.<n>.dmg`. Bump `APP_BUILD`, and `APP_CHANNEL` for each new beta (`beta.2`, ...).
- **Not signed by Apple, not notarized.** Gatekeeper rejects the app on a Mac that downloaded it, so testers must allow it once (System Settings › Privacy & Security › Open Anyway, or `xattr -dr com.apple.quarantine /Applications/plopcut.app`). The README explains this for users.
- **Permissions:** an ad-hoc signature changes with every build, so macOS may drop the Accessibility or Automation grant after an update (`tccutil reset Accessibility com.plopcut.app`, then allow again). Moving to the Developer ID build needs one more re-grant. The bundle ID `com.plopcut.app` stays the same, so settings and drops carry over.
- **Publish:** create a GitHub Release marked **Pre-release**, upload the DMG, and put the unsigned warning at the top of the notes. Add the SHA-256 (`shasum -a 256`) so testers can verify the download.
- **Verified for the beta:** the DMG verifies (`hdiutil verify`), `codesign --verify --deep --strict` passes, and the app opens after the Open Anyway step. NOT verified: Gatekeeper acceptance, notarization, and clean-Mac installs on Intel (the build is single-architecture, the host's).
- **Never** commit signing identities, Apple IDs, passwords, or `.p12`/`.p8` files. None are needed for a beta.

## What was verified locally (no Apple account on the build Mac)

- `sh -n` on all scripts, `release.sh --check`, `release.sh --adhoc` (release build, ad-hoc signed DMG, `hdiutil verify`), Info.plist lint, deployment target 14.0, and a Hardened Runtime + entitlements signing run with the ad-hoc identity.
- NOT verified: Developer ID signing, notarization, stapling, `spctl --assess` acceptance, and clean-Mac installs (Apple Silicon and Intel). Ad-hoc builds are rejected by Gatekeeper by design.

## Human-only steps (official release, STA-88)

These apply to the official signed release. The beta needs none of them.

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
