import AppKit
import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

/// The Save Popup's title field and "Pin after saving" (spec 3.5, PLO-105).
@MainActor
@Suite struct SavePopupTitleTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

    private final class Captured: @unchecked Sendable { var request: SaveRequest? }

    private func model(_ draft: CaptureDraft, captured: Captured = Captured()) -> SavePopupModel {
        SavePopupModel(
            draft: draft, recentTags: [],
            save: { request in
                captured.request = request
                return Drop(id: "d", type: .text, title: request.title ?? "", createdAt: "t", updatedAt: "t")
            },
            onSaved: { _ in }, onCancel: {}, log: NullEventLog())
    }

    private static let notes = CaptureDraft(
        type: .text, title: "Ideas", text: "hello", source: DropSource(appName: "Notes", windowTitle: "Ideas"))

    // I-07
    @Test func theFieldStartsWithTheAutomaticTitle() {
        let m = model(Self.notes)
        #expect(m.title == "Ideas")
        #expect(m.autoTitle == "Ideas")
    }

    // I-07: an untouched field saves the same title as before PLO-105.
    @Test func savingAnUntouchedFieldSendsTheAutomaticTitle() async {
        let captured = Captured()
        await model(Self.notes, captured: captured).submit()
        #expect(captured.request?.title == "Ideas")
    }

    // I-08
    @Test func autoIsOnlyAvailableAfterAnEditAndRestoresTheAutomaticTitle() async {
        let captured = Captured()
        let m = model(Self.notes, captured: captured)
        #expect(!m.canRestoreAutoTitle)
        m.title = "Meeting ideas"
        #expect(m.canRestoreAutoTitle)
        m.restoreAutoTitle()
        #expect(m.title == "Ideas")
        #expect(!m.canRestoreAutoTitle)
        m.title = ""
        #expect(m.canRestoreAutoTitle)
        m.title = "Ideas"
        #expect(!m.canRestoreAutoTitle)
    }

    @Test func anEditedTitleIsSavedTrimmed() async {
        let captured = Captured()
        let m = model(Self.notes, captured: captured)
        m.title = "  Meeting ideas \n"
        await m.submit()
        #expect(captured.request?.title == "Meeting ideas")
    }

    // I-09: storage then infers the title (spec 1.4).
    @Test(arguments: ["", "   ", " \n\t"])
    func anEmptyFieldSendsNoExplicitTitle(input: String) async {
        let captured = Captured()
        let m = model(Self.notes, captured: captured)
        m.title = input
        await m.submit()
        #expect(captured.request != nil)
        #expect(captured.request?.title == nil)
    }

    // I-08
    @Test func aMixedDraftFollowsTheChosenTypeUntilTheTitleIsEdited() {
        let draft = CaptureDraft(
            type: .mixed, title: "caption line", text: "caption line", imagePNG: Self.png,
            imageTitle: "Image Drop")
        let m = model(draft)
        #expect(m.title == "caption line")
        m.selectedType = .image
        #expect(m.title == "Image Drop")
        m.selectedType = .text
        #expect(m.title == "caption line")
        m.title = "Mine"
        m.selectedType = .image
        #expect(m.title == "Mine")
        #expect(m.autoTitle == "Image Drop")
        m.restoreAutoTitle()
        #expect(m.title == "Image Drop")
    }

    @Test func choosingTheImageOfAMixedDraftSavesTheImageTitle() async {
        let captured = Captured()
        let draft = CaptureDraft(type: .mixed, title: "caption", text: "caption", imagePNG: Self.png, imageTitle: "Shot")
        let m = model(draft, captured: captured)
        m.selectedType = .image
        await m.submit()
        #expect(captured.request?.title == "Shot")
    }

    // I-11
    @Test func pinAfterSavingStartsOffAndRidesOnTheRequest() async {
        let off = Captured()
        let first = model(Self.notes, captured: off)
        #expect(!first.pinAfterSave)
        await first.submit()
        #expect(off.request?.pinned == false)

        let on = Captured()
        let second = model(Self.notes, captured: on)
        second.pinAfterSave = true
        await second.submit()
        #expect(on.request?.pinned == true)
        // A new popup starts unchecked again.
        #expect(!model(Self.notes).pinAfterSave)
    }

    // I-09: the hint says where the automatic title came from, in spec 1.4's order.
    @Test func theHintNamesWhereTheAutomaticTitleCameFrom() {
        func hint(_ type: DropType = .text, text: String? = "first line\nsecond", window: String? = nil, app: String? = nil) -> String {
            let draft = CaptureDraft(
                type: type, title: "t", text: type == .image ? nil : text, imagePNG: type == .text ? nil : Self.png,
                source: DropSource(appName: app, windowTitle: window))
            return model(draft).titleHint
        }
        #expect(hint(window: "Ideas", app: "Notes") == L10n.t("titleHintWindow"))
        #expect(hint(window: "  ", app: "Notes") == L10n.t("titleHintApp"))
        #expect(hint(app: "Notes") == L10n.t("titleHintApp"))
        #expect(hint() == L10n.t("titleHintFirstLine"))
        #expect(hint(text: "\n  \n") == L10n.t("titleHintDefault"))
        #expect(hint(.image) == L10n.t("titleHintDefault"))
        #expect(hint(.image, app: "Preview") == L10n.t("titleHintApp"))
    }

    @Test func theHintOfAMixedDraftFollowsTheChosenType() {
        let draft = CaptureDraft(
            type: .mixed, title: "caption", text: "caption", imagePNG: Self.png, imageTitle: "Image Drop")
        let m = model(draft)
        #expect(m.titleHint == L10n.t("titleHintFirstLine"))
        m.selectedType = .image
        #expect(m.titleHint == L10n.t("titleHintDefault"))
    }
}

extension SavePopupWindowTests {
    /// I-10: with the title field focused, Cmd+Enter still saves and Escape still cancels (spec 3.5, PLO-105).
    @MainActor
    @Suite struct TitleKeys {
        @MainActor
        private final class Popup {
            let controller = SavePopupWindowController()
            private(set) var model: SavePopupModel!
            private(set) var saves = 0
            private(set) var cancels = 0
            private(set) var window: NSWindow!

            init() {
                let draft = CaptureDraft(
                    type: .text, title: "Ideas", text: "hello", source: DropSource(appName: "Notes", windowTitle: "Ideas"))
                model = SavePopupModel(
                    draft: draft, recentTags: [],
                    save: { request in Drop(id: "d", type: .text, title: request.title ?? "", createdAt: "t", updatedAt: "t") },
                    onSaved: { [weak self] _ in self?.saves += 1 }, onCancel: { [weak self] in self?.cancels += 1 },
                    log: NullEventLog())
            }

            func openWithTheTitleFocused() async throws {
                _ = NSApplication.shared
                controller.show(model)
                window = try #require(controller.window)
                try await Self.waitUntil { Self.titleField(in: self.window.contentView!) != nil }
                let field = try #require(Self.titleField(in: window.contentView!))
                #expect(window.makeFirstResponder(field))
                try await Self.waitUntil { (self.window.firstResponder as? NSTextView)?.delegate === field }
            }

            private static func titleField(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable, field.stringValue == "Ideas" { return field }
                return view.subviews.lazy.compactMap { titleField(in: $0) }.first
            }

            static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
                for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
                #expect(condition())
            }

            func event(_ characters: String, _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
            }
        }

        @Test func commandReturnSavesFromTheTitleField() async throws {
            let popup = Popup()
            try await popup.openWithTheTitleFocused()
            defer { popup.controller.close() }
            popup.window.sendEvent(popup.event("\r", 36, .command))
            try await Popup.waitUntil { popup.saves == 1 }
        }

        @Test func escapeCancelsFromTheTitleField() async throws {
            let popup = Popup()
            try await popup.openWithTheTitleFocused()
            defer { popup.controller.close() }
            popup.window.sendEvent(popup.event("\u{1b}", 53))
            try await Popup.waitUntil { popup.cancels == 1 }
            #expect(popup.saves == 0)
        }
    }
}
