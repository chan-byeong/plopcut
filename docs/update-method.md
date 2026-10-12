# Update method and open decisions

Status: **decided — manual download (owner, STA-75).**

## Decision: manual download

Notedrop checks for updates **never**. Users download the new `Notedrop.dmg`
from the release page and replace the app.

Reasons:

- It matches the privacy claim in [privacy.md](privacy.md). The app makes no
  network calls, so it needs no update server, no appcast, and no
  update-check telemetry.
- It adds no dependency. The app has no third-party packages today.
- It needs no update signing keys to manage or lose.

Trade-off: users must notice new versions themselves. There is no in-app prompt,
so adoption of fixes may be slow.

## Alternative: Sparkle automatic updates (not chosen)

[Sparkle](https://sparkle-project.org/) is the common macOS framework for
in-app updates.

What it would require:

- An **appcast** feed hosted at a public HTTPS URL, and a signed update archive
  for each release.
- EdDSA signing keys, which must be generated, stored safely, and used for every
  release.
- A new third-party dependency, and a network request from the app on a schedule
  or on demand.

Trade-offs:

- **Pro:** users receive updates without action, and fixes reach them faster.
- **Con:** the app would make network requests, so the privacy document and the
  README would need to change. The "no network calls" claim would no longer hold.
- **Con:** key management and release automation become part of the release
  process.
- **Con:** Sparkle's own behavior (update checks, optional system profile reports)
  must be reviewed and configured to match the privacy claim before use.

If the owner chooses Sparkle, update [privacy.md](privacy.md) and the README
first, then implement the update flow as its own issue.

## Open decisions

Each item below needs an owner decision. Items struck through are decided.

1. ~~**Update method.**~~ Decided: manual download.
2. **License.** **TBD (placeholder).** No license has been chosen. The README
   says all rights are reserved until one is chosen. The owner must pick a
   license and add a `LICENSE` file.
3. ~~**Minimum macOS version.**~~ Decided: macOS 14. `spec.md`, both `Package.swift` files and
   `make-app.sh` now agree.
4. **Distribution and release process.** How the DMG is built, signed, checked by
   macOS, and published is not decided on this branch. It will be described in
   `docs/release.md` (coming). The README does not claim anything about it.
5. **Where the user docs are published.** The issue requires the user docs to be
   published at the release location. That location is not chosen yet.
