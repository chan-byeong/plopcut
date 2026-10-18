import AppKit
import SwiftUI

/// The content editor (spec 2.6 "본문 편집", E-13): plain text in a monospaced font, line numbers on the left, and the
/// Markdown symbols drawn dimmed. Like `PopupNoteEditor`, it never writes into the text view during an input-method
/// composition, so Korean typing keeps its syllables (I-04). Escape cancels; Cmd+Return is the Done button's shortcut.
struct BodyTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    /// False while Done is writing (E-14): the view keeps showing the text but takes no typing.
    var isEditable = true
    var onCancel: @MainActor () -> Void = {}
    var onDone: @MainActor () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // A TextKit 1 stack, so the ruler and the dimming can use the layout manager.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let textView = BodyTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = BodyTextView.editorFont
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: Spacing.xs, height: Spacing.s)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isEditable = isEditable
        textView.string = text
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.onEdit = { [weak coordinator = context.coordinator] in coordinator?.publish($0) }
        textView.onCancel = { [weak coordinator = context.coordinator] in coordinator?.parent.onCancel() }
        textView.onDone = { [weak coordinator = context.coordinator] in coordinator?.parent.onDone() }
        textView.applyDimming()

        let scrollView = NoteScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        // Since macOS 14 views do not clip by default; the ruler would draw past the editor's frame.
        scrollView.clipsToBounds = true
        let ruler = LineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? BodyTextView else { return }
        if textView.accessibilityLabel() != accessibilityLabel { textView.setAccessibilityLabel(accessibilityLabel) }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        // The text view owns the text while it is open; only a value set from outside outside a composition is written.
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.applyDimming()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: BodyTextEditor
        init(_ parent: BodyTextEditor) { self.parent = parent }

        func publish(_ string: String) {
            if parent.text != string { parent.text = string }
        }
    }
}

/// The editor's text view: reports every visible change (marked text included), dims Markdown symbols, and turns
/// Escape and Cmd+Return into Cancel and Done.
final class BodyTextView: NSTextView {
    static var editorFont: NSFont { .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }

    var onEdit: (@MainActor (String) -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onDone: (@MainActor () -> Void)?
    private var focusOnFirstWindow = true

    /// Dims the symbols with temporary attributes: they only change drawing, never the text or a composition.
    func applyDimming() {
        guard let layoutManager else { return }
        let whole = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        for range in MarkdownSymbols.dimmedRanges(in: string) where NSMaxRange(range) <= whole.length {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, forCharacterRange: range)
        }
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
        // Recomputing during a composition would only change colors, but waiting keeps the marked text untouched.
        if !hasMarkedText() { applyDimming() }
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
        onEdit?(string)
    }

    /// Escape cancels instead of opening the completion list (NSTextView's default).
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender); return }
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.keyCode == CompositionGuard.returnKey || event.keyCode == CompositionGuard.keypadEnterKey {
            onDone?()
            return
        }
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnFirstWindow, let window else { return }
        focusOnFirstWindow = false
        // The editor opens with the keyboard on it (spec 2.6), after the hosting view finishes inserting it.
        Task { @MainActor [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
            self.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDimming()
    }
}

/// Logical line numbers (one per line of text, not per wrapped row) beside the editor, in a dim color.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private static let padding: CGFloat = 8

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = thickness(lines: 99)
        // Scrolling moves the numbers with the text.
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(contentChanged), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func contentChanged() { needsDisplay = true }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
         .foregroundColor: NSColor.tertiaryLabelColor]
    }

    private func thickness(lines: Int) -> CGFloat {
        let digits = String(repeating: "8", count: max(2, String(lines).count))
        return ceil((digits as NSString).size(withAttributes: attributes).width) + Self.padding * 2
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let string = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let firstChar = layoutManager.characterIndexForGlyph(at: glyphs.location)
        // The first visible line may start above the visible rect when it wraps; number it from its start.
        var index = string.lineRange(for: NSRange(location: firstChar, length: 0)).location
        var number = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: index), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            number += 1
        }
        let lastChar = NSMaxRange(layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
        let neededThickness = thickness(lines: max(number, 99))
        if ruleThickness != neededThickness { ruleThickness = neededThickness }
        while index < string.length && index <= lastChar {
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(number, atTextY: fragment.minY, height: fragment.height, in: textView)
            number += 1
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
        }
        // The empty last line after a final line break, or an empty text.
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty || string.length == 0 {
            draw(number, atTextY: extra.minY, height: extra.isEmpty ? BodyTextView.editorFont.boundingRectForFont.height : extra.height, in: textView)
        }
    }

    private func draw(_ number: Int, atTextY y: CGFloat, height: CGFloat, in textView: NSTextView) {
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attributes)
        let origin = convert(NSPoint(x: 0, y: y + textView.textContainerOrigin.y), from: textView)
        let point = NSPoint(x: ruleThickness - Self.padding - size.width, y: origin.y + (height - size.height) / 2)
        label.draw(at: point, withAttributes: attributes)
    }
}
