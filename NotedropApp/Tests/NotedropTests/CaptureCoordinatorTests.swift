import Foundation
import NotedropCore
import Testing
@testable import Notedrop

@MainActor
@Suite struct CaptureCoordinatorTests {
    @Test func successOpensThePopupWithTheDraft() async {
        var presented: CaptureDraft?
        let draft = CaptureDraft(type: .text, title: "t", text: "x")
        let coordinator = CaptureCoordinator(capture: { draft }, present: { presented = $0 }, failed: { _ in })
        await coordinator.trigger()
        #expect(presented == draft)
    }

    @Test func failureIsReportedAndNoPopupOpens() async {
        var presented = false
        var failure: NotedropError?
        let coordinator = CaptureCoordinator(
            capture: { throw NotedropError("no_selected_text") }, present: { _ in presented = true },
            failed: { failure = $0 })
        await coordinator.trigger()
        #expect(!presented)
        #expect(failure == NotedropError("no_selected_text"))
    }

    @Test func triggerWhileRunningIsDropped() async {
        let gate = Gate()
        let counter = SaveCounter()
        let coordinator = CaptureCoordinator(
            capture: {
                await counter.increment()
                await gate.wait()
                return CaptureDraft(type: .text, title: "t", text: "x")
            }, present: { _ in }, failed: { _ in })
        let first = Task { await coordinator.trigger() }
        while await counter.value == 0 { await Task.yield() }
        await coordinator.trigger()
        await gate.open()
        await first.value
        #expect(await counter.value == 1)
    }

    @Test func coordinatorsSharingAGateDoNotRunTogether() async {
        let open = Gate()
        let counter = SaveCounter()
        let shared = CaptureGate()
        let draft = CaptureDraft(type: .text, title: "t", text: "x")
        let selection = CaptureCoordinator(
            capture: {
                await counter.increment()
                await open.wait()
                return draft
            }, present: { _ in }, failed: { _ in }, gate: shared)
        let clipboard = CaptureCoordinator(
            capture: {
                await counter.increment()
                return draft
            }, present: { _ in }, failed: { _ in }, gate: shared)
        let first = Task { await selection.trigger() }
        while await counter.value == 0 { await Task.yield() }
        await clipboard.trigger()
        #expect(await counter.value == 1)
        await open.open()
        await first.value
        await clipboard.trigger()
        #expect(await counter.value == 2)
    }

    @Test func theGateStaysClosedWhileTheDraftIsBeingRouted() async {
        let open = Gate()
        let counter = SaveCounter()
        let coordinator = CaptureCoordinator(
            capture: {
                await counter.increment()
                return CaptureDraft(type: .text, title: "t", text: "x")
            }, present: { _ in await open.wait() }, failed: { _ in })
        let first = Task { await coordinator.trigger() }
        while await counter.value == 0 { await Task.yield() }
        await Task.yield()
        await coordinator.trigger()
        #expect(await counter.value == 1)
        await open.open()
        await first.value
    }

    @Test func pendingErrorIsReturnedOnce() {
        let pending = PendingCaptureError()
        pending.store(NotedropError("permission_missing"))
        #expect(pending.take() == NotedropError("permission_missing"))
        #expect(pending.take() == nil)
    }
}

@MainActor
@Suite struct LibraryCaptureTests {
    private func copyOfFixtures() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    // L-10
    @Test func reloadSelectingShowsTheNewDropEvenWhenAFilterHidesIt() async throws {
        let root = try copyOfFixtures()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(storageRoot: { root })
        await model.reload()
        model.search = "no such text anywhere"
        #expect(model.filtered.isEmpty)
        let saved = try DropStore(root: root).saveText("brand new capture", title: nil, source: DropSource(), tags: [], note: nil)
        await model.reload(selecting: saved.id)
        #expect(model.selectedID == saved.id)
        #expect(model.search.isEmpty)
        #expect(model.filtered.contains { $0.id == saved.id })
    }

    // P-13
    @Test func pendingCaptureErrorIsShownOnceAsPendingFailed() {
        let model = LibraryModel(storageRoot: { URL(fileURLWithPath: "/nonexistent") })
        model.pendingCapture.store(NotedropError("no_selected_text"))
        model.presentPendingCaptureError()
        #expect(model.alertMessage == "\(L10n.t("pendingFailed")): \(L10n.t("noSelectedText"))")
        model.alertMessage = nil
        model.presentPendingCaptureError()
        #expect(model.alertMessage == nil)
    }
}
