import AppKit
import PlopcutCore
import SwiftUI
import Testing
@testable import Plopcut

/// Popup tests open real windows and move keyboard focus, so they run one at a time, not beside each other.
@MainActor
@Suite(.serialized) struct SavePopupWindowTests {}

extension SavePopupWindowTests {
    /// The popup's note field driven the way an input method and the keyboard drive it (STA-66).
    ///
    /// A Korean input method keeps the syllable being typed as marked text. At a syllable boundary it commits the
    /// previous syllable and opens the next one in the same key event, so the view update that follows runs while
    /// the new syllable is still marked.
    @MainActor
    @Suite struct NoteEditor {
        private static let noReplacement = NSRange(location: NSNotFound, length: 0)

        @MainActor
        private final class Popup {
            let controller = SavePopupWindowController()
            private(set) var model: SavePopupModel!
            private(set) var cancelled = 0
            private(set) var window: NSWindow!
            private(set) var note: NoteTextView!

            init() {
                let draft = CaptureDraft(type: .text, title: "T", text: "hello", source: DropSource(appName: "Notes"))
                model = SavePopupModel(
                    draft: draft, recentTags: [], save: { _ in throw CancellationError() }, onSaved: { _ in },
                    onCancel: { [weak self] in self?.cancelled += 1 })
            }

            func open() async throws {
                _ = NSApplication.shared
                controller.show(model)
                window = try #require(controller.window)
                note = try #require(Self.textViews(in: window.contentView!).compactMap { $0 as? NoteTextView }.first)
                // The note takes focus once the hosting view has inserted it.
                try await waitUntil { self.window.firstResponder === self.note }
            }

            private static func textViews(in view: NSView) -> [NSTextView] {
                ((view as? NSTextView).map { [$0] } ?? []) + view.subviews.flatMap { textViews(in: $0) }
            }

            func mark(_ text: String) {
                note.setMarkedText(
                    text, selectedRange: NSRange(location: (text as NSString).length, length: 0),
                    replacementRange: noReplacement)
            }

            func commit(_ text: String) { note.insertText(text, replacementRange: noReplacement) }

            private func event(_ type: NSEvent.EventType, _ characters: String, _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
            }

            func press(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
                for type in [NSEvent.EventType.keyDown, .keyUp] { NSApp.sendEvent(event(type, characters, keyCode, modifiers)) }
            }

            /// The test process has no running app to route key equivalents, so ask the window directly.
            func keyEquivalent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
                window.performKeyEquivalent(with: event(.keyDown, characters, keyCode, modifiers))
            }

            var focusIsInTagField: Bool { (window.firstResponder as? NSTextView)?.isFieldEditor == true }
        }

        /// Suspends so the main run loop can run SwiftUI's pending updates.
        private static func settle() async {
            try? await Task.sleep(for: .milliseconds(60))
        }

        /// Waits for a condition instead of a fixed delay, up to about a second.
        private static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
            for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
            #expect(condition())
        }

        private func withPopup(_ body: (Popup) async throws -> Void) async throws {
            let popup = Popup()
            try await popup.open()
            defer { popup.controller.close() }
            try await body(popup)
        }

        @Test func theNoteHasFocusWhenThePopupOpens() async throws {
            try await withPopup { popup in #expect(popup.window.firstResponder === popup.note) }
        }

        @Test func aSyllableOpenedRightAfterACommitStaysComposing() async throws {
            try await withPopup { popup in
                popup.mark("한")
                await Self.settle()
                // Commit 한 and open ㄱ in one key event, then let the view update.
                popup.commit("한")
                popup.mark("ㄱ")
                await Self.settle()
                #expect(popup.note.string == "한ㄱ")
                #expect(popup.note.hasMarkedText())
                #expect(popup.note.selectedRange() == NSRange(location: 2, length: 0))
                popup.mark("글")
                popup.commit("글")
                try await Self.waitUntil { popup.model.note == "한글" }
                #expect(popup.note.string == "한글")
            }
        }

        @Test func theNoteHoldsWhatTheFieldShowsWhileComposing() async throws {
            try await withPopup { popup in
                popup.mark("하")
                try await Self.waitUntil { popup.model.note == "하" }
            }
        }

        @Test func savingClosesAnOpenCompositionAndKeepsItsCharacters() async throws {
            try await withPopup { popup in
                popup.commit("a")
                popup.mark("하")
                // Cmd+Enter is the Save button's key equivalent.
                #expect(popup.keyEquivalent("\r", keyCode: 36, modifiers: .command))
                try await Self.waitUntil { !popup.note.hasMarkedText() }
                #expect(popup.note.string == "a하")
                #expect(popup.model.note == "a하")
            }
        }

        @Test func returnTypesANewlineAndTheCaretFollows() async throws {
            try await withPopup { popup in
                popup.commit("a")
                popup.press("\r", keyCode: 36)
                popup.mark("ㅂ")
                await Self.settle()
                #expect(popup.model.note == "a\nㅂ")
                #expect(popup.note.selectedRange() == NSRange(location: 3, length: 0))
            }
        }

        @Test func tabMovesToTheTagFieldAndShiftTabComesBack() async throws {
            try await withPopup { popup in
                popup.commit("a")
                popup.press("\t", keyCode: 48)
                try await Self.waitUntil { popup.focusIsInTagField }
                #expect(popup.model.note == "a")
                popup.press("\u{19}", keyCode: 48, modifiers: .shift)
                try await Self.waitUntil { popup.window.firstResponder === popup.note }
                #expect(popup.model.note == "a")
            }
        }

        @Test func escapeCancelsFromTheNote() async throws {
            try await withPopup { popup in
                popup.press("\u{1b}", keyCode: 53)
                try await Self.waitUntil { popup.cancelled == 1 }
            }
        }

        // PLO-96: plopcut stays inactive behind the popup, so no menu offers the Edit shortcuts. The test process has no
        // main menu either, so only the panel's own routing can select the text here.
        @Test func editShortcutsReachTheNoteWithoutTheEditMenu() async throws {
            try await withPopup { popup in
                popup.commit("abc")
                popup.press("a", keyCode: 0, modifiers: .command)
                #expect(popup.note.selectedRange() == NSRange(location: 0, length: 3))
            }
        }

        @Test func thePlaceholderStartsWhereTheCaretIs() async throws {
            try await withPopup { popup in
                #expect(popup.note.showsPlaceholder)
                let caret = try #require(popup.note.caretRect(at: 0))
                let placeholder = popup.note.placeholderRect
                #expect(abs(placeholder.minX - caret.minX) < 0.5)
                #expect(abs(placeholder.minY - caret.minY) < 0.5)
            }
        }

        @Test func thePlaceholderHidesWhileComposingAndAfterTyping() async throws {
            try await withPopup { popup in
                popup.mark("ㅎ")
                #expect(!popup.note.showsPlaceholder)
                popup.note.unmarkText()
                popup.note.selectAll(nil)
                popup.commit("")
                try await Self.waitUntil { popup.model.note.isEmpty }
                #expect(popup.note.showsPlaceholder)
            }
        }

        @Test func aNoteSetByTheModelReachesTheField() async throws {
            try await withPopup { popup in
                popup.model.note = "from model"
                try await Self.waitUntil { popup.note.string == "from model" }
            }
        }
    }
}
