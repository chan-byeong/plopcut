import Foundation

/// The explicit "Save Clipboard..." capture (spec 3.2). Reads the clipboard once and never writes to it.
public struct ClipboardCapture: Sendable {
    private let clipboard: ClipboardAccess
    private let collector: SourceCollector
    private let frontmost: @Sendable () -> CaptureTarget?
    private let isNotedrop: @Sendable (CaptureTarget?) -> Bool

    public init(
        clipboard: ClipboardAccess, collector: SourceCollector,
        frontmost: @escaping @Sendable () -> CaptureTarget?,
        isNotedrop: @escaping @Sendable (CaptureTarget?) -> Bool
    ) {
        self.clipboard = clipboard
        self.collector = collector
        self.frontmost = frontmost
        self.isNotedrop = isNotedrop
    }

    public func capture() async throws -> CaptureDraft {
        let snapshot = try readSnapshot()
        var warnings: [CaptureWarning] = []

        let text = snapshot.text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        if snapshot.imageUnreadable {
            guard text != nil else { throw NotedropError("clipboard_image_unavailable") }
            warnings.append(CaptureWarning("clipboard_image_unavailable"))
        }
        guard let text else {
            // Image-only content can't be saved until image drops are wired in (STA-57).
            throw NotedropError(snapshot.png == nil ? "clipboard_empty" : "clipboard_image_unsupported")
        }

        let target = frontmost()
        var source = DropSource()
        if !isNotedrop(target) {
            let result = await collector.collect(from: target)
            source = result.source
            warnings += result.warnings
        }
        let title = Naming.inferTitle(windowTitle: source.windowTitle, appName: source.appName, text: text)
        return CaptureDraft(type: .text, title: title, text: text, source: source, warnings: warnings)
    }

    /// Reads the content between two change-count samples; a difference means another app copied meanwhile (K-01).
    private func readSnapshot() throws -> ClipboardSnapshot {
        let before = clipboard.changeCount
        let snapshot: ClipboardSnapshot
        do {
            snapshot = try clipboard.read()
        } catch let error as NotedropError {
            throw error
        } catch {
            throw NotedropError("clipboard_unavailable", detail: error.localizedDescription)
        }
        if let before, let after = clipboard.changeCount, before != after {
            throw NotedropError("clipboard_changed")
        }
        return snapshot
    }
}
