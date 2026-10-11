import AppKit
import NotedropCore
import SwiftUI
import Testing
@testable import Notedrop

/// The compact Save Popup (STA-67): small for a plain draft, taller instead of cut off when rows are added.
@MainActor
@Suite(.serialized) struct SavePopupLayoutTests {
    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    private func model(_ draft: CaptureDraft, recent: [String] = ["alpha", "beta", "gamma"]) -> SavePopupModel {
        SavePopupModel(draft: draft, recentTags: recent, save: { _ in throw CancellationError() }, onSaved: { _ in }, onCancel: {})
    }

    private func show(_ model: SavePopupModel) throws -> (SavePopupWindowController, NSWindow) {
        _ = NSApplication.shared
        let controller = SavePopupWindowController()
        controller.show(model)
        spin()
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<SavePopupView> })
        return (controller, window)
    }

    private func contentHeight(_ window: NSWindow) -> CGFloat { window.contentRect(forFrameRect: window.frame).height }

    private static let textDraft = CaptureDraft(
        type: .text, title: "T", text: "hello", source: DropSource(appName: "Notes", windowTitle: "Ideas"))

    @Test func aPlainDraftUsesTheCompactSize() throws {
        let (controller, window) = try show(model(Self.textDraft))
        defer { controller.close() }
        let titleBar = try #require(window.contentView).safeAreaInsets.top
        #expect(window.frame.width == SavePopupView.contentSize.width)
        #expect(contentHeight(window) == SavePopupView.contentSize.height + titleBar)
        #expect(contentHeight(window) < 560)
    }

    @Test(arguments: [DropType.text, .image, .mixed])
    func extraRowsMakeThePopupTallerInsteadOfCuttingItOff(type: DropType) throws {
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in rect.fill(); return true }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let draft = CaptureDraft(
            type: type, title: "T", text: type == .image ? nil : "hello", imagePNG: type == .text ? nil : png,
            source: DropSource(appName: "Notes"),
            warnings: [CaptureWarning("clipboard_restore_failed"), CaptureWarning("chrome_url_failed")])
        let popup = model(draft, recent: (1...12).map { "recent-tag-\($0)" })
        let (controller, window) = try show(popup)
        defer { controller.close() }
        let top = window.frame.maxY
        let before = contentHeight(window)
        for tag in (1...12).map({ "tag-\($0)" }) {
            popup.tagInput = tag
            popup.registerTagInput()
        }
        spin()
        #expect(contentHeight(window) > before)
        #expect(window.frame.maxY == top)
        // The window is as tall as the content asks for, so nothing is cut off.
        #expect(contentHeight(window) == (window.contentView?.fittingSize.height ?? 0))
    }
}
