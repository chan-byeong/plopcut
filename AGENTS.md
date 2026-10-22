# Plopcut

Plopcut is a local-first macOS clipboard app built with Swift (SwiftUI and
AppKit). Users deliberately capture text or images, add notes and tags, and
find saved drops in the Library.

This branch is a from-scratch Swift implementation. The previous Tauri +
React implementation is kept by the maintainer (branch `legacy/tauri`, tag
`tauri-final`) and is not published in this repository. It was a reference for
behavior only; do not port its code. The spec and the checklist are
self-contained, so contributors do not need it.

## Product boundaries

Store original drop data as readable local files. Database persistence,
cloud sync, OCR, AI features, collaboration, mobile apps, continuous
clipboard monitoring, full-screen recording, permanent highlight
overlays, and perfect source-position restoration require an explicit
user request.

Before changing capture, persistence, metadata, search, or UI behavior,
read the [implementation spec](docs/swift-migration/spec.md) and the
[behavior checklist](docs/swift-migration/behavior-checklist.md). The spec
is the source of truth for product behavior and the on-disk format.

## Engineering

Before changing the UI, read [design decisions](Design.md) and the
[design system](docs/design-system.md).

Prefer native SwiftUI and AppKit controls and system behavior (focus rings,
selection emphasis, SF Symbols, toolbars, inspectors) over custom drawing.
Keep OS integration (pasteboard, global shortcut, accessibility, Apple
Events, Trash, menu bar) behind small Swift types with protocol seams so
capture, storage, and settings logic is testable without the OS.

Keep models and storage independent of the UI.

Preserve compatibility with saved drop folders and `settings.json`. Use the
[fixtures](docs/swift-migration/fixtures/README.md) for compatibility tests
and run read/write experiments on copies, never on the user's real folder.
Avoid unrelated refactors.

`site/` is the static download site (plopcut.com, deployed by
`.github/workflows/pages.yml`). It is not part of the app: app changes do not
need site changes, and the site loads nothing from outside `site/`.

### Legacy reference

Do not read or copy the legacy implementation by default. When the spec or
checklist leaves a behavior unclear, look at one specific file or test:

```text
git show legacy/tauri:src-tauri/src/capture.rs
```

Record the answer in the spec or checklist so the next reader does not need
the legacy code.

## Completion

Use the checks relevant to the changed files: build, unit tests, and
formatting or lint tools once the project configures them. Report the exact
commands that ran. For capture, persistence, or viewer changes, manually
verify the affected save and viewer flows in the running app and compare the
UI with the reference captures. Report which checks ran and any verification
that remains incomplete.

Tick the matching items in the behavior checklist as they are verified.

Complete the issue workflow described in the tracker configuration before
reporting a task as finished.

## Agent skills

Agent skills are installed locally by each maintainer in `.agents/skills/`
and are not part of this repository (the folder is git-ignored). Read the
relevant installed skill when its task matches the user's request. If your
agent has none installed, follow this file and the linked docs directly.

### Issue tracker

Every task must be based on a Linear issue in the `Plopcut Beta` project, including
implementation, bug fixes, refactoring, documentation, research, and
reviews. Before starting work, read
[issue tracker rules](docs/agents/issue-tracker.md), fetch or create the
issue, and report its identifier and URL. Start task work only after the
issue exists and its scope and acceptance criteria are understood.

### Triage labels

Use the five canonical triage labels. Before triaging issues, read
[triage labels](docs/agents/triage-labels.md).

### Domain docs

Use a single-context layout. Before exploring domain behavior or proposing
architecture changes, read [domain docs](docs/agents/domain.md).
