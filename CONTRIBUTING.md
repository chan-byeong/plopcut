# Contributing to Plopcut

Thanks for helping. Plopcut is a small local-first macOS app, so changes are
reviewed against a short list of product rules. Read this page before you open
a pull request.

## Ground rules

- Be kind. Everyone follows the [Code of Conduct](CODE_OF_CONDUCT.md).
- Report security problems privately, not in a public issue. See [SECURITY.md](SECURITY.md).
- Open an issue before you start work that changes behavior or adds a feature, so
  we can agree on scope first. Small fixes and docs can go straight to a pull request.

## What fits the project

Plopcut stores what you deliberately capture as readable local files. These are
**out of scope** unless a maintainer asks for them: database storage, cloud sync,
OCR, AI features, collaboration, mobile apps, continuous clipboard monitoring,
full-screen recording, permanent highlight overlays, and exact source-position
restoration. See [docs/release-scope.md](docs/release-scope.md).

The on-disk format of drops and `settings.json` is a compatibility contract. Do not
change it. The [implementation spec](docs/swift-migration/spec.md) is the source of
truth, and the [fixtures](docs/swift-migration/fixtures/README.md) are for
compatibility tests. Run read/write experiments on copies, never on your real folder.

## Build and test

You need macOS 14 or later and a Swift 6 toolchain (Xcode).

```sh
cd PlopcutCore && swift build && swift test
cd ../PlopcutApp && swift build && swift test
sh scripts/make-app.sh debug      # builds PlopcutApp/.build/Plopcut.app
open PlopcutApp/.build/Plopcut.app
```

Running the packaged app **moves** a pre-rebrand `~/Documents/Notedrop`, the
settings folder, and the log folder to their Plopcut names (see spec section 1.9). Back
those up first if you used an older build. `swift test` and `swift run` never touch your
real folders. The app asks for Accessibility and Automation permission when you capture.

## Making a change

1. Fork the repository and branch from `swift/main`.
2. Keep the change focused. Avoid unrelated refactors.
3. Add or update tests. Capture, storage, and settings logic sits behind small
   protocol seams so it can be tested without the OS.
4. Update the spec and the behavior checklist when behavior changes.
5. For UI work, read [Design.md](Design.md) and the [design system](docs/design-system.md).
6. Make sure `swift test` passes in both packages. CI runs the same checks.
7. Open a pull request and fill in the template.

Commit messages start with a type and a short description, for example
`fix: keep the selection when the list refreshes`. Types: feat, fix, refactor, docs,
test, chore, perf, ci.

## Issues

Use GitHub Issues for bugs and ideas. For a bug, include your macOS version, the
Plopcut version, what you did, and what happened. Attach `plopcut.log` if it
helps (Settings → Show Log in Finder); it holds no drop text, notes, or paths.
Maintainers track accepted work internally as `PLO-<number>` (older work as `STA-<number>`); you do not need an account for that.

## License

By contributing you agree that your contribution is licensed under the
[MIT License](LICENSE).
