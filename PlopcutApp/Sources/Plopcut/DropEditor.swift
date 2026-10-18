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

/// The content editor of one text drop (spec 2.6 "본문 편집", PLO-104). Saved only by Done, never automatically.
struct BodyEdit: Equatable {
    enum State: Equatable {
        case editing, saving
        /// Holds the error code; the editor stays open with the typed text.
        case failed(String)
    }

    let dropID: String
    /// The content when editing began; "changed" compares against it.
    var original: String
    var text: String
    var state = State.editing

    var isChanged: Bool { text != original }
}

/// Editing state for the selected drop: a draft, the last saved copy, and the autosave rules of spec 2.7
/// (600 ms debounce, save when a field is left, no blur retries after a failure, late responses ignored).
///
/// Each drop with unsaved or in-flight work owns a `Slot`. The selected drop's slot lives in the observable
/// properties below; the others wait in `slots` until their save finishes, so switching drops never loses,
/// duplicates or resurrects an edit. All writes of the Library (autosave, Done, pin, format) go through one chain,
/// reach the disk in order, and hand their result to `onSaved` in that order.
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
    private var tail: Task<Void, Never>?
    private var queued = 0
    /// Drops with a write running right now. Their slot must outlive a switch, even if the text was reverted meanwhile.
    private var writing: [String: Int] = [:]
    private var titleEditing = false
    /// The open content editor, if any. Separate from the title, note and tag draft above (spec 2.6, E-12).
    private(set) var bodyEdit: BodyEdit?
    /// The move (cancel, another drop, another Collection) waiting for "Discard changes?" (E-10).
    private var pendingLeave: (@MainActor () -> Void)?
    private(set) var isConfirmingDiscard = false
    /// The move asked for while Done was writing; it runs once the write succeeds (E-15).
    private var moveAfterSave: (@MainActor () -> Void)?
    /// The content write of Done while it runs.
    private var bodySave: Task<Bool, Never>?

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

    /// True when quitting must wait: unsaved autosave edits, a content save in flight, or a changed content draft.
    var needsWorkBeforeQuit: Bool { hasUnsavedEdits || bodyChanged }

    /// Gets the editor ready to quit (E-16). A content save already running is waited for. A changed content draft
    /// is never saved on its own: `ask` decides, Save goes through Done, and a failed save keeps the app open with
    /// the editor and its error. Then every autosave is drained.
    func prepareToQuit(ask: @MainActor () async -> BodyDraftQuitChoice) async -> QuitPreparation {
        if let bodySave { _ = await bodySave.value }
        if bodyChanged {
            switch await ask() {
            case .cancel: return .cancelled
            case .discard: closeBodyEdit()
            case .save: if await finishBodyEdit() == false { return .cancelled }
            }
        }
        return await drain() ? .ready : .failed
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
        if bodyEdit != nil, bodyEdit?.dropID != drop?.id { closeBodyEdit() }
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
        if bodyEdit?.dropID == id { closeBodyEdit() }
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

    // MARK: Content editing (spec 2.6 "본문 편집")

    var isEditingBody: Bool { bodyEdit != nil }
    var bodyChanged: Bool { bodyEdit?.isChanged ?? false }

    /// False while Done is writing: the text sent must be the text kept, so typing waits for the result (E-14).
    var isBodyEditable: Bool { bodyEdit != nil && bodyEdit?.state != .saving }

    /// What the content editor shows. Setting it is ignored when no editor is open or while its save is pending.
    var bodyText: String {
        get { bodyEdit?.text ?? "" }
        set {
            guard isBodyEditable, var edit = bodyEdit, edit.text != newValue else { return }
            edit.text = newValue
            bodyEdit = edit
        }
    }

    /// Only a text drop whose content could be read can be edited; image drops cannot (E-07).
    static func canEditBody(_ drop: Drop?) -> Bool { drop?.type == .text && drop?.text != nil }

    /// Opens the content editor on the drop's current text. Returns false when the drop cannot be edited.
    @discardableResult
    func beginBodyEdit(_ drop: Drop) -> Bool {
        guard Self.canEditBody(drop), let text = drop.text else { return false }
        if bodyEdit?.dropID == drop.id { return true }
        bodyEdit = BodyEdit(dropID: drop.id, original: text, text: text)
        return true
    }

    /// Done: writes the typed text to content.md without asking (E-08). Returns true when the editor closed.
    func finishBodyEdit() async -> Bool {
        guard var edit = bodyEdit, edit.state != .saving else { return false }
        guard edit.isChanged else { bodyEdit = nil; return true }
        // The store refuses it too (`empty_text`); checking here keeps the editor open without a write (E-09).
        guard edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            edit.state = .failed("empty_text")
            bodyEdit = edit
            return false
        }
        let id = edit.dropID, text = edit.text
        edit.state = .saving
        bodyEdit = edit
        let task = Task { await self.writeBody(text, of: id) }
        bodySave = task
        return await task.value
    }

    /// The content write of Done. A move asked for meanwhile runs after a success and is dropped after a failure,
    /// which leaves the editor open with the typed text and the error (E-15).
    private func writeBody(_ text: String, of id: String) async -> Bool {
        defer { bodySave = nil; moveAfterSave = nil }
        do {
            _ = try await queueChange(for: id) { [weak self] _ in
                if self?.bodyEdit?.dropID == id { self?.bodyEdit = nil }
            } update: { DropUpdate(text: text) }
        } catch {
            log.log(error: error)
            let code = ErrorText.code(for: error)
            if var latest = bodyEdit, latest.dropID == id {
                latest.state = .failed(code)
                bodyEdit = latest
            } else {
                // The drop went away (moved to the Trash) while the write ran; the failure must still be seen.
                onBackgroundFailure(code)
            }
            return false
        }
        let move = moveAfterSave
        moveAfterSave = nil
        move?()
        return true
    }

    /// Cancel (button or Escape): ends at once without a change, otherwise asks first (E-10).
    func cancelBodyEdit() { requestLeave {} }

    /// Runs `proceed` once the content editor may close: at once when nothing typed would be lost, otherwise after
    /// the user confirms "Discard changes?". Until then the move is held, and Keep Editing drops it (E-10).
    /// While Done is writing the move is held without asking and follows the write's result (E-15).
    func requestLeave(_ proceed: @escaping @MainActor () -> Void) {
        if bodyEdit?.state == .saving {
            // Closing now would lose the text if the write fails; the latest move waits for the result (E-15).
            moveAfterSave = proceed
            return
        }
        guard let edit = bodyEdit, edit.isChanged else {
            closeBodyEdit()
            proceed()
            return
        }
        pendingLeave = proceed
        isConfirmingDiscard = true
    }

    /// Discard: drops the typed text without writing and runs the held move.
    func confirmDiscard() {
        let proceed = pendingLeave
        closeBodyEdit()
        proceed?()
    }

    /// Keep Editing: the held move is dropped and the editor stays as it was.
    func keepEditing() {
        pendingLeave = nil
        isConfirmingDiscard = false
    }

    private func closeBodyEdit() {
        bodyEdit = nil
        pendingLeave = nil
        moveAfterSave = nil
        isConfirmingDiscard = false
    }

    /// Writes one change of a drop behind every write already queued, so it never overwrites an autosave or another
    /// change in drop.json. `update` runs when the write's turn comes, so it sees what earlier writes left (a toggle
    /// reads the pin the previous toggle saved); nil writes nothing and returns nil. On success `prepare` and then
    /// `onSaved` run before the next queued write starts.
    func queueChange(
        for id: String,
        prepare: @escaping @MainActor (Drop) -> Void = { _ in },
        update: @escaping @MainActor () -> DropUpdate?
    ) async throws -> Drop? {
        try await run { [weak self, save] () -> Result<Drop?, Error> in
            guard let change = update() else { return .success(nil) }
            do {
                let saved = try await save(id, change)
                prepare(saved)
                self?.onSaved(saved)
                return .success(saved)
            } catch {
                return .failure(error)
            }
        }.value.get()
    }

    /// Runs `work` after every write already queued; `queued` counts it until it ends.
    private func run<T: Sendable>(_ work: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = tail
        queued += 1
        let task = Task { @MainActor [weak self] () -> T in
            await previous?.value
            let result = await work()
            self?.queued -= 1
            return result
        }
        tail = Task { _ = await task.value }
        return task
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
        run { [weak self] in
            guard let self else { return false }
            let ok = await self.writeNow(id, retry: retry)
            if !ok, id != self.dropID, case .failed(let code)? = self.slots[id]?.state { self.onBackgroundFailure(code) }
            return ok
        }
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
            let code = ErrorText.code(for: error)
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

extension DropEditor: TagEditing {
    var currentTags: [String] { draft.tags }
}
