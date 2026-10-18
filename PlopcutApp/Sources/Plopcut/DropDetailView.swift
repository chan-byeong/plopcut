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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    // The type is an eyebrow over the title, so the two stay together.
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(drop.type == .image ? L10n.t("imageDrops") : drop.type == .text ? L10n.t("textDrops") : drop.type.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                        titleField
                    }
                    actions(for: drop)
                    Divider()
                    body(of: drop)
                }
                .padding(Spacing.xxl).frame(maxWidth: .infinity, alignment: .leading)
            }
            .slimScrollers()
        } else {
            ContentUnavailableView(L10n.t("selectHint"), systemImage: "text.cursor")
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

    /// Icon-only buttons: Pin · Open Source · Export Markdown | Move to Trash (spec 2.6). PLO-104 adds Edit after Pin.
    private func actions(for drop: Drop) -> some View {
        HStack(spacing: Spacing.xs) {
            let pin = DropAction.pin(pinned: drop.isPinned)
            Toggle(isOn: Binding(get: { drop.isPinned }, set: { _ in Task { await model.togglePin(id: drop.id) } })) {
                DropActionIcon(action: pin)
            }
            .toggleStyle(.button)
            .help(pin.tooltip).accessibilityLabel(pin.title)
            actionButton(.openSource) { openSource(drop) }
                .disabled(URL(string: drop.source.url ?? "") == nil || drop.source.url?.isEmpty != false)
            actionButton(.exportMarkdown) { Task { await model.exportWithPanel(id: drop.id) } }
            Divider().frame(height: DropActionIcon.buttonSize.height)
            actionButton(.moveTrash, role: .destructive) { model.pendingDeleteID = drop.id }
        }
    }

    private func actionButton(_ action: DropAction, role: ButtonRole? = nil, perform: @escaping () -> Void) -> some View {
        Button(role: role, action: perform) { DropActionIcon(action: action) }
            .help(action.tooltip).accessibilityLabel(action.title)
    }

    @ViewBuilder private func body(of drop: Drop) -> some View {
        if let url = drop.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: Self.imageMaxWidth)
                .accessibilityLabel(L10n.t("image"))
        } else if drop.type == .image {
            Label(L10n.t("imagePreviewUnavailable"), systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
        } else if let text = drop.text {
            Text(text).font(.body).textSelection(.enabled)
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

/// The label of an icon action button (spec 2.6). The native bordered bezel adds its own padding, so the label is
/// smaller than the 38 x 26 pt button it ends up in. Move to Trash is drawn red.
struct DropActionIcon: View {
    static let buttonSize = CGSize(width: 38, height: 26)
    /// Optical: the bordered bezel's padding at regular size, measured in the running app.
    static let bezelInset = CGSize(width: 16, height: 2)
    let action: DropAction

    var body: some View {
        Image(systemName: action.systemImage)
            .foregroundStyle(action == .moveTrash ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .frame(width: Self.buttonSize.width - Self.bezelInset.width, height: Self.buttonSize.height - Self.bezelInset.height)
            .contentShape(Rectangle())
    }
}
