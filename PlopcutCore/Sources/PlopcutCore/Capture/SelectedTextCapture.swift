import Foundation

/// Selected-text capture (spec 3.1): accessibility read first, clipboard round trip as the fallback.
public struct SelectedTextCapture: Sendable {
    public static let pollInterval = Duration.milliseconds(25)
    public static let timeout = Duration.milliseconds(700)
    static let maxPolls = 28  // timeout / pollInterval

    private let reader: any SelectedTextReader
    private let clipboard: any ClipboardAccess
    private let sender: any CopyShortcutSender
    private let collector: any SourceCollector
    private let frontmost: @Sendable () -> CaptureTarget?
    private let sleep: @Sendable (Duration) async -> Void

    public init(
        reader: any SelectedTextReader, clipboard: any ClipboardAccess, sender: any CopyShortcutSender,
        collector: any SourceCollector, frontmost: @escaping @Sendable () -> CaptureTarget?,
        sleep: @escaping @Sendable (Duration) async -> Void
    ) {
        self.reader = reader
        self.clipboard = clipboard
        self.sender = sender
        self.collector = collector
        self.frontmost = frontmost
        self.sleep = sleep
    }

    public func capture() async throws -> CaptureDraft {
        // The frontmost app at this moment is the origin. It is pinned once so source and selection can't come from
        // different apps if focus moves mid-capture; source goes first (checklist P-01).
        let target = frontmost()
        let sourceResult = await collector.collect(from: target)
        var warnings = sourceResult.warnings

        let raw: String
        if let selected = reader.readSelection(in: target), !Self.isBlank(selected) {
            raw = selected
        } else {
            let fallback = try await readThroughClipboard()
            raw = fallback.text
            warnings += fallback.warnings
        }

        let text = Self.trimTrailingLineBreaks(raw)
        guard !Self.isBlank(text) else { throw PlopcutError("no_selected_text") }

        let source = sourceResult.source
        let title = Naming.inferTitle(windowTitle: source.windowTitle, appName: source.appName, text: text)
        return CaptureDraft(type: .text, title: title, text: text, source: source, warnings: warnings)
    }

    // MARK: clipboard fallback (checklist P-02..P-09)

    private struct FallbackResult {
        var text: String
        var warnings: [CaptureWarning]
    }

    private func readThroughClipboard() async throws -> FallbackResult {
        var warnings: [CaptureWarning] = []
        var backup = ClipboardSnapshot()
        var backupFailed = false
        do {
            backup = try clipboard.read()
        } catch {
            backupFailed = true
            warnings.append(CaptureWarning("clipboard_backup_failed"))
        }
        let before = clipboard.changeCount

        let copied: String
        do {
            copied = try await copySelection(backup: backup, changeCountBefore: before)
        } catch {
            // Nothing was copied (permission, timeout, empty selection): the clipboard is untouched, and restoring
            // would rewrite it as text and PNG only, dropping files, RTF or extra items.
            if clipboardMayHaveChanged(since: before) { _ = restore(backup) }
            throw error
        }

        if !restore(backup) || backupFailed {
            // An unrestorable or incomplete backup means the original clipboard is not back.
            warnings.append(CaptureWarning("clipboard_restore_failed"))
        }
        return FallbackResult(text: copied, warnings: warnings)
    }

    private func copySelection(backup: ClipboardSnapshot, changeCountBefore: Int?) async throws -> String {
        do {
            try sender.sendCopy()
        } catch let error as PlopcutError where error.code.hasPrefix("automation_") {
            throw PlopcutError(
                "permission_missing",
                detail: "Allow Plopcut in System Settings > Privacy & Security > Accessibility.")
        }

        var changed = hasChanged(since: changeCountBefore, backup: backup)
        var polls = 0
        while !changed && polls < Self.maxPolls {
            await sleep(Self.pollInterval)
            polls += 1
            changed = hasChanged(since: changeCountBefore, backup: backup)
        }
        guard changed else { throw PlopcutError("no_selected_text") }

        do {
            return try clipboard.read().text ?? ""
        } catch let error as PlopcutError {
            throw error
        } catch {
            throw PlopcutError("clipboard_unavailable")
        }
    }

    /// With a change count, any difference counts, even if the copied text equals the old clipboard (P-03).
    /// Without one, only a different text proves the copy happened.
    private func hasChanged(since before: Int?, backup: ClipboardSnapshot) -> Bool {
        if let before, let now = clipboard.changeCount { return now != before }
        guard let snapshot = try? clipboard.read() else { return false }
        return snapshot.text != backup.text
    }

    /// Without a change count there is no proof either way, so assume it changed.
    private func clipboardMayHaveChanged(since before: Int?) -> Bool {
        guard let before, let now = clipboard.changeCount else { return true }
        return now != before
    }

    /// Returns `false` when the original clipboard could not be put back.
    private func restore(_ backup: ClipboardSnapshot) -> Bool {
        do { try clipboard.write(backup); return true } catch { return false }
    }

    // MARK: text rules (checklist P-07)

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func trimTrailingLineBreaks(_ text: String) -> String {
        var scalars = Substring(text)
        while let last = scalars.last, last == "\n" || last == "\r" || last == "\r\n" { scalars = scalars.dropLast() }
        return String(scalars)
    }
}
