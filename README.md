# Notedrop (Swift)

Notedrop is a local-first macOS clipboard app. Users deliberately capture
text or images, add notes and tags, and find saved drops in the Library.

This branch (`swift/main`) is a from-scratch Swift (SwiftUI and AppKit)
implementation tracked by [STA-40](https://linear.app/byeoung/issue/STA-40).
It starts as an orphan branch with no Tauri, React, or Rust code. The
previous implementation is preserved on `legacy/tauri` and the `tauri-final`
tag.

Start with [`AGENTS.md`](AGENTS.md), then the
[implementation spec](docs/swift-migration/spec.md) and the
[behavior checklist](docs/swift-migration/behavior-checklist.md).
