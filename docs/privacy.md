# Privacy

Plopcut keeps everything on your Mac.

- **All data stays local.** Drops, notes, tags, and settings are files in your
  storage folder (default `~/Documents/plopcut`) and in
  `~/Library/Application Support/plopcut/`.
- **Nothing is sent externally.** The app has no code that uploads or syncs data.
- **One kind of network request: the update check.** Since PLO-118 the app asks
  `https://plopcut.com/appcast.xml` whether a new version exists, and downloads
  the new DMG from GitHub Releases when you install it. See
  [Update checks](#update-checks) for exactly what is sent.
- **No telemetry.** The app contains no analytics, crash reporting, or usage tracking.
- **No accounts, no cloud, no database.**

## Support log (local only)

Plopcut writes a small log to `~/Library/Logs/plopcut/plopcut.log` (one
previous file, `plopcut.log.1`; about 1 MB each). It stays on your Mac and is
never uploaded. Settings has a `Show Log in Finder` row.

- **Contains:** timestamp, app version, build and macOS version at start, the
  code of errors shown to you, in an alert or inline (a failed autosave or a
  failed save in the save popup), such as `storage_unreadable`, `permission_missing`,
  `save_failed`), and permission status changes.
- **Never contains:** drop text, images, notes, titles, tags, URLs, clipboard
  data, or file paths. The log API accepts only fixed event types, and error
  details are dropped, so only the code is written (covered by unit tests).
- **Reporting a problem:** attach the log file to your message yourself. There
  is no automatic report.

## Update checks

Plopcut uses [Sparkle](https://sparkle-project.org/) to check for and install
updates (PLO-118, [update-method.md](update-method.md)).

- **When.** Automatic checks are **on by default** (`SUEnableAutomaticChecks`
  in `Info.plist`): about once a day, without asking first. Turn them off with
  the `Check for updates automatically` switch in Settings › About; then no
  request is made unless you choose `Check for Updates` in the app menu, the
  menu bar menu, or Settings.
- **What is sent.** A plain HTTPS `GET` for the appcast. Like any web request it
  carries your IP address and a User-Agent with the app and Sparkle version
  (for example `Plopcut/1.0.0 Sparkle/2.10.0`). System profiling is turned off
  in `Info.plist` (`SUEnableSystemProfiling`), so no Mac model, macOS version,
  or other system details are added. No drops, notes, tags, settings, or
  identifiers are sent.
- **Where.** The appcast is a static file on plopcut.com (GitHub Pages). The
  update itself is downloaded from `github.com/chan-byeong/plopcut` Releases.
  Both hosts keep their own server logs; Plopcut runs no server of its own.
- **Integrity.** Every update must carry an EdDSA signature that matches the
  public key in the app (`SUPublicEDKey`), and a valid Developer ID signature
  from the same team. Sparkle refuses anything else.
- **Where the choice is stored.** Sparkle keeps its own preferences (automatic
  checks, last check time) in the app's user defaults
  (`~/Library/Preferences/com.plopcut.app.plist`), not in `settings.json`.

## What Plopcut reads, and when

- The **selected text** of the frontmost app, only when you press the capture
  shortcut or choose a capture command.
- The **clipboard**, only when you run `Save Clipboard`. Plopcut does not
  monitor the clipboard in the background.
- The **frontmost app name, window title**, and, for Google Chrome only, the
  **URL of the active tab**, at the moment of capture. macOS asks for Automation
  permission the first time this happens.

## Basis for the claim: static check of the source

Checked on branch `sta-81` at commit `0e8c2ac`, and again for 0.2.0 on
`swift/main` at commit `dbab98a` (PLO-106). These are static checks of the
tracked Swift, shell, and plist files. They are not a runtime network trace.

Searched for network and telemetry APIs and SDKs (`URLSession`, `NSURLSession`,
`URLRequest`, `NWConnection`, `NWListener`, `CFNetwork`, `import Network`,
`WKWebView`, `WebKit`, `dataTask`, `downloadTask`, Sparkle, analytics, telemetry,
crash reporters such as Crashlytics, Sentry, and Firebase, and `http(s)://` URLs).

Result: **no matches in the app or core sources** (`PlopcutApp/Sources`,
`PlopcutCore/Sources`). The only `http` string in the app-related files is the
DTD URL inside the `Info.plist` template in `scripts/make-app.sh`. It is XML
metadata and is not requested at runtime.

Other findings:

- **One dependency with network code: Sparkle** (PLO-118). It is the only code
  in the app that makes network requests, as described in
  [Update checks](#update-checks). Its XPC services are removed from the
  bundle because the app is not sandboxed.
- **Three rendering dependencies, no network code.** Since 0.2.0,
  `PlopcutApp/Package.swift` depends on `swift-markdown` (which brings
  `swift-cmark`) to render Markdown, and on `HighlighterSwift`, which runs the
  bundled highlight.js in JavaScriptCore to color code blocks. The same search
  over their sources (`.build/checkouts`) finds no network API, and
  highlight.js has no `fetch` or `XMLHttpRequest` call. Their licenses are in
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
  `PlopcutCore/Package.swift` has no dependencies.
- **Markdown never loads remote content.** Images in a drop's Markdown are
  shown as text and never downloaded. A link opens in your browser only when
  you click it (`http`, `https`, and `mailto` only).
- **Local file access only.** Drops and settings are read and written with
  `FileManager`, `Data(contentsOf:)`, and `String(contentsOf:)` on local paths.
- **Chrome URL read is local IPC.** The app runs an AppleScript (`NSAppleScript`)
  that asks Google Chrome for its active tab URL. This is an Apple Event to a
  process on the same Mac.
- **User-initiated URL opening.** `NSWorkspace.shared.open` opens a stored
  source URL when you click `Open Source`, and opens System Settings when you
  choose to review permissions. The browser that opens makes its own network
  requests. That traffic is the browser's, not Plopcut's.

## What this does not cover

- Behavior of macOS, Google Chrome, or the browser you open a source link in.
- Network activity that does not come from the app's code (for example, the
  system's own services).
- Future code. Repeat the check before each release, and update this document
  if another network API or SDK is added.

## Re-check before each release

```sh
git grep -n -E 'URLSession|NSURLSession|URLRequest|NWConnection|NWListener|CFNetwork|import Network|WKWebView|WebKit|dataTask|downloadTask|Sparkle|Analytics|Telemetry|Crashlytics|Sentry|Firebase|https?://' -- '*.swift' '*.sh' '*.plist' 'Package.swift'
```

Expected matches outside tests (checked for PLO-118): the package URLs in
`PlopcutApp/Package.swift`; `Sparkle` in `PlopcutApp/Sources/Plopcut/Updates/`
(`import Sparkle` only in `SparkleUpdater.swift`), in `PlopcutApp.swift`, and in a
comment in `SettingsView.swift`; the appcast URL in `scripts/app-config.sh`; the
framework steps and the plist DTD URL in `scripts/make-app.sh`; and the download
URL in `scripts/release.sh`. Anything else needs this document updated.

Also confirm that `dependencies:` lists in every `Package.swift` contain only
the local package, Sparkle, and the three rendering packages named above, unless
this document is updated. When a dependency is added or its version changes, run the same
search over `PlopcutApp/.build/checkouts` and update
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
