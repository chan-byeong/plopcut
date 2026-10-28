# Plopcut

[한국어 안내 (README.ko.md)](README.ko.md)

Plopcut is a local-first macOS clipboard app. You deliberately capture
selected text or a clipboard image, add a note and tags, and find it later
in the Library. Every drop is stored as ordinary readable files on your Mac.

Plopcut does not watch your clipboard in the background. It reads the
clipboard or the selected text only when you ask it to capture.

> **Beta.** Plopcut is in beta. The beta build is **not signed or notarized by
> Apple**, so macOS blocks it the first time you open it (see
> [Install](#install)). An official signed release will follow after testing.
> Please report problems in [GitHub Issues](https://github.com/chan-byeong/plopcut/issues).

## What you can do

- **Capture selected text** with the global shortcut (default `Shift`+`Command`+`C`).
  The shortcut is changeable in Settings.
- **Save the clipboard** from the menu bar item (`Save Clipboard`).
- **Add a title, a note, and tags** in the save popup. The title is filled in
  for you and can be changed or reset to the automatic one. You can also choose
  to save plain text instantly, without the popup, in Settings.
- **Browse the Library**: search, filter by type or tag, and narrow by source
  (websites such as `github.com`, or apps such as Google Chrome or Terminal;
  pick several at once) and date.
- **Read drops formatted**: Markdown shows headings, lists, and code blocks;
  code is highlighted and has a copy button. If the format is guessed wrong,
  change it from the format menu. The saved file stays as it was.
- **Edit a drop**: change its title, note, and tags, or edit the text itself
  with `Command`+`E`. Saving an edit overwrites `content.md`; the earlier text
  is not kept.
- **Pin drops** you use often (`Shift`+`Command`+`P`). Pinned drops stay at the
  top of the list and in the sidebar's Pinned collection.
- **Open the source** of a drop (for example the URL of a Chrome page), copy
  its text, export it as Markdown, or move it to the Trash.

## Install

Requirements: a Mac running macOS. The minimum supported macOS version is 14.

1. Download the latest `Plopcut-<version>-beta.<n>.dmg` from the
   [Releases page](https://github.com/chan-byeong/plopcut/releases) (beta builds are marked Pre-release).
   *Added with the first beta.*
2. Open the disk image and drag **Plopcut** into **Applications**.
3. Try to open Plopcut. macOS refuses because the beta is not notarized. Allow it once:
   - Open **System Settings › Privacy & Security**, scroll to the message about
     Plopcut, and choose **Open Anyway**. (On macOS 15 and later, right-click › Open
     no longer works.)
   - Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Plopcut.app`
4. Allow **Accessibility** and **Automation** when Plopcut asks (see Permissions below).

You can also build it yourself: `sh scripts/make-app.sh release`, then open
`PlopcutApp/.build/Plopcut.app`. This needs Xcode and the Swift 6 toolchain.

**Permissions after an update.** Beta builds are signed ad hoc, so the signature
changes with every build and macOS may forget the Accessibility or Automation
permission. If capture stops working after an update, run
`tccutil reset Accessibility com.plopcut.app` and allow Plopcut again. You will
need to allow it once more when the signed official release replaces the beta.
Your drops and settings are not affected.

## First run

On first launch Plopcut asks where to keep your drops:

- **Use the default folder** `~/Documents/plopcut`, or
- **Choose another folder.**

The dialog stays until you confirm one of these. Changing the folder later in
Settings only affects new drops. Existing drops are not moved or copied.

## Permissions

Plopcut asks for these only when a feature needs them. You can review their
status in Settings.

| Permission | Where to allow it | Why Plopcut needs it |
| --- | --- | --- |
| Accessibility | System Settings › Privacy & Security › Accessibility | Reads the selected text in the app you are using and, as a fallback, sends `Command`+`C` to copy it. Selected-text capture does not work without it. |
| Automation (Google Chrome) | System Settings › Privacy & Security › Automation | Reads the URL of Chrome's active tab so the drop can keep its source link. macOS asks the first time. Without it, capture still works but the URL is not saved. |
| Clipboard | No Plopcut setting. Recent macOS versions may show their own prompt when an app reads the clipboard. | Reads the clipboard only when you run `Save Clipboard`. |

## Where your data is stored

- **Drops:** `~/Documents/plopcut/drops/<drop-id>/`, one folder per drop,
  containing `drop.json` (metadata, including when it was pinned and the format
  you chose), `content.md` or `image.png`, and `note.md`.
  You can open these files with any text editor or Finder.
- **Settings:** `~/Library/Application Support/plopcut/settings.json`.

Plopcut does not use a database and does not send these files anywhere.
See [docs/privacy.md](docs/privacy.md).

## Uninstall

1. Quit Plopcut.
2. Move **Plopcut.app** from Applications to the Trash.
3. Optional: remove the settings folder `~/Library/Application Support/plopcut`

4. Optional: remove your saved drops in `~/Documents/plopcut`. **This deletes
   your drops.** Copy the folder somewhere safe first if you want to keep them.
   Uninstalling the app does not delete them.
5. Optional: remove Plopcut from **Accessibility** and **Automation** under
   System Settings › Privacy & Security.

## Privacy

All drops and settings stay on your Mac. Plopcut does not send data
externally and contains no telemetry. Its only network request is the update
check, which sends no data about you or your drops. Details and the basis for this claim:
[docs/privacy.md](docs/privacy.md).

## Log file and reporting a problem

Plopcut keeps a small local log to help with support. It is a plain text file at
`~/Library/Logs/plopcut/plopcut.log` (the previous one is `plopcut.log.1`;
each file is at most about 1 MB). In Plopcut, open **Settings** and choose
**Show Log in Finder**.

- **It stays on your Mac.** Nothing is uploaded or sent automatically.
- **It contains only:** a timestamp, app version, build and macOS version at
  start, the code of an error that was shown to you, in an alert or inline such as a
  failed autosave or a failed save in the save popup (for example
  `storage_unreadable`, `permission_missing`, `save_failed`), and permission
  status changes.
- **It never contains** drop text, images, notes, titles, tags, URLs, clipboard
  data or file paths.

To report a problem, attach `plopcut.log` (and `plopcut.log.1` if it exists)
to your message yourself, with a short description of what you did. You can
open the file first to check it. Deleting the files is safe; Plopcut creates a
new one.

## Features not in this release

Database storage, cloud sync, OCR, AI features, collaboration, mobile apps,
background clipboard monitoring, full-screen recording, permanent highlight
overlays, and exact source-position restoration are intentionally excluded.
See [docs/release-scope.md](docs/release-scope.md).

## Updates

Plopcut updates itself with [Sparkle](https://sparkle-project.org/). It checks for updates automatically
about once a day; you can turn this off in Settings › About, or choose
**Check for Updates** in the app menu or the menu bar menu at any time. Each update is verified with an
EdDSA signature before it is installed. Builds before this feature have no updater, so download one new
version manually once. See [docs/update-method.md](docs/update-method.md). Plopcut is distributed as a
downloadable DMG, not through the Mac App Store.

## License

Plopcut is open source under the [MIT License](LICENSE). It includes
open-source packages for Markdown rendering and code highlighting; their
licenses are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), which is also
inside the app (`Plopcut.app/Contents/Resources`). Contributions are
welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Report security problems
privately as described in [SECURITY.md](SECURITY.md).

---

## For contributors

This is a from-scratch Swift (SwiftUI and AppKit) implementation. An earlier
Tauri + React prototype is not part of this repository; the spec and the
behavior checklist record the behavior you need.

Start with [`AGENTS.md`](AGENTS.md), then the
[implementation spec](docs/swift-migration/spec.md) and the
[behavior checklist](docs/swift-migration/behavior-checklist.md).
`scripts/make-app.sh` builds a local `Plopcut.app` bundle for development.
