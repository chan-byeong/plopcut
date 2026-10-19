import AppKit
import PlopcutCore
import SwiftUI

struct DropDetailView: View {
    /// Images stop growing here so a wide window does not blow a screenshot past its natural size.
    private static let imageMaxWidth: CGFloat = 640
    @Bindable var model: LibraryModel
    var listFocused: FocusState<Bool>.Binding
    @FocusState private var titleFocused: Bool

    private var editor: DropEditor { model.editor }

    var body: some View {
        if let drop = model.selectedDrop {
            if editor.bodyEdit?.dropID == drop.id {
                // The editor fills the pane and scrolls itself (spec 2.6 "본문 편집").
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header(for: drop, editing: true)
                    editBar
                    bodyEditor
                }
                .padding(Spacing.xxl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        header(for: drop, editing: false)
                        // Above the body, so a button's tooltip is not drawn under it.
                        actions(for: drop).zIndex(1)
                        Divider()
                        body(of: drop)
                    }
                    .padding(Spacing.xxl).frame(maxWidth: .infinity, alignment: .leading)
                }
                .slimScrollers()
            }
        } else {
            ContentUnavailableView(L10n.t("selectHint"), systemImage: "text.cursor")
        }
    }

    /// The type is an eyebrow over the title, so the two stay together. While editing it ends in "● Editing".
    private func header(for drop: Drop, editing: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(drop.type == .image ? L10n.t("imageDrops") : drop.type == .text ? L10n.t("textDrops") : drop.type.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
                if drop.type == .text {
                    FormatMenuButton(drop: drop) { choice in Task { await model.setFormat(choice, for: drop.id) } }
                }
                if editing {
                    Text("·").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    StatusDot(text: L10n.t("editingBody")).font(.caption.weight(.semibold))
                }
            }
            titleField
        }
    }

    // MARK: Content editing (spec 2.6 "본문 편집")

    /// The hint, Cancel and Done take the action buttons' place while editing.
    private var editBar: some View {
        HStack(spacing: Spacing.s) {
            Text(L10n.t("editBodyHint")).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.t("cancel")) { editor.cancelBodyEdit() }
            Button(L10n.t("done")) { Task { await editor.finishBodyEdit() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(BodyEditorShortcuts.done)
                .disabled(editor.bodyEdit?.state == .saving)
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            BodyTextEditor(
                text: Bindable(editor).bodyText, accessibilityLabel: L10n.t("editBodyField"),
                isEditable: editor.isBodyEditable,
                onCancel: { editor.cancelBodyEdit() },
                onDone: { Task { await editor.finishBodyEdit() } })
                .inputSurface(focused: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: Spacing.m) {
                if case .failed(let code)? = editor.bodyEdit?.state {
                    FeedbackText(code == "empty_text" ? L10n.t("emptyBody") : ErrorText.message(forCode: code), kind: .fieldError)
                } else if editor.bodyChanged {
                    StatusDot(text: L10n.t("bodyChanged"))
                }
                Spacer(minLength: Spacing.s)
                Text(L10n.t("editBodyShortcuts"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Always-visible inline rename: the text never moves, the field chrome appears only while editing (spec 2.6).
    private var titleField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("", text: Bindable(editor).titleText)
                .textFieldStyle(.plain).font(.title.bold())
                // The edit chrome grows outward, so the title text stays where it is when the field is focused.
                .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs).padding(.horizontal, -Spacing.s)
                .inputSurface(focused: titleFocused, chrome: .whileFocused)
                .focused($titleFocused)
                .accessibilityLabel(L10n.t("dropTitle"))
                .onSubmit { finishTitle(commit: true) }
                .onExitCommand { finishTitle(commit: false) }
                .onChange(of: titleFocused) { _, focused in
                    if focused { editor.beginTitleEdit() } else { Task { await editor.commitTitle() } }
                }
            if case .failed(let code) = editor.state, code == "blankTitle" || code == "invalid_title" {
                FeedbackText(ErrorText.message(forCode: code), kind: .fieldError)
            }
        }
    }

    private func finishTitle(commit: Bool) {
        if !commit { editor.cancelTitleEdit() }
        listFocused.wrappedValue = true
    }

    /// Icon-only buttons: Pin · Edit · Open Source · Export Markdown | Move to Trash (spec 2.6).
    private func actions(for drop: Drop) -> some View {
        HStack(spacing: DropActionIcon.gap) {
            let pin = DropAction.pin(pinned: drop.isPinned)
            Toggle(isOn: Binding(get: { drop.isPinned }, set: { _ in Task { await model.togglePin(id: drop.id) } })) {
                DropActionIcon(action: pin)
            }
            .toggleStyle(DropActionToggleStyle())
            .dropActionTooltip(pin.tooltip).accessibilityLabel(pin.title)
            actionButton(.editBody) { model.beginBodyEdit() }
                .disabled(!DropEditor.canEditBody(drop))
            actionButton(.openSource) { openSource(drop) }
                .disabled(URL(string: drop.source.url ?? "") == nil || drop.source.url?.isEmpty != false)
            actionButton(.exportMarkdown) { Task { await model.exportWithPanel(id: drop.id) } }
            Rectangle().fill(.separator).frame(width: 1, height: DropActionIcon.dividerHeight)
                .padding(.horizontal, Spacing.xxs).accessibilityHidden(true)
            actionButton(.moveTrash, role: .destructive) { model.pendingDeleteID = drop.id }
        }
    }

    private func actionButton(_ action: DropAction, role: ButtonRole? = nil, perform: @escaping () -> Void) -> some View {
        Button(role: role, action: perform) { DropActionIcon(action: action) }
            .buttonStyle(DropActionButtonStyle())
            .dropActionTooltip(action.tooltip).accessibilityLabel(action.title)
    }

    @ViewBuilder private func body(of drop: Drop) -> some View {
        if let url = drop.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: Self.imageMaxWidth)
                .accessibilityLabel(L10n.t("image"))
        } else if drop.type == .image {
            Label(L10n.t("imagePreviewUnavailable"), systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
        } else if let text = drop.text {
            RenderedBodyView(text: text, format: FormatDetection.resolve(drop), openLink: model.openLink)
        }
    }

    private func openSource(_ drop: Drop) {
        if let value = drop.source.url, let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }
}

struct InspectorView: View {
    @Bindable var model: LibraryModel
    @FocusState private var noteFocused: Bool
    @FocusState private var tagFocused: Bool

    private var editor: DropEditor { model.editor }
    /// Optical: NSTextView's line fragment padding, so the placeholder starts where typed text does.
    private static let textViewLinePadding: CGFloat = 5
    /// About four lines of body text.
    private static let noteMinHeight: CGFloat = 96

    var body: some View {
        ScrollView {
            if let drop = model.selectedDrop {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    noteSection
                    tagSection
                    section(L10n.t("source")) {
                        Text(drop.source.appName ?? L10n.t("unknownApp"))
                        Text("\(L10n.t("savedAt")) \(Formatting.dateTime(drop.createdAt))").font(.caption).foregroundStyle(.secondary)
                        Button { model.showDropsFromSource(of: drop) } label: {
                            Label(L10n.t("showSourceDrops"), systemImage: "line.3.horizontal.decrease")
                        }
                        .controlSize(.small)
                        .disabled(!LibraryModel.hasSource(drop))
                    }
                    DisclosureGroup(L10n.t("sourceDetails")) {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            detail(L10n.t("window"), drop.source.windowTitle)
                            detail(L10n.t("updatedAt"), Formatting.dateTime(drop.updatedAt))
                            detail(L10n.t("url"), drop.source.url)
                            detail(L10n.t("file"), drop.source.filePath)
                        }
                    }
                }
                .padding(Spacing.l).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .slimScrollers()
    }

    // MARK: Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(L10n.t("note")).font(.headline)
                Spacer()
                saveStatus
            }
            TextEditor(text: Binding(get: { editor.draft.note }, set: { editor.setNote($0) }))
                .font(.body).scrollContentBackground(.hidden).slimScrollers()
                .padding(Spacing.xs).frame(minHeight: Self.noteMinHeight)
                .inputSurface(focused: noteFocused)
                .overlay(alignment: .topLeading) {
                    if editor.draft.note.isEmpty { Text(L10n.t("noNote")).foregroundStyle(.secondary).padding(.horizontal, Spacing.xs + Self.textViewLinePadding).padding(.vertical, Spacing.xs).allowsHitTesting(false) }
                }
                .focused($noteFocused)
                .accessibilityLabel(L10n.t("note"))
                .onExitCommand { noteFocused = false }
                .onChange(of: noteFocused) { _, focused in if !focused { Task { await editor.flush() } } }
        }
    }

    @ViewBuilder private var saveStatus: some View {
        HStack(spacing: Spacing.s) {
            switch editor.state {
            case .idle: Text(L10n.t("automaticSave"))
            case .pending: Text(L10n.t("changesPending"))
            case .saving: Text(L10n.t("saving"))
            case .saved: Text(L10n.t("saved"))
            case .failed(let code):
                Text(code == "blankTitle" ? ErrorText.message(forCode: code) : L10n.t("saveFailed")).foregroundStyle(.red)
                Button(L10n.t("retrySave")) { Task { await editor.retry() } }.controlSize(.small)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Tags

    private var tagSection: some View {
        section(L10n.t("tags")) {
            TagEntryField(model: editor, focused: $tagFocused, emptyText: L10n.t("noTags"), onExit: { tagFocused = false })
                .onChange(of: tagFocused) { _, focused in if !focused { Task { await editor.flush() } } }
        }
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) { Text(title).font(.headline); body() }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

/// A small accent dot before a status word: "● Editing", "● Changed" (spec 2.6).
struct StatusDot: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(Color.accentColor).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The label of an icon action button: a 38 x 26 pt cell (spec 2.6, MainFeatures design). Move to Trash is drawn red;
/// a pinned Pin takes the accent from `DropActionToggleStyle`.
struct DropActionIcon: View {
    static let buttonSize = CGSize(width: 38, height: 26)
    /// From the MainFeatures design: 6 pt between buttons, a 16 pt divider before Move to Trash.
    static let gap: CGFloat = 6
    static let dividerHeight: CGFloat = 16
    let action: DropAction

    var body: some View {
        // Only Trash sets its own color; the others take the button style's foreground (accent while pinned).
        if action == .moveTrash { icon.foregroundStyle(.red) } else { icon }
    }

    private var icon: some View {
        Image(systemName: action.systemImage)
            .font(.system(size: 13))
            .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
            .contentShape(Rectangle())
    }
}

/// The MainFeatures action button: a rounded cell with a hairline border on the control background. Hover darkens the
/// border and fill, pressing darkens the fill more, and `isOn` (a pinned Pin) tints it with the accent.
struct DropActionButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        DropActionCell(configuration: configuration, isOn: isOn)
    }
}

/// Pin's toggle: the same cell, tinted while on, keeping the toggle's VoiceOver state.
struct DropActionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(DropActionButtonStyle(isOn: configuration.isOn))
    }
}

private struct DropActionCell: View {
    static let radius: CGFloat = 7
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        configuration.label
            .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 && isEnabled }
    }

    private var fill: AnyShapeStyle {
        if isOn { return AnyShapeStyle(Color.accentColor.opacity(configuration.isPressed ? 0.18 : 0.10)) }
        if configuration.isPressed { return AnyShapeStyle(Color.primary.opacity(0.10)) }
        if hovering { return AnyShapeStyle(Color.primary.opacity(0.05)) }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    private var border: Color {
        if isOn { return Color.accentColor.opacity(0.35) }
        return Color.primary.opacity(hovering || configuration.isPressed ? 0.22 : 0.12)
    }
}

extension View {
    /// The MainFeatures tooltip: a small bubble centered under the button after a short hover. The system `.help`
    /// tooltip does not appear on these custom-styled buttons, so the bubble is drawn here instead.
    func dropActionTooltip(_ text: String) -> some View {
        modifier(DropActionTooltip(text: text))
    }
}

private struct DropActionTooltip: ViewModifier {
    /// About the system tooltip delay.
    static let delay: Duration = .milliseconds(600)
    /// From the MainFeatures design: the bubble's top sits 6 pt under the 26 pt button.
    static let offset = DropActionIcon.buttonSize.height + 6
    let text: String
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                pending?.cancel()
                guard hovering else { shown = false; return }
                pending = Task {
                    try? await Task.sleep(for: Self.delay)
                    if !Task.isCancelled { shown = true }
                }
            }
            // A click hides it, as the system tooltip does.
            .simultaneousGesture(TapGesture().onEnded { pending?.cancel(); shown = false })
            .overlay(alignment: .top) {
                if shown {
                    Text(text)
                        .font(.system(size: 11))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
                        .fixedSize()
                        .offset(y: Self.offset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onDisappear { pending?.cancel() }
    }
}
