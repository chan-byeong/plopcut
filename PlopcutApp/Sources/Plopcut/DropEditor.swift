import Foundation
import PlopcutCore
import Observation

/// Autosave state shown next to the note (spec 2.7).
enum SaveState: Equatable {
    case idle, pending, saving, saved
    /// Holds the error code; `ErrorText` turns it into a message.
    case failed(String)
}

enum TagAddResult: Equatable { case added, alreadyAdded, nothing }

/// Editing state for the selected drop: a draft, the last saved copy, and the autosave rules of spec 2.7
/// (600 ms debounce, save when a field is left, no blur retries after a failure, late responses ignored).
///
/// Each drop with unsaved or in-flight work owns a `Slot`. The selected drop's slot lives in the observable
/// properties below; the others wait in `slots` until their save finishes, so switching drops never loses,
/// duplicates or resurrects an edit. All writes go through one chain and reach the disk in order.
@MainActor @Observable
final class DropEditor {
    struct Draft: Equatable {
        var title = ""
        var note = ""
        var tags: [String] = []

        init(title: String = "", note: String = "", tags: [String] = []) {
            self.title = title; self.note = note; self.tags = tags
        }

        init(_ drop: Drop) { self.init(title: drop.title, note: drop.note ?? "", tags: drop.tags) }
    }

    struct Slot {
        var draft = Draft()
        var base = Draft()
        var state = SaveState.idle
        var revision = 0

        var isDirty: Bool { draft != base }
        /// Anything that still needs the disk: unsaved text, a save in flight, or a failed save.
        var needsWork: Bool {
            if isDirty { return true }
            switch state {
            case .saving, .failed: return true
            default: return false
            }
        }
    }

    static let debounce: Duration = .milliseconds(600)

    private(set) var dropID: String?
    private(set) var draft = Draft()
    private(set) var state = SaveState.idle
    /// What the title field shows. Only `commitTitle` moves it into the draft, so Escape can drop it.
    var titleText = ""
    /// Tag field text and its hint live here (not in the view) so closing the inspector keeps them (E-05).
    var tagInput = ""
    var tagMessage: String?

    private var base = Draft()
    private var revision = 0
    private var slots: [String: Slot] = [:]
    private var debounceTask: Task<Void, Never>?
    /// Every write is queued behind this task.
    private var tail: Task<Bool, Never>?
    private var queued = 0
    /// Drops with a write running right now. Their slot must outlive a switch, even if the text was reverted meanwhile.
    private var writing: [String: Int] = [:]
    private var titleEditing = false

    private let sleep: @Sendable (Duration) async throws -> Void
    private let save: @Sendable (String, DropUpdate) async throws -> Drop
    private let onSaved: @MainActor (Drop) -> Void
    private let onBackgroundFailure: @MainActor (String) -> Void
    private let log: EventLogging

    init(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        save: @escaping @Sendable (String, DropUpdate) async throws -> Drop,
        onSaved: @escaping @MainActor (Drop) -> Void,
        onBackgroundFailure: @escaping @MainActor (String) -> Void = { _ in },
        log: EventLogging = AppLog.shared
    ) {
        self.log = log
        self.sleep = sleep
        self.save = save
        self.onSaved = onSaved
        self.onBackgroundFailure = onBackgroundFailure
    }

    var isDirty: Bool { draft != base }

    /// True while anything typed has not reached the disk; the app waits for `drain()` before quitting.
    var hasUnsavedEdits: Bool {
        if queued > 0 || (titleEditing && titleText != draft.title) { return true }
        if let id = dropID, slot(id)?.needsWork == true { return true }
        return slots.values.contains { $0.needsWork }
    }

    // MARK: Slots

    private func slot(_ id: String) -> Slot? {
        id == dropID ? Slot(draft: draft, base: base, state: state, revision: revision) : slots[id]
    }

    private func store(_ slot: Slot, for id: String) {
        if id == dropID {
            draft = slot.draft; base = slot.base; state = slot.state; revision = slot.revision
        } else {
            slots[id] = slot
        }
    }

    /// Removes a finished slot of a drop that is no longer selected.
    private func dropIdleSlot(_ id: String) {
        if id != dropID, slots[id]?.needsWork == false, (writing[id] ?? 0) == 0 { slots[id] = nil }
    }

    // MARK: Showing a drop

    /// Shows a drop. Leaving a drop queues a save of its unsaved edits; coming back to it restores its draft.
    /// The same drop keeps the draft while there are unsaved edits and otherwise follows the disk.
    func show(_ drop: Drop?) {
        if let drop, drop.id == dropID {
            if !isDirty && state != .saving { adopt(drop) }
            return
        }
        debounceTask?.cancel()
        // A title typed but not committed yet belongs to the drop being left.
        if titleEditing, dropID != nil, titleText != draft.title { setTitle(titleText); debounceTask?.cancel() }
        if let old = dropID, let current = slot(old) {
            if current.needsWork || (writing[old] ?? 0) > 0 { slots[old] = current }
            if current.isDirty { _ = enqueue(old, retry: true) }
        }
        titleEditing = false
        tagInput = ""; tagMessage = nil
        guard let drop else {
            dropID = nil; draft = Draft(); base = Draft(); revision = 0; titleText = ""; state = .idle
            return
        }
        dropID = drop.id
        if let kept = slots.removeValue(forKey: drop.id) {
            store(kept, for: drop.id)
            titleText = kept.draft.title
        } else {
            revision = 0
            adopt(drop)
            state = .idle
        }
    }

    /// The drop is gone (moved to the Trash): drop its draft without saving anything.
    func forget(_ id: String) {
        slots[id] = nil
        guard dropID == id else { return }
        debounceTask?.cancel()
        dropID = nil; draft = Draft(); base = Draft(); revision = 0
        titleText = ""; tagInput = ""; tagMessage = nil; titleEditing = false; state = .idle
    }

    private func adopt(_ drop: Drop) {
        dropID = drop.id
        base = Draft(drop)
        draft = base
        if !titleEditing { titleText = drop.title }
    }

    // MARK: Editing

    func setNote(_ value: String) { edit { $0.note = value } }
    func setTitle(_ value: String) { edit { $0.title = value } }

    func addTags(_ input: String) -> TagAddResult {
        let parsed = Tags.parse(input)
        guard !parsed.isEmpty else { return .nothing }
        let fresh = parsed.filter { !draft.tags.contains($0) }
        guard !fresh.isEmpty else { return .alreadyAdded }
        edit { $0.tags += fresh }
        return .added
    }

    func removeTag(_ tag: String) { edit { $0.tags.removeAll { $0 == tag } } }

    /// Registers the tag field's text and clears it.
    func registerTagInput() {
        switch addTags(tagInput) {
        case .added: tagMessage = nil
        case .alreadyAdded: tagMessage = L10n.t("tagAlreadyAdded")
        case .nothing: break
        }
        tagInput = ""
    }

    private func edit(_ change: (inout Draft) -> Void) {
        guard dropID != nil else { return }
        change(&draft)
        revision += 1
        state = .pending
        debounceTask?.cancel()
        let sleep = sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(Self.debounce) } catch { return }
            await self?.autosave()
        }
    }

    private func autosave() async {
        guard let id = dropID else { return }
        _ = await enqueue(id, retry: false).value
    }

    // Title: Return commits, Escape reverts to the title when editing began.

    func beginTitleEdit() {
        titleEditing = true
        titleText = draft.title
    }

    func cancelTitleEdit() {
        titleEditing = false
        titleText = draft.title
    }

    /// Leaving the field untouched is not an edit: it must not restart a failed save.
    func commitTitle() async {
        titleEditing = false
        if titleText != draft.title { setTitle(titleText) }
        await flush()
    }

    // MARK: Saving

    /// Called when a field is left. A failed save waits for `retry` instead.
    func flush() async {
        if case .failed = state { return }
        guard let id = dropID else { return }
        debounceTask?.cancel()
        _ = await enqueue(id, retry: false).value
    }

    func retry() async {
        guard let id = dropID else { return }
        debounceTask?.cancel()
        _ = await enqueue(id, retry: true).value
    }

    /// Writes everything that is pending, for every drop, and waits for it. Returns false if anything stayed unsaved.
    /// Used before the app quits and before an export.
    func drain() async -> Bool {
        if titleEditing { await commitTitleForDrain() }
        debounceTask?.cancel()
        var ids = Array(slots.keys)
        if let id = dropID { ids.append(id) }
        var ok = true
        for id in ids where slot(id)?.needsWork == true {
            if await enqueue(id, retry: true).value == false { ok = false }
        }
        _ = await tail?.value
        return ok && !hasUnsavedEdits
    }

    private func commitTitleForDrain() async {
        titleEditing = false
        if titleText != draft.title { setTitle(titleText) }
    }

    /// Queues one write behind every write already queued, so saves reach the disk one at a time and in order.
    /// `retry` is false for writes that only follow a field being left: they must not restart a failed save.
    private func enqueue(_ id: String, retry: Bool) -> Task<Bool, Never> {
        let previous = tail
        queued += 1
        let task = Task { @MainActor [weak self] () -> Bool in
            _ = await previous?.value
            guard let self else { return false }
            defer { self.queued -= 1 }
            let ok = await self.writeNow(id, retry: retry)
            if !ok, id != self.dropID, case .failed(let code)? = self.slots[id]?.state { self.onBackgroundFailure(code) }
            return ok
        }
        tail = task
        return task
    }

    /// Writes one drop's pending changes. Returns true when nothing is left unsaved for it.
    private func writeNow(_ id: String, retry: Bool = true) async -> Bool {
        guard var slot = slot(id) else { return true }
        if !retry, case .failed = slot.state { return false }
        guard slot.isDirty else {
            if slot.state == .pending { slot.state = .saved; store(slot, for: id) }
            dropIdleSlot(id)
            return true
        }
        guard !slot.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            slot.state = .failed("blankTitle")
            store(slot, for: id)
            return false
        }
        let update = update(for: slot.draft, from: slot.base)
        let sentRevision = slot.revision
        // A retry of a save that already failed is the same failure event: only the change into failed is logged.
        var wasFailed = false
        if case .failed = slot.state { wasFailed = true }
        slot.state = .saving
        store(slot, for: id)
        writing[id, default: 0] += 1
        do {
            let saved = try await save(id, update)
            writing[id, default: 1] -= 1
            // Read the slot again: edits, a switch, or a delete may have happened while the write ran.
            guard var latest = self.slot(id) else { onSaved(saved); return true }
            latest.base = Draft(saved)
            if latest.revision == sentRevision {
                latest.draft = latest.base
                latest.state = .saved
                if id == dropID && !titleEditing { titleText = latest.base.title }
            } else {
                latest.state = latest.isDirty ? .pending : .saved
            }
            store(latest, for: id)
            onSaved(saved)
            // A drop that is no longer selected has no debounce: write what was typed since.
            if id != dropID, latest.isDirty { return await writeNow(id) }
            dropIdleSlot(id)
            return !latest.isDirty || id == dropID
        } catch {
            writing[id, default: 1] -= 1
            let code = (error as? PlopcutError)?.code ?? "defaultError"
            if !wasFailed { log.log(error: error) }
            guard var latest = self.slot(id) else { return false }
            latest.state = latest.revision == sentRevision ? .failed(code) : .pending
            store(latest, for: id)
            return false
        }
    }

    private func update(for draft: Draft, from base: Draft) -> DropUpdate {
        var update = DropUpdate()
        if draft.title != base.title { update.title = draft.title }
        if draft.note != base.note { update.note = draft.note }
        if draft.tags != base.tags { update.tags = draft.tags }
        return update
    }
}
