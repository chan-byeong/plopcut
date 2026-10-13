import Foundation
import PlopcutCore
import Testing
@testable import Plopcut

@MainActor
@Suite struct CaptureRouterTests {
    @MainActor private final class Spy {
        var popups: [CaptureDraft] = []
        var saved: [Drop] = []
        var failures: [PlopcutError] = []
        var requests: [SaveRequest] = []
        var modeReads = 0
    }

    private nonisolated static let drop = Drop(id: "d1", type: .text, title: "t", createdAt: "t", updatedAt: "t")

    private func router(
        _ spy: Spy, mode: @escaping () -> CaptureConfirmationMode, failWith: PlopcutError? = nil
    ) -> CaptureRouter {
        CaptureRouter(
            mode: { spy.modeReads += 1; return mode() },
            save: { request in
                await MainActor.run { spy.requests.append(request) }
                if let failWith { throw failWith }
                return Self.drop
            },
            showPopup: { spy.popups.append($0) },
            saved: { spy.saved.append($0) },
            failed: { spy.failures.append($0) })
    }

    // P-11
    @Test func instantTextIsSavedWithAnEmptyNoteAndNoTags() async {
        let spy = Spy()
        let source = DropSource(appName: "Safari")
        let draft = CaptureDraft(type: .text, title: "Hello", text: "body", source: source, tags: ["ignored"])
        await router(spy, mode: { .instant }).route(draft)
        #expect(spy.popups.isEmpty)
        #expect(spy.saved == [Self.drop])
        #expect(spy.requests == [SaveRequest(text: "body", title: "Hello", source: source, note: "", tags: [], imagePNG: nil)])
    }

    // P-12
    @Test func instantImageAndMixedOpenThePopupAndSaveNothing() async {
        let spy = Spy()
        let png = Data([0x89, 0x50])
        await router(spy, mode: { .instant }).route(CaptureDraft(type: .image, title: "i", imagePNG: png))
        await router(spy, mode: { .instant }).route(CaptureDraft(type: .mixed, title: "m", text: "t", imagePNG: png))
        #expect(spy.popups.count == 2)
        #expect(spy.requests.isEmpty)
    }

    @Test func modalOpensThePopupForText() async {
        let spy = Spy()
        await router(spy, mode: { .modal }).route(CaptureDraft(type: .text, title: "t", text: "x"))
        #expect(spy.popups.count == 1)
        #expect(spy.requests.isEmpty)
    }

    // A change in Settings applies to the very next capture.
    @Test func theModeIsReadAtEveryCapture() async {
        let spy = Spy()
        var mode = CaptureConfirmationMode.instant
        let r = router(spy, mode: { mode })
        let draft = CaptureDraft(type: .text, title: "t", text: "x")
        await r.route(draft)
        mode = .modal
        await r.route(draft)
        #expect(spy.saved.count == 1)
        #expect(spy.popups.count == 1)
        #expect(spy.modeReads == 2)
    }

    @Test func aFailedInstantSaveIsReportedAndNothingIsShownAsSaved() async {
        let spy = Spy()
        await router(spy, mode: { .instant }, failWith: PlopcutError("storage_unwritable"))
            .route(CaptureDraft(type: .text, title: "t", text: "x"))
        #expect(spy.failures == [PlopcutError("storage_unwritable")])
        #expect(spy.saved.isEmpty)
        #expect(spy.popups.isEmpty)
    }
}
