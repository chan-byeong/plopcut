import SwiftUI

/// A model that edits a list of tags through a draft input (the inspector's `DropEditor`, the `SavePopupModel`).
@MainActor
protocol TagEditing: AnyObject, Observable {
    var tagInput: String { get set }
    var tagMessage: String? { get set }
    var currentTags: [String] { get }
    func registerTagInput()
    func removeTag(_ tag: String)
}

/// When an edit of the tag draft registers it without Return (design-system.md, "태그 편집기").
enum TagInputRule {
    /// A typed comma registers. A comma left behind by an input-method commit must not register the next syllable,
    /// which arrives one character at a time; pasted text with commas still registers.
    static func registersOnChange(old: String, new: String) -> Bool {
        let pasted = new.count - old.count > 1
        return new.hasSuffix(",") || (pasted && new.contains(","))
    }
}

/// The tag draft field, its Add button, the duplicate notice and the removable chips.
/// Return, comma, paste and Add register; the key that only commits a Korean composition does not (checklist I-01).
/// Registering or removing a chip keeps focus in the field.
struct TagEntryField<Model: TagEditing>: View {
    @Bindable var model: Model
    var focused: FocusState<Bool>.Binding
    /// Shown when there are no tags, or nothing when `nil`.
    var emptyText: String?
    /// Without tags or `emptyText`, keep one chip row's height empty so the first tag does not push the content down.
    var reservesChipRow = false
    /// Escape in the field; `nil` leaves Escape to the window (the Save Popup cancels).
    var onExit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                TextField(L10n.t("tagPlaceholder"), text: $model.tagInput)
                    .focused(focused)
                    .onSubmit { register() }
                    .onExitCommand(perform: onExit)
                    .onChange(of: focused.wrappedValue) { _, _ in CompositionMonitor.shared.reset() }
                    .onChange(of: model.tagInput) { old, value in
                        if !value.isEmpty { model.tagMessage = nil }
                        if TagInputRule.registersOnChange(old: old, new: value) { register() }
                    }
                    .accessibilityLabel(L10n.t("tags"))
                Button(L10n.t("addTag")) { register() }
                    .disabled(model.tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message = model.tagMessage { FeedbackText(message, kind: .warning) }
            if model.currentTags.isEmpty {
                if let emptyText {
                    Text(emptyText).foregroundStyle(.secondary)
                } else if reservesChipRow {
                    // A hidden chip measures the row, so the space follows the chip's font and control size.
                    RemovableChip(text: "#", removeLabel: "") {}.hidden().accessibilityHidden(true)
                }
            } else {
                FlowLayout {
                    ForEach(model.currentTags, id: \.self) { tag in
                        RemovableChip(text: Formatting.tag(tag), removeLabel: L10n.t("removeTag")) {
                            model.removeTag(tag)
                            focused.wrappedValue = true
                        }
                    }
                }
            }
        }
        // A text field takes spare height in a tall pane (the inspector); the field keeps its natural height anywhere.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func register() {
        if CompositionMonitor.shared.shouldIgnoreRegistration { return }
        model.registerTagInput()
        focused.wrappedValue = true
    }
}
