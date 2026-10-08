import AppKit
import NotedropCore

/// The general pasteboard. Only touched for an explicit capture; never watched (product boundaries).
struct SystemClipboard: ClipboardAccess {
    var changeCount: Int? { NSPasteboard.general.changeCount }

    func read() throws -> ClipboardSnapshot {
        let board = NSPasteboard.general
        return ClipboardSnapshot(text: board.string(forType: .string), png: Self.pngData(from: board))
    }

    /// Text and PNG go back as one pasteboard item (checklist P-09).
    func write(_ snapshot: ClipboardSnapshot) throws {
        let board = NSPasteboard.general
        board.clearContents()
        guard snapshot.text != nil || snapshot.png != nil else { return }
        let item = NSPasteboardItem()
        if let text = snapshot.text { item.setString(text, forType: .string) }
        if let png = snapshot.png { item.setData(png, forType: .png) }
        guard board.writeObjects([item]) else { throw NotedropError("clipboard_unavailable") }
    }

    /// PNG as is, or TIFF converted to PNG (checklist K-04).
    private static func pngData(from board: NSPasteboard) -> Data? {
        if let png = board.data(forType: .png) { return png }
        guard let tiff = board.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
