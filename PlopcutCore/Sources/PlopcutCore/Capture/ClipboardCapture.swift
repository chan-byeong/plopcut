import Foundation

/// The explicit "Save Clipboard..." capture (spec 3.2). Reads the clipboard once and never writes to it.
public struct ClipboardCapture: Sendable {
    private let clipboard: ClipboardAccess
    private let collector: SourceCollector
    private let frontmost: @Sendable () -> CaptureTarget?
    private let isplopcut: @Sendable (CaptureTarget?) -> Bool

    public init(
        clipboard: ClipboardAccess, collector: SourceCollector,
        frontmost: @escaping @Sendable () -> CaptureTarget?,
        isplopcut: @escaping @Sendable (CaptureTarget?) -> Bool
    ) {
        self.clipboard = clipboard
        self.collector = collector
        self.frontmost = frontmost
        self.isplopcut = isplopcut
    }

    public func capture() async throws -> CaptureDraft {
        let snapshot = try readSnapshot()
        var warnings: [CaptureWarning] = []

        let text = snapshot.text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        // Bytes that are not a PNG are as unusable as an image that failed to decode (K-03, S-10).
        let png = snapshot.png.flatMap { Self.isPNG($0) ? $0 : nil }
        if snapshot.imageUnreadable || (snapshot.png != nil && png == nil) {
            guard text != nil else { throw PlopcutError("clipboard_image_unavailable") }
            warnings.append(CaptureWarning("clipboard_image_unavailable"))
        }
        let type: DropType
        switch (text, png) {
        case (nil, nil): throw PlopcutError("clipboard_empty")
        case (_?, nil): type = .text
        case (nil, _?): type = .image
        case (_?, _?): type = .mixed
        }

        let target = frontmost()
        var source = DropSource()
        if !isplopcut(target) {
            let result = await collector.collect(from: target)
            source = result.source
            warnings += result.warnings
        }
        let title = Naming.inferTitle(
            windowTitle: source.windowTitle, appName: source.appName, text: text,
            fallback: type == .image ? "Image Drop" : "Untitled Drop")
        let imageTitle = type == .mixed
            ? Naming.inferTitle(windowTitle: source.windowTitle, appName: source.appName, fallback: "Image Drop") : nil
        return CaptureDraft(
            type: type, title: title, text: text, imagePNG: png, source: source, warnings: warnings,
            imageTitle: imageTitle)
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// Reads the content between two change-count samples; a difference means another app copied meanwhile (K-01).
    private func readSnapshot() throws -> ClipboardSnapshot {
        let before = clipboard.changeCount
        let snapshot: ClipboardSnapshot
        do {
            snapshot = try clipboard.read()
        } catch let error as PlopcutError {
            throw error
        } catch {
            throw PlopcutError("clipboard_unavailable", detail: error.localizedDescription)
        }
        if let before, let after = clipboard.changeCount, before != after {
            throw PlopcutError("clipboard_changed")
        }
        return snapshot
    }
}
