import Foundation
import NotedropCore
import Observation

/// What the popup asks storage to write.
struct SaveRequest: Equatable, Sendable {
    var text: String
    var title: String
    var source: DropSource
    var note: String?
    var tags: [String]
}

/// State of one Save Popup (spec 3.5). The popup never closes itself: the owner reacts to `onSaved` and `onCancel`.
@MainActor @Observable
final class SavePopupModel {
    let draft: CaptureDraft
    let recentTags: [String]

    var note = ""
    var tagInput = ""
    var tagMessage: String?
    private(set) var tags: [String]
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let save: @Sendable (SaveRequest) async throws -> Drop
    private let onSaved: (Drop) -> Void
    private let onCancel: () -> Void

    init(
        draft: CaptureDraft, recentTags: [String], save: @escaping @Sendable (SaveRequest) async throws -> Drop,
        onSaved: @escaping (Drop) -> Void, onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.recentTags = recentTags
        self.tags = draft.tags
        self.note = draft.note ?? ""
        self.save = save
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    /// One line: `app · window · URL`, or the unknown-source text when nothing was collected.
    var sourceSummary: String {
        let parts = [draft.source.appName, draft.source.windowTitle, draft.source.url]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? L10n.t("unknown") : parts.joined(separator: " · ")
    }

    // MARK: Tags (checklist I-02)

    /// Registers the tag field's text; a tag that is already there only shows the "already added" hint.
    func registerTagInput() {
        let parsed = Tags.parse(tagInput)
        tagInput = ""
        guard !parsed.isEmpty else { return }
        let fresh = parsed.filter { !tags.contains($0) }
        if fresh.isEmpty {
            tagMessage = L10n.t("tagAlreadyAdded")
        } else {
            tags += fresh
            tagMessage = nil
        }
    }

    func addRecentTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        tagMessage = nil
    }

    func removeTag(_ tag: String) { tags.removeAll { $0 == tag } }

    // MARK: Actions

    /// Saves the draft. Ignored while a save is running (checklist I-04). A failure keeps the popup open.
    func submit() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        // Text typed in the tag field but not yet confirmed still counts.
        if !tagInput.trimmingCharacters(in: .whitespaces).isEmpty { registerTagInput() }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SaveRequest(
            text: draft.text ?? "", title: draft.title, source: draft.source,
            note: trimmedNote.isEmpty ? nil : note, tags: tags)
        do {
            let drop = try await save(request)
            onSaved(drop)
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    /// Ignored while a save runs: closing then would let the finishing save close the next popup.
    func cancel() {
        guard !isSaving else { return }
        onCancel()
    }
}
