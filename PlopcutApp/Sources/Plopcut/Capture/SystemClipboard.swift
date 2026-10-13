import AppKit
import PlopcutCore

/// The general pasteboard. Only touched for an explicit capture; never watched (product boundaries).
struct SystemClipboard: ClipboardAccess {
    var changeCount: Int? { NSPasteboard.general.changeCount }

    func read() throws -> ClipboardSnapshot {
        let board = NSPasteboard.general
        let image = Self.image(from: board)
        return ClipboardSnapshot(text: board.string(forType: .string), png: image.png, imageUnreadable: image.unreadable)
    }

    /// Text and PNG go back as one pasteboard item (checklist P-09).
    func write(_ snapshot: ClipboardSnapshot) throws {
        let board = NSPasteboard.general
        board.clearContents()
        guard snapshot.text != nil || snapshot.png != nil else { return }
        let item = NSPasteboardItem()
        if let text = snapshot.text { item.setString(text, forType: .string) }
        if let png = snapshot.png { item.setData(png, forType: .png) }
        guard board.writeObjects([item]) else { throw PlopcutError("clipboard_unavailable") }
    }

    /// PNG as is, or TIFF converted to PNG (checklist K-04). `unreadable` means an image is there but can't be used (K-03).
    private static func image(from board: NSPasteboard) -> (png: Data?, unreadable: Bool) {
        if let png = board.data(forType: .png) { return (png, false) }
        guard let tiff = board.data(forType: .tiff) else { return (nil, false) }
        guard let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            return (nil, true)
        }
        return (png, false)
    }
}
