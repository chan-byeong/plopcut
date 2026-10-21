# Release scope: features not included

The following features are intentionally not part of this release. They
follow the product boundaries in [AGENTS.md](../AGENTS.md) and would need an
explicit product request before they are built.

## Excluded by product boundary

- Database persistence. Drops are stored as readable files.
- Cloud sync.
- OCR (text recognition from images).
- AI features.
- Collaboration or sharing between users.
- Mobile apps.
- Continuous clipboard monitoring. The clipboard is read only when you capture.
- Full-screen recording.
- Permanent highlight overlays.
- Perfect restoration of the original source position (for example, the exact
  scroll position or selection in the source app).

## Excluded by the implementation spec

These come from [the implementation spec](swift-migration/spec.md) and the
behavior decisions it records.

- A **Shift+Cmd+V** clipboard shortcut. The PRD mentioned it, but it was never
  implemented. Clipboard capture is opened from the menu bar item
  `Save Clipboard`.
- A **capture button in the toolbar** for selected text. The frontmost app is
  Plopcut when the button is pressed, so it cannot read another app's selection.
  Use the global shortcut instead.
- **File path collection** for sources. The spec collects it only when a
  trustworthy API exists, and the legacy app did not collect it.
- **Moving or copying existing drops** when the storage folder changes. The new
  folder is used for new drops only.
