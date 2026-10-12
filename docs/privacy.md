# Privacy

Notedrop keeps everything on your Mac.

- **All data stays local.** Drops, notes, tags, and settings are files in your
  storage folder (default `~/Documents/Notedrop`) and in
  `~/Library/Application Support/Notedrop/`.
- **Nothing is sent externally.** The app has no code that uploads or syncs data.
- **No telemetry.** The app contains no analytics, crash reporting, or usage tracking.
- **No accounts, no cloud, no database.**

## Support log (local only)

Notedrop writes a small log to `~/Library/Logs/Notedrop/notedrop.log` (one
previous file, `notedrop.log.1`; about 1 MB each). It stays on your Mac and is
never uploaded. Settings has a `Show Log in Finder` row.

- **Contains:** timestamp, app version, build and macOS version at start, the
  code of errors shown to you (such as `storage_unreadable`, `permission_missing`,
  `save_failed`), and permission status changes.
- **Never contains:** drop text, images, notes, titles, tags, URLs, clipboard
  data, or file paths. The log API accepts only fixed event types, and error
  details are dropped, so only the code is written (covered by unit tests).
- **Reporting a problem:** attach the log file to your message yourself. There
  is no automatic report.

## What Notedrop reads, and when

- The **selected text** of the frontmost app, only when you press the capture
  shortcut or choose a capture command.
- The **clipboard**, only when you run `Save Clipboard...`. Notedrop does not
  monitor the clipboard in the background.
- The **frontmost app name, window title**, and, for Google Chrome only, the
  **URL of the active tab**, at the moment of capture. macOS asks for Automation
  permission the first time this happens.

## Basis for the claim: static check of the source

Checked on branch `sta-81` at commit `0e8c2ac`. These are static checks of the
tracked Swift, shell, and plist files. They are not a runtime network trace.

Searched for network and telemetry APIs and SDKs (`URLSession`, `NSURLSession`,
`URLRequest`, `NWConnection`, `NWListener`, `CFNetwork`, `import Network`,
`WKWebView`, `WebKit`, `dataTask`, `downloadTask`, Sparkle, analytics, telemetry,
crash reporters such as Crashlytics, Sentry, and Firebase, and `http(s)://` URLs).

Result: **no matches in the app or core sources** (`NotedropApp/Sources`,
`NotedropCore/Sources`). The only `http` string in the app-related files is the
DTD URL inside the `Info.plist` template in `scripts/make-app.sh`. It is XML
metadata and is not requested at runtime.

Other findings:

- **No third-party dependencies.** `NotedropApp/Package.swift` depends only on the
  local package `../NotedropCore`. `NotedropCore/Package.swift` has no dependencies.
- **Local file access only.** Drops and settings are read and written with
  `FileManager`, `Data(contentsOf:)`, and `String(contentsOf:)` on local paths.
- **Chrome URL read is local IPC.** The app runs an AppleScript (`NSAppleScript`)
  that asks Google Chrome for its active tab URL. This is an Apple Event to a
  process on the same Mac.
- **User-initiated URL opening.** `NSWorkspace.shared.open` opens a stored
  source URL when you click `Open Source`, and opens System Settings when you
  choose to review permissions. The browser that opens makes its own network
  requests. That traffic is the browser's, not Notedrop's.

## What this does not cover

- Behavior of macOS, Google Chrome, or the browser you open a source link in.
- Network activity that does not come from the app's code (for example, the
  system's own services).
- Future code. Repeat the check before each release, and update this document
  if a network API or SDK is added.

## Re-check before each release

```sh
git grep -n -E 'URLSession|NSURLSession|URLRequest|NWConnection|NWListener|CFNetwork|import Network|WKWebView|WebKit|dataTask|downloadTask|Sparkle|Analytics|Telemetry|Crashlytics|Sentry|Firebase|https?://' -- '*.swift' '*.sh' '*.plist' 'Package.swift'
```

Also confirm that `dependencies:` lists in every `Package.swift` contain only
local packages, unless this document is updated.
