import AppKit
import NotedropCore
import SwiftUI

struct DropDetailView: View {
    @Bindable var model: LibraryModel
    var listFocused: FocusState<Bool>.Binding
    @FocusState private var titleFocused: Bool

    private var editor: DropEditor { model.editor }

    var body: some View {
        if let drop = model.selectedDrop {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(drop.type == .image ? L10n.t("imageDrops") : drop.type == .text ? L10n.t("textDrops") : drop.type.rawValue)
                        .font(.caption).foregroundStyle(.secondary)
                    titleField
                    actions(for: drop)
                    Divider()
                    body(of: drop)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .slimScrollers()
        } else {
            ContentUnavailableView(L10n.t("selectHint"), systemImage: "text.cursor")
        }
    }

    /// Always-visible inline rename: the text never moves, the field chrome appears only while editing (spec 2.6).
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: Bindable(editor).titleText)
                .textFieldStyle(.plain).font(.title.bold())
                .padding(.horizontal, 6).padding(.vertical, 2).padding(.horizontal, -6)
                .background(titleFocused ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(titleFocused ? Color.accentColor : .clear, lineWidth: 2))
                .focused($titleFocused)
                                .onSubmit { finishTitle(commit: true) }
                .onExitCommand { finishTitle(commit: false) }
                .onChange(of: titleFocused) { _, focused in
                    if focused { editor.beginTitleEdit() } else { Task { await editor.commitTitle() } }
                }
            if case .failed(let code) = editor.state, code == "blankTitle" || code == "invalid_title" {
                Text(ErrorText.message(forCode: code)).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func finishTitle(commit: Bool) {
        if !commit { editor.cancelTitleEdit() }
        listFocused.wrappedValue = true
    }

    private func actions(for drop: Drop) -> some View {
        HStack {
            Button { openSource(drop) } label: { Label(L10n.t("openSource"), systemImage: "arrow.up.right.square") }
                .disabled(URL(string: drop.source.url ?? "") == nil || drop.source.url?.isEmpty != false)
            Button { Task { await model.exportWithPanel(id: drop.id) } } label: { Label(L10n.t("exportMarkdown"), systemImage: "square.and.arrow.down") }
            Button(role: .destructive) { model.pendingDeleteID = drop.id } label: { Label(L10n.t("moveTrash"), systemImage: "trash") }
        }
    }

    @ViewBuilder private func body(of drop: Drop) -> some View {
        if let url = drop.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 640)
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

    var body: some View {
        ScrollView {
            if let drop = model.selectedDrop {
                VStack(alignment: .leading, spacing: 18) {
                    noteSection
                    tagSection
                    section(L10n.t("source")) {
                        Text(drop.source.appName ?? L10n.t("unknownApp"))
                        Text("\(L10n.t("savedAt")) \(Formatting.dateTime(drop.createdAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup(L10n.t("sourceDetails")) {
                        VStack(alignment: .leading, spacing: 6) {
                            detail(L10n.t("window"), drop.source.windowTitle)
                            detail(L10n.t("updatedAt"), Formatting.dateTime(drop.updatedAt))
                            detail(L10n.t("url"), drop.source.url)
                            detail(L10n.t("file"), drop.source.filePath)
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .slimScrollers()
    }

    // MARK: Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("note")).font(.headline)
                Spacer()
                saveStatus
            }
            TextEditor(text: Binding(get: { editor.draft.note }, set: { editor.setNote($0) }))
                .font(.body).scrollContentBackground(.hidden).slimScrollers()
                .padding(4).frame(minHeight: 96)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(noteFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: noteFocused ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    if editor.draft.note.isEmpty { Text(L10n.t("noNote")).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false) }
                }
                .focused($noteFocused)
                .accessibilityLabel(L10n.t("note"))
                .onExitCommand { noteFocused = false }
                .onChange(of: noteFocused) { _, focused in if !focused { Task { await editor.flush() } } }
        }
    }

    @ViewBuilder private var saveStatus: some View {
        HStack(spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("tags")).font(.headline)
            HStack {
                TextField(L10n.t("tagPlaceholder"), text: Bindable(editor).tagInput)
                    .focused($tagFocused)
                    .onSubmit { register() }
                    .onExitCommand { tagFocused = false }
                    .onChange(of: tagFocused) { _, focused in
                        CompositionMonitor.shared.reset()
                        if !focused { Task { await editor.flush() } }
                    }
                    .onChange(of: editor.tagInput) { old, value in
                        if !value.isEmpty { editor.tagMessage = nil }
                        // A typed comma registers; a comma left behind by a composition commit must not register
                        // the next syllable. Pasted text with commas still registers.
                        let pasted = value.count - old.count > 1
                        if value.hasSuffix(",") || (pasted && value.contains(",")) { register() }
                    }
                    .accessibilityLabel(L10n.t("tags"))
                Button(L10n.t("addTag")) { register() }
                    .disabled(editor.tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message = editor.tagMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            if editor.draft.tags.isEmpty {
                Text(L10n.t("noTags")).foregroundStyle(.secondary)
            } else {
                FlowLayout {
                    ForEach(editor.draft.tags, id: \.self) { tag in
                        Button {
                            editor.removeTag(tag)
                            tagFocused = true
                        } label: { Label("#\(tag)", systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityLabel("\(L10n.t("removeTag")) #\(tag)")
                    }
                }
            }
        }
    }

    /// Enter and comma register tags, but not the key that only commits an input-method composition (spec I-01).
    private func register() {
        if CompositionMonitor.shared.shouldIgnoreRegistration { return }
        editor.registerTagInput()
        tagFocused = true
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); body() }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}
