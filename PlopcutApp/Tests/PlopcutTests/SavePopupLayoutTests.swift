import AppKit
import PlopcutCore
import SwiftUI
import Testing
@testable import Plopcut

extension SavePopupWindowTests {
    /// The compact Save Popup (STA-67): small for a plain draft, taller instead of cut off when rows are added,
    /// never taller than the screen.
    @MainActor
    @Suite struct Layout {
        /// Suspends so the main run loop can lay out and resize the window.
        private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

        private func model(_ draft: CaptureDraft, recent: [String] = ["alpha", "beta", "gamma"]) -> SavePopupModel {
            SavePopupModel(draft: draft, recentTags: recent, save: { _ in throw CancellationError() }, onSaved: { _ in }, onCancel: {})
        }

        private func show(_ model: SavePopupModel, in controller: SavePopupWindowController) async throws -> NSWindow {
            _ = NSApplication.shared
            controller.show(model)
            await settle()
            return try #require(controller.window)
        }

        private func contentHeight(_ window: NSWindow) -> CGFloat { window.contentRect(forFrameRect: window.frame).height }

        private func addTags(_ count: Int, to model: SavePopupModel) {
            for tag in (1...count).map({ "tag-number-\($0)" }) {
                model.tagInput = tag
                model.registerTagInput()
            }
        }

        private static let textDraft = CaptureDraft(
            type: .text, title: "T", text: "hello", source: DropSource(appName: "Notes", windowTitle: "Ideas"))

        private static func fullDraft(_ type: DropType) throws -> CaptureDraft {
            let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in rect.fill(); return true }
            let tiff = try #require(image.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            return CaptureDraft(
                type: type, title: "T", text: type == .image ? nil : "hello", imagePNG: type == .text ? nil : png,
                source: DropSource(appName: "Notes"),
                warnings: [CaptureWarning("clipboard_restore_failed"), CaptureWarning("chrome_url_failed")])
        }

        @Test func aPlainDraftUsesTheCompactSize() async throws {
            let controller = SavePopupWindowController()
            let window = try await show(model(Self.textDraft), in: controller)
            defer { controller.close() }
            let titleBar = try #require(window.contentView).safeAreaInsets.top
            #expect(window.frame.width == SavePopupView.contentSize.width)
            #expect(contentHeight(window) == SavePopupView.contentSize.height + titleBar)
            #expect(contentHeight(window) < 560)
        }

        // I-12: the title field and "Pin after saving" (PLO-105) fit the compact size: 487 below the title bar
        // (spec 2.1) holds a plain text or image draft with three recent tags, and nothing in it scrolls.
        @Test(arguments: [DropType.text, .image, .mixed])
        func theTitleAndPinRowsFitTheCompactSize(type: DropType) async throws {
            #expect(SavePopupView.contentSize == CGSize(width: 430, height: 487))
            let screen = NSRect(x: 0, y: 0, width: 1600, height: 1200)
            let controller = SavePopupWindowController(visibleFrame: { _ in screen })
            var draft = try Self.fullDraft(type)
            draft.warnings = []
            let window = try await show(model(draft), in: controller)
            defer { controller.close() }
            let host = try #require(window.contentView)
            let compact = SavePopupView.contentSize.height + host.safeAreaInsets.top
            if type == .mixed {
                // The type picker makes the header a little taller, so a mixed draft grows past the compact size.
                #expect(contentHeight(window) > compact)
            } else {
                #expect(contentHeight(window) == compact)
            }
            #expect(host.fittingSize.height <= contentHeight(window))
            #expect(!Self.scrollViews(in: host).contains { $0.documentView.map { $0.frame.height > $0.visibleRect.height + 1 } ?? false })
        }

        @Test(arguments: [DropType.text, .image, .mixed])
        func extraRowsMakeThePopupTallerInsteadOfCuttingItOff(type: DropType) async throws {
            // A fixed, roomy screen: on a small real screen (CI runners) the window is moved to stay on it.
            let screen = NSRect(x: 0, y: 0, width: 1600, height: 1200)
            let controller = SavePopupWindowController(visibleFrame: { _ in screen })
            let popup = model(try Self.fullDraft(type), recent: (1...12).map { "recent-tag-\($0)" })
            let window = try await show(popup, in: controller)
            defer { controller.close() }
            let top = window.frame.maxY
            let before = contentHeight(window)
            addTags(12, to: popup)
            await settle()
            #expect(contentHeight(window) > before)
            #expect(window.frame.maxY == top)
            // The window is as tall as the content asks for, so nothing is cut off.
            #expect(contentHeight(window) == (window.contentView?.fittingSize.height ?? 0))
        }

        @Test(arguments: [DropType.text, .image, .mixed])
        func onASmallScreenTheFieldsScrollAndTheWindowStaysOnScreen(type: DropType) async throws {
            let screen = NSRect(x: 100, y: 80, width: 900, height: 520)
            let controller = SavePopupWindowController(visibleFrame: { _ in screen })
            let popup = model(try Self.fullDraft(type), recent: (1...12).map { "recent-tag-\($0)" })
            let window = try await show(popup, in: controller)
            defer { controller.close() }
            addTags(30, to: popup)
            await settle()
            #expect(window.frame.height <= screen.height)
            #expect(screen.contains(window.frame))
            // The content fits the window, so the buttons at its bottom are in view; the fields above them scroll.
            let host = try #require(window.contentView)
            #expect(host.fittingSize.height <= contentHeight(window))
            #expect(Self.scrollViews(in: host).contains { $0.documentView.map { $0.frame.height > $0.visibleRect.height + 1 } ?? false })
        }

        @Test func reopeningAfterATallDraftCentersTheCompactSize() async throws {
            let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
            let controller = SavePopupWindowController(visibleFrame: { _ in screen })
            let tall = model(try Self.fullDraft(.mixed), recent: (1...12).map { "recent-tag-\($0)" })
            let window = try await show(tall, in: controller)
            addTags(20, to: tall)
            await settle()
            let tallHeight = window.frame.height
            controller.close()

            _ = try await show(model(Self.textDraft), in: controller)
            defer { controller.close() }
            let titleBar = try #require(window.contentView).safeAreaInsets.top
            #expect(window.frame.height < tallHeight)
            #expect(contentHeight(window) == SavePopupView.contentSize.height + titleBar)
            #expect(abs(window.frame.midX - screen.midX) < 1)
            #expect(abs(window.frame.midY - screen.midY) < 1)
        }

        // PLO-96: the popup takes the keyboard without activating plopcut, so the main window never comes forward and
        // the app the user was in stays active after a save or a cancel.
        @Test func thePopupDoesNotActivateTheApp() async throws {
            let controller = SavePopupWindowController()
            let window = try await show(model(Self.textDraft), in: controller)
            defer { controller.close() }
            #expect(window.styleMask.contains(.nonactivatingPanel))
            #expect(window.canBecomeKey)
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
        }
    }
}

extension SavePopupWindowTests {
    /// PLO-96: plopcut stays inactive while its popup is open, so AppKit skips key equivalents (Cmd+Enter, Escape, the
    /// Edit menu's Cmd+V). The panel routes those itself; plain typing goes through as usual.
    @MainActor
    @Suite struct KeyRouting {
        private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }

        @Test func commandKeysAndEscapeAreRoutedAsKeyEquivalents() throws {
            #expect(SavePopupPanel.routesAsKeyEquivalent(try key(36, "\r", .command)))
            #expect(SavePopupPanel.routesAsKeyEquivalent(try key(9, "v", .command)))
            #expect(SavePopupPanel.routesAsKeyEquivalent(try key(53, "\u{1b}")))
        }

        @Test func editShortcutsMapToTheTextActions() throws {
            #expect(SavePopupPanel.editAction(for: try key(9, "v", .command)) == #selector(NSText.paste(_:)))
            #expect(SavePopupPanel.editAction(for: try key(8, "c", .command)) == #selector(NSText.copy(_:)))
            #expect(SavePopupPanel.editAction(for: try key(7, "x", .command)) == #selector(NSText.cut(_:)))
            #expect(SavePopupPanel.editAction(for: try key(0, "a", .command)) == #selector(NSText.selectAll(_:)))
            #expect(SavePopupPanel.editAction(for: try key(6, "z", .command)) == Selector(("undo:")))
            #expect(SavePopupPanel.editAction(for: try key(6, "z", [.command, .shift])) == Selector(("redo:")))
            // A Korean layout reports its own letter; the key's position still says which shortcut it is.
            #expect(SavePopupPanel.editAction(for: try key(9, "ㅍ", .command)) == #selector(NSText.paste(_:)))
            #expect(SavePopupPanel.editAction(for: try key(9, "v")) == nil)
            #expect(SavePopupPanel.editAction(for: try key(36, "\r", .command)) == nil)
        }

        @Test func typingIsLeftToTheTextFields() throws {
            #expect(!SavePopupPanel.routesAsKeyEquivalent(try key(0, "a")))
            #expect(!SavePopupPanel.routesAsKeyEquivalent(try key(36, "\r")))
            #expect(!SavePopupPanel.routesAsKeyEquivalent(try key(0, "A", .shift)))
        }
    }
}
