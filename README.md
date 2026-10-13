# plopcut

[한국어 안내 (README.ko.md)](README.ko.md)

plopcut is a local-first macOS clipboard app. You deliberately capture
selected text or a clipboard image, add a note and tags, and find it later
in the Library. Every drop is stored as ordinary readable files on your Mac.

plopcut does not watch your clipboard in the background. It reads the
clipboard or the selected text only when you ask it to capture.

> Status: pre-release. Download and signing details will be described in
> `docs/release.md` (coming).

## What you can do

- **Capture selected text** with the global shortcut (default `Shift`+`Command`+`C`).
  The shortcut is changeable in Settings.
- **Save the clipboard** from the menu bar item (`Save Clipboard...`).
- **Add a note and tags** in the save popup. You can also choose to save plain
  text instantly, without the popup, in Settings.
- **Browse the Library**: search, filter by type, tag, app, or date, and open
  a drop to edit its title, note, and tags.
- **Open the source** of a drop (for example the URL of a Chrome page), copy
  its text, export it as Markdown, or move it to the Trash.

## Install

Requirements: a Mac running macOS. The minimum supported macOS version is 14.

1. Download `plopcut.dmg` from the Releases page of the
   [plopcut repository](https://github.com/chan-byeong/plopcut). *Added with the first release.*
2. Open the disk image and drag **plopcut** into **Applications**.
3. Open plopcut from Applications.

## First run

On first launch plopcut asks where to keep your drops:

- **Use the default folder** `~/Documents/plopcut`, or
- **Choose another folder.**

The dialog stays until you confirm one of these. Changing the folder later in
Settings only affects new drops. Existing drops are not moved or copied.

## Permissions

plopcut asks for these only when a feature needs them. You can review their
status in Settings.

| Permission | Where to allow it | Why plopcut needs it |
| --- | --- | --- |
| Accessibility | System Settings › Privacy & Security › Accessibility | Reads the selected text in the app you are using and, as a fallback, sends `Command`+`C` to copy it. Selected-text capture does not work without it. |
| Automation (Google Chrome) | System Settings › Privacy & Security › Automation | Reads the URL of Chrome's active tab so the drop can keep its source link. macOS asks the first time. Without it, capture still works but the URL is not saved. |
| Clipboard | No plopcut setting. Recent macOS versions may show their own prompt when an app reads the clipboard. | Reads the clipboard only when you run `Save Clipboard...`. |

## Where your data is stored

- **Drops:** `~/Documents/plopcut/drops/<drop-id>/`, one folder per drop,
  containing `drop.json` (metadata), `content.md` or `image.png`, and `note.md`.
  You can open these files with any text editor or Finder.
- **Settings:** `~/Library/Application Support/plopcut/settings.json`.

plopcut does not use a database and does not send these files anywhere.
See [docs/privacy.md](docs/privacy.md).

## Upgrading from Notedrop

plopcut was called Notedrop before. The first time you open plopcut it moves
your data to the new locations: `~/Documents/Notedrop` to
`~/Documents/plopcut`, the settings folder in `~/Library/Application Support`,
and the log folder in `~/Library/Logs`. A storage folder you chose yourself is
not moved, and a plopcut folder that already exists is never overwritten.
macOS treats plopcut as a new app, so allow it again under **Accessibility**
and **Automation**. You can remove the old Notedrop entries there.

## Uninstall

1. Quit plopcut.
2. Move **plopcut.app** from Applications to the Trash.
3. Optional: remove the settings folder `~/Library/Application Support/plopcut`

4. Optional: remove your saved drops in `~/Documents/plopcut`. **This deletes
   your drops.** Copy the folder somewhere safe first if you want to keep them.
   Uninstalling the app does not delete them.
5. Optional: remove plopcut from **Accessibility** and **Automation** under
   System Settings › Privacy & Security.

## Privacy

All drops and settings stay on your Mac. plopcut does not send data
externally and contains no telemetry. Details and the basis for this claim:
[docs/privacy.md](docs/privacy.md).

## Log file and reporting a problem

plopcut keeps a small local log to help with support. It is a plain text file at
`~/Library/Logs/plopcut/plopcut.log` (the previous one is `plopcut.log.1`;
each file is at most about 1 MB). In plopcut, open **Settings** and choose
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
open the file first to check it. Deleting the files is safe; plopcut creates a
new one.

## Features not in this release

Database storage, cloud sync, OCR, AI features, collaboration, mobile apps,
background clipboard monitoring, full-screen recording, permanent highlight
overlays, and exact source-position restoration are intentionally excluded.
See [docs/release-scope.md](docs/release-scope.md).

## Updates

This release has no automatic update check. Download new versions manually.
See [docs/update-method.md](docs/update-method.md). plopcut is distributed as a downloadable DMG, not through the Mac App Store.

## License

**License: TBD (placeholder).** No license has been chosen yet. Until one is
chosen, all rights are reserved by the author. See the open decisions in
[docs/update-method.md](docs/update-method.md#open-decisions).

---

## For contributors

This is a from-scratch Swift (SwiftUI and AppKit) implementation. The previous
Tauri + React version is kept on `legacy/tauri` and the `tauri-final` tag, for
behavior reference only.

Start with [`AGENTS.md`](AGENTS.md), then the
[implementation spec](docs/swift-migration/spec.md) and the
[behavior checklist](docs/swift-migration/behavior-checklist.md).
`scripts/make-app.sh` builds a local `plopcut.app` bundle for development.
