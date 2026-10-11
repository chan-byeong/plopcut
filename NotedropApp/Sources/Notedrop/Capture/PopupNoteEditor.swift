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
    var onFocusChange: (Bool) -> Void = { _ in }

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
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.delegate = context.coordinator
        textView.onEdit = { [weak coordinator = context.coordinator] in coordinator?.publish($0) }
        textView.onFocusChange = { [weak coordinator = context.coordinator] in coordinator?.parent.onFocusChange($0) }

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
        if textView.placeholder != placeholder { textView.placeholder = placeholder }
        // Writing during a composition would drop the syllable being typed.
        if !textView.hasMarkedText(), textView.string != text { textView.string = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PopupNoteEditor
        init(_ parent: PopupNoteEditor) { self.parent = parent }

        func publish(_ string: String) {
            if parent.text != string { parent.text = string }
        }
    }
}

/// Keeps the text view at least as tall as the visible area, so a click below the last line still focuses the note.
final class NoteScrollView: NSScrollView {
    override func tile() {
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
    var onEdit: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
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

    private func edited() {
        // The placeholder can extend past the changed glyphs, so redraw the whole view.
        needsDisplay = true
        onEdit?(string)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnFirstWindow, let window else { return }
        focusOnFirstWindow = false
        // After the hosting view finishes inserting its views; the run loop also runs this inside a nested loop.
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.window === window else { return }
                window.makeFirstResponder(self)
            }
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
