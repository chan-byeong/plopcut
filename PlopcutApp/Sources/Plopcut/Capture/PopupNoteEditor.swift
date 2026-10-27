import AppKit
import SwiftUI

/// The Save Popup note field (STA-66).
///
/// SwiftUI's `TextEditor` writes its binding back into the text view after every commit. A Korean input method commits
/// one syllable and opens the next in the same key event, so that write lands while the new syllable is still marked:
/// it drops the syllable and moves the caret back one character. This editor never writes into the text view during a
/// composition. The binding holds the visible text, composition included, as a web textarea does, so a save during a
/// composition keeps the last syllable (checklist I-04). The placeholder is drawn by the text view at the caret.
struct PopupNoteEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String
    /// Lets the popup close an open composition before it saves.
    var control: PopupNoteEditorControl? = nil
    /// The Save Popup opens on the note; a floating panel must not take the keyboard when it appears.
    var focusOnAppear = true
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.string = text
        textView.placeholder = placeholder
        textView.focusOnFirstWindow = focusOnAppear
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.delegate = context.coordinator
        textView.onEdit = { [weak coordinator = context.coordinator] in coordinator?.publish($0) }
        textView.onFocusChange = { [weak coordinator = context.coordinator] in coordinator?.focusChanged($0) }
        control?.textView = textView

        // Same scroll setup as `TextEditor`, so the scroller looks as before.
        let scrollView = NoteScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NoteTextView else { return }
        control?.textView = textView
        if textView.placeholder != placeholder { textView.placeholder = placeholder }
        if textView.accessibilityLabel() != accessibilityLabel { textView.setAccessibilityLabel(accessibilityLabel) }
        // The text view is the source of truth while the popup is open: every edit, marked text included, is
        // published to the binding, and the end of a composition (`unmarkText`, or the IME's `insertText`) publishes
        // again, so the binding matches the view once the composition ends. Only a value set from outside during a
        // composition is skipped here, on purpose: writing it would drop the syllable being typed. Nothing else in
        // the popup writes the note while it is being edited.
        if !textView.hasMarkedText(), textView.string != text { textView.string = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PopupNoteEditor
        init(_ parent: PopupNoteEditor) { self.parent = parent }

        func publish(_ string: String) {
            if parent.text != string { parent.text = string }
        }

        /// Focus changes arrive inside `becomeFirstResponder`, which can run during a SwiftUI update; the popup's
        /// state changes on the next turn instead.
        func focusChanged(_ focused: Bool) {
            Task { @MainActor [weak self] in self?.parent.onFocusChange(focused) }
        }
    }
}

/// A handle the popup uses to reach its note editor.
@MainActor
final class PopupNoteEditorControl {
    fileprivate(set) weak var textView: NoteTextView?

    /// Ends an open composition, keeping the visible characters, so `Cmd+Enter` saves what the field shows and a
    /// later commit from the input method has nothing left to replace.
    func commitComposition() { textView?.commitComposition() }
}

/// Keeps the text view at least as tall as the visible area, so a click below the last line still focuses the note.
final class NoteScrollView: NSScrollView {
    /// The thin scroller is set on every tile. AppKit tiles after it gets a new scroller, as when the system's scroll
    /// bar setting changes, and a new scroller starts regular (STA-68).
    override func tile() {
        SlimScroller.setControlSize(on: self)
        super.tile()
        guard let textView = documentView as? NSTextView else { return }
        let height = contentSize.height
        if textView.minSize.height != height { textView.minSize = NSSize(width: 0, height: height) }
        if textView.frame.height < height { textView.setFrameSize(NSSize(width: contentSize.width, height: height)) }
    }
}

/// A plain-text view that reports every visible change, marked text included, and draws its own placeholder.
final class NoteTextView: NSTextView {
    var placeholder = "" {
        didSet {
            setAccessibilityPlaceholderValue(placeholder)
            needsDisplay = true
        }
    }
    var onEdit: (@MainActor (String) -> Void)?
    var onFocusChange: (@MainActor (Bool) -> Void)?
    /// Takes keyboard focus the first time the view is in a window: the popup opens on the note (spec 3.5).
    var focusOnFirstWindow = true

    /// `string` includes marked text, so an open composition hides the placeholder.
    var showsPlaceholder: Bool { string.isEmpty }

    /// Where the first line of text and the caret start, in this view's coordinates.
    var placeholderRect: NSRect {
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        return NSRect(origin: origin, size: placeholderText.size())
    }

    private var placeholderText: NSAttributedString {
        NSAttributedString(string: placeholder, attributes: [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.placeholderTextColor,
        ])
    }

    /// The caret rectangle for an insertion point, in this view's coordinates.
    func caretRect(at location: Int) -> NSRect? {
        guard let window else { return nil }
        let screen = firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        return convert(window.convertFromScreen(screen), from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if showsPlaceholder { placeholderText.draw(at: placeholderRect.origin) }
    }

    override func didChangeText() {
        super.didChangeText()
        edited()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        edited()
    }

    override func unmarkText() {
        super.unmarkText()
        edited()
    }

    /// Asks the input method to finish; if it leaves the marked text in place, keeps those characters as typed.
    func commitComposition() {
        guard hasMarkedText() else { return }
        inputContext?.discardMarkedText()
        if hasMarkedText() { unmarkText() }
    }

    /// Tab and Shift+Tab move between the popup's fields instead of typing a tab, like the legacy textarea.
    /// Option+Tab still types one (`insertTabIgnoringFieldEditor`).
    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(sender)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The placeholder color is resolved when it is drawn.
        needsDisplay = true
    }

    private func edited() {
        // The placeholder can extend past the changed glyphs, so redraw the whole view.
        needsDisplay = true
        onEdit?(string)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnFirstWindow, let window else { return }
        focusOnFirstWindow = false
        // After the hosting view finishes inserting its views.
        Task { @MainActor [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }
}
