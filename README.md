# Notedrop

[한국어 안내 (README.ko.md)](README.ko.md)

Notedrop is a local-first macOS clipboard app. You deliberately capture
selected text or a clipboard image, add a note and tags, and find it later
in the Library. Every drop is stored as ordinary readable files on your Mac.

Notedrop does not watch your clipboard in the background. It reads the
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

Requirements: a Mac running macOS. The minimum supported macOS version is
still to be confirmed (see [docs/update-method.md](docs/update-method.md#open-decisions)).

1. Download `Notedrop.dmg` from the release page. *Link: coming with the
   first release (see `docs/release.md`, coming).*
2. Open the disk image and drag **Notedrop** into **Applications**.
3. Open Notedrop from Applications.

## First run

On first launch Notedrop asks where to keep your drops:

- **Use the default folder** `~/Documents/Notedrop`, or
- **Choose another folder.**

The dialog stays until you confirm one of these. Changing the folder later in
Settings only affects new drops. Existing drops are not moved or copied.

## Permissions

Notedrop asks for these only when a feature needs them. You can review their
status in Settings.

| Permission | Where to allow it | Why Notedrop needs it |
| --- | --- | --- |
| Accessibility | System Settings › Privacy & Security › Accessibility | Reads the selected text in the app you are using and, as a fallback, sends `Command`+`C` to copy it. Selected-text capture does not work without it. |
| Automation (Google Chrome) | System Settings › Privacy & Security › Automation | Reads the URL of Chrome's active tab so the drop can keep its source link. macOS asks the first time. Without it, capture still works but the URL is not saved. |
| Clipboard | No Notedrop setting. Recent macOS versions may show their own prompt when an app reads the clipboard. | Reads the clipboard only when you run `Save Clipboard...`. |

## Where your data is stored

- **Drops:** `~/Documents/Notedrop/drops/<drop-id>/`, one folder per drop,
  containing `drop.json` (metadata), `content.md` or `image.png`, and `note.md`.
  You can open these files with any text editor or Finder.
- **Settings:** `~/Library/Application Support/Notedrop/settings.json`.

Notedrop does not use a database and does not send these files anywhere.
See [docs/privacy.md](docs/privacy.md).

## Uninstall

1. Quit Notedrop.
2. Move **Notedrop.app** from Applications to the Trash.
3. Optional: remove the settings folder `~/Library/Application Support/Notedrop`.
4. Optional: remove your saved drops in `~/Documents/Notedrop`. **This deletes
   your drops.** Copy the folder somewhere safe first if you want to keep them.
   Uninstalling the app does not delete them.
5. Optional: remove Notedrop from **Accessibility** and **Automation** under
   System Settings › Privacy & Security.

## Privacy

All drops and settings stay on your Mac. Notedrop does not send data
externally and contains no telemetry. Details and the basis for this claim:
[docs/privacy.md](docs/privacy.md).

## Features not in this release

Database storage, cloud sync, OCR, AI features, collaboration, mobile apps,
background clipboard monitoring, full-screen recording, permanent highlight
overlays, and exact source-position restoration are intentionally excluded.
See [docs/release-scope.md](docs/release-scope.md).

## Updates

This release has no automatic update check. Download new versions manually.
This is the proposed default and needs owner confirmation; see
[docs/update-method.md](docs/update-method.md).

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
`scripts/make-app.sh` builds a local `Notedrop.app` bundle for development.
