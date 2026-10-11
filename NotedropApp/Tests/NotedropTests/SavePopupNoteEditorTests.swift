import AppKit
import NotedropCore
import SwiftUI
import Testing
@testable import Notedrop

/// The popup's note field driven the way an input method drives it (STA-66).
///
/// A Korean input method keeps the syllable being typed as marked text. At a syllable boundary it commits the
/// previous syllable and opens the next one in the same key event, so the view update that follows runs while
/// the new syllable is still marked.
@MainActor
@Suite struct SavePopupNoteEditorTests {
    private static let noReplacement = NSRange(location: NSNotFound, length: 0)

    private struct Popup {
        let window: NSWindow
        let model: SavePopupModel
        let note: NSTextView
    }

    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    private func open() throws -> Popup {
        _ = NSApplication.shared
        let draft = CaptureDraft(type: .text, title: "T", text: "hello", source: DropSource(appName: "Notes"))
        let model = SavePopupModel(
            draft: draft, recentTags: [], save: { _ in throw CancellationError() }, onSaved: { _ in }, onCancel: {})
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 480), styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SavePopupView(model: model))
        window.makeKeyAndOrderFront(nil)
        spin()
        let note = try #require(Self.textViews(in: window.contentView!).first { !$0.isFieldEditor })
        return Popup(window: window, model: model, note: note)
    }

    private static func textViews(in view: NSView) -> [NSTextView] {
        ((view as? NSTextView).map { [$0] } ?? []) + view.subviews.flatMap { textViews(in: $0) }
    }

    private func mark(_ text: String, in view: NSTextView) {
        view.setMarkedText(
            text, selectedRange: NSRange(location: (text as NSString).length, length: 0), replacementRange: Self.noReplacement)
    }

    @Test func theNoteHasFocusWhenThePopupOpens() throws {
        let popup = try open()
        defer { popup.window.close() }
        #expect(popup.window.firstResponder === popup.note)
    }

    @Test func aSyllableOpenedRightAfterACommitStaysComposing() throws {
        let popup = try open()
        defer { popup.window.close() }
        mark("한", in: popup.note)
        spin()
        // Commit 한 and open ㄱ in one key event, then let the view update.
        popup.note.insertText("한", replacementRange: Self.noReplacement)
        mark("ㄱ", in: popup.note)
        spin()
        #expect(popup.note.string == "한ㄱ")
        #expect(popup.note.hasMarkedText())
        #expect(popup.note.selectedRange() == NSRange(location: 2, length: 0))
        mark("글", in: popup.note)
        popup.note.insertText("글", replacementRange: Self.noReplacement)
        spin()
        #expect(popup.note.string == "한글")
        #expect(popup.model.note == "한글")
    }

    @Test func theNoteHoldsWhatTheFieldShowsWhileComposing() throws {
        let popup = try open()
        defer { popup.window.close() }
        mark("하", in: popup.note)
        spin()
        // Like a web textarea: Cmd+Enter during a composition saves the visible text (checklist I-04).
        #expect(popup.model.note == "하")
    }

    @Test func newlinesKeepTheCaretAfterTheText() throws {
        let popup = try open()
        defer { popup.window.close() }
        popup.note.insertText("a", replacementRange: Self.noReplacement)
        popup.note.insertNewline(nil)
        mark("ㅂ", in: popup.note)
        spin()
        #expect(popup.model.note == "a\nㅂ")
        #expect(popup.note.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test func thePlaceholderStartsWhereTheCaretIs() throws {
        let popup = try open()
        defer { popup.window.close() }
        let note = try #require(popup.note as? NoteTextView)
        #expect(note.showsPlaceholder)
        let caret = try #require(note.caretRect(at: 0))
        let placeholder = note.placeholderRect
        #expect(abs(placeholder.minX - caret.minX) < 0.5)
        #expect(abs(placeholder.minY - caret.minY) < 0.5)
    }

    @Test func thePlaceholderHidesWhileComposingAndAfterTyping() throws {
        let popup = try open()
        defer { popup.window.close() }
        let note = try #require(popup.note as? NoteTextView)
        mark("ㅎ", in: note)
        #expect(!note.showsPlaceholder)
        note.unmarkText()
        note.selectAll(nil)
        note.insertText("", replacementRange: Self.noReplacement)
        spin()
        #expect(note.showsPlaceholder)
        #expect(popup.model.note.isEmpty)
    }

    @Test func aNoteSetByTheModelReachesTheField() throws {
        let popup = try open()
        defer { popup.window.close() }
        popup.model.note = "from model"
        spin()
        #expect(popup.note.string == "from model")
    }
}
