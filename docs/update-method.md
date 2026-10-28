# Update method and open decisions

Status: **decided — Sparkle in-app updates (owner, PLO-118, 2026-10-27).** This replaces the
manual-download decision of STA-75 (PLO-7).

## Decision: Sparkle

Plopcut checks for updates with [Sparkle](https://sparkle-project.org/) 2 and installs them in place.
Users no longer have to notice a new version and replace the app by hand.

How it works:

- **Feed.** A static appcast at `https://plopcut.com/appcast.xml`, served from `site/appcast.xml` by the
  Pages workflow. Each item points at the versioned DMG of a GitHub Release
  (`releases/download/v<version>/Plopcut-<version>.dmg`).
- **Signing.** Each DMG is signed with an EdDSA key. The public key is in `scripts/app-config.sh`
  (`SPARKLE_PUBLIC_KEY`) and written to `Info.plist` as `SUPublicEDKey`; the private key stays in the
  release Mac's login keychain and is never committed. Sparkle also requires the new app to carry a
  Developer ID signature from the same team.
- **Schedule.** Automatic checks are on by default (owner, 2026-10-28): `SUEnableAutomaticChecks` is
  `true` in `Info.plist`, so Sparkle does not ask on the second launch and checks about once a day. `Check for Updates` in the app menu, the
  menu bar menu, and Settings › About checks right away. Settings › About also has the automatic-check
  switch. Sparkle keeps these choices in the app's user defaults, not in `settings.json`.
- **Privacy.** The check is a plain HTTPS request; system profiling is off. See
  [privacy.md](privacy.md#update-checks).
- **Builds without a key** (`swift run`, or `make-app.sh` with an empty `SPARKLE_PUBLIC_KEY`) get no
  feed and start no updater, and the update items are hidden.
- **Release.** `scripts/release.sh` runs `generate_appcast` after notarization and writes
  `site/appcast.xml`. See [release.md](release.md).

Why the change: with manual download, users did not learn about new versions, so fixes reached them
slowly. The cost is accepted: one network request (documented in privacy.md), one more dependency
(pinned exactly), and an EdDSA key to keep safe.

Builds released before PLO-118 have no updater. Their users must download one new version by hand; the
release notes of the first Sparkle release say so.

## Previous decision: manual download (STA-75, replaced)

The app made no network calls and users downloaded each new DMG from GitHub Releases. It needed no
update server, dependency, or signing keys, but users had to notice new versions themselves and there
was no in-app prompt.

## Open decisions

Each item below needs an owner decision. Items struck through are decided.

1. ~~**Update method.**~~ Decided: Sparkle (PLO-118), replacing manual download (STA-75).
2. ~~**License.**~~ Decided (owner, STA-86): MIT. `LICENSE` is added and both READMEs link to it.
3. ~~**Minimum macOS version.**~~ Decided: macOS 14. `spec.md`, both `Package.swift` files and
   `make-app.sh` now agree.
4. **Distribution and release process.** How the DMG is built, signed, checked by
   macOS, and published is not decided on this branch. It will be described in
   `docs/release.md` (coming). The README does not claim anything about it.
5. ~~**Where the user docs are published.**~~ Decided (owner, STA-85, replacing the STA-75
   plan of a separate release repository): Plopcut is open source, so the source repository
   `github.com/chan-byeong/plopcut` is the public home. Its README and `docs/` hold the user
   docs, and the DMGs are in its GitHub Releases. It goes public after STA-86.
