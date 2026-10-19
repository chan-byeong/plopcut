import AppKit
import Foundation
import PlopcutCore
import Observation

/// What the popup asks storage to write: a text drop, or an image drop when `imagePNG` is set.
struct SaveRequest: Equatable, Sendable {
    var text: String
    /// The title the user asked for; nil lets storage infer it (spec 1.4).
    var title: String?
    var source: DropSource
    var note: String?
    var tags: [String]
    var imagePNG: Data?
}

/// State of one Save Popup (spec 3.5). The popup never closes itself: the owner reacts to `onSaved` and `onCancel`.
@MainActor @Observable
final class SavePopupModel {
    let draft: CaptureDraft
    let recentTags: [String]
    /// Decoded once; the view body runs on every keystroke and must not decode the PNG again.
    @ObservationIgnored let previewImage: NSImage?

    /// For a `mixed` draft the user picks one; only that type is saved (spec 3.5, checklist D-02).
    var selectedType: DropType
    var note = ""
    var tagInput = ""
    var tagMessage: String?
    private(set) var tags: [String]
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    /// What the user typed over the automatic title; nil while the field follows it (spec 3.5, PLO-105).
    private var editedTitle: String?

    private let save: @Sendable (SaveRequest) async throws -> Drop
    private let onSaved: (Drop) -> Void
    private let onCancel: () -> Void
    private let log: EventLogging

    init(
        draft: CaptureDraft, recentTags: [String], save: @escaping @Sendable (SaveRequest) async throws -> Drop,
        onSaved: @escaping (Drop) -> Void, onCancel: @escaping () -> Void,
        log: EventLogging = AppLog.shared
    ) {
        self.log = log
        self.draft = draft
        self.previewImage = draft.imagePNG.flatMap { NSImage(data: $0) }
        self.selectedType = draft.type == .mixed ? .text : draft.type
        self.recentTags = recentTags
        self.tags = draft.tags
        self.note = draft.note ?? ""
        self.save = save
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var isMixed: Bool { draft.type == .mixed }

    // MARK: Title (spec 3.5, PLO-105)

    /// The title storage would infer for the type being saved; the capture worked it out with spec 1.4's order.
    var autoTitle: String { selectedType == .image ? (draft.imageTitle ?? draft.title) : draft.title }

    /// The title field. It follows `autoTitle` until the user types something else.
    var title: String {
        get { editedTitle ?? autoTitle }
        set { editedTitle = newValue == autoTitle ? nil : newValue }
    }

    /// The `Auto` button is only offered when it would change the field.
    var canRestoreAutoTitle: Bool { title != autoTitle }

    func restoreAutoTitle() { editedTitle = nil }

    /// Where the automatic title came from, by spec 1.4's order, and that an empty field saves it.
    var titleHint: String {
        let source = draft.source
        let firstLine = selectedType == .image ? nil : draft.text?
            .split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let key = if source.windowTitle?.trimmedOrNil != nil {
            "titleHintWindow"
        } else if source.appName?.trimmedOrNil != nil {
            "titleHintApp"
        } else if firstLine != nil {
            "titleHintFirstLine"
        } else {
            "titleHintDefault"
        }
        return L10n.t(key)
    }

    /// How the text preview renders: the Library's automatic detection (spec 3.5, PLO-101). The popup never stores a choice.
    var previewFormat: ResolvedFormat {
        FormatDetection.detect(text: draft.text ?? "", source: draft.source)
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
        let saveImage = selectedType == .image
        let request = SaveRequest(
            text: saveImage ? "" : draft.text ?? "", title: title.trimmedOrNil, source: draft.source,
            note: trimmedNote.isEmpty ? nil : note, tags: tags, imagePNG: saveImage ? draft.imagePNG : nil)
        do {
            let drop = try await save(request)
            onSaved(drop)
        } catch {
            log.log(error: error)
            errorMessage = ErrorText.message(for: error)
        }
    }

    /// Ignored while a save runs: closing then would let the finishing save close the next popup.
    func cancel() {
        guard !isSaving else { return }
        onCancel()
    }
}

extension SavePopupModel: TagEditing {
    var currentTags: [String] { tags }
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
