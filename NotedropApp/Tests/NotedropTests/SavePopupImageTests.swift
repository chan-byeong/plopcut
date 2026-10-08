import Foundation
import NotedropCore
import Testing
@testable import Notedrop

@MainActor
@Suite struct SavePopupImageTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

    private final class Captured: @unchecked Sendable { var request: SaveRequest? }

    private func model(_ draft: CaptureDraft, captured: Captured, fail: NotedropError? = nil) -> SavePopupModel {
        SavePopupModel(
            draft: draft, recentTags: [],
            save: { request in
                if let fail { throw fail }
                captured.request = request
                return Drop(id: "d", type: request.imagePNG == nil ? .text : .image, title: request.title,
                            source: request.source, tags: request.tags, createdAt: "t", updatedAt: "t")
            },
            onSaved: { _ in }, onCancel: {})
    }

    @Test func imageDraftSavesTheImageAndNoText() async {
        let captured = Captured()
        let draft = CaptureDraft(type: .image, title: "Shot", imagePNG: Self.png)
        let m = model(draft, captured: captured)
        #expect(!m.isMixed)
        #expect(m.selectedType == .image)
        await m.submit()
        #expect(captured.request?.imagePNG == Self.png)
        #expect(captured.request?.text == "")
    }

    @Test func textDraftStillSavesText() async {
        let captured = Captured()
        let m = model(CaptureDraft(type: .text, title: "t", text: "hello"), captured: captured)
        await m.submit()
        #expect(captured.request?.text == "hello")
        #expect(captured.request?.imagePNG == nil)
    }

    @Test func mixedDraftOffersAChoiceAndDefaultsToText() async {
        let captured = Captured()
        let draft = CaptureDraft(type: .mixed, title: "t", text: "caption", imagePNG: Self.png)
        let m = model(draft, captured: captured)
        #expect(m.isMixed)
        #expect(m.selectedType == .text)
        await m.submit()
        #expect(captured.request?.text == "caption")
        #expect(captured.request?.imagePNG == nil)
    }

    @Test func mixedDraftSavesOnlyTheImageWhenChosen() async {
        let captured = Captured()
        let draft = CaptureDraft(type: .mixed, title: "t", text: "caption", imagePNG: Self.png)
        let m = model(draft, captured: captured)
        m.selectedType = .image
        await m.submit()
        #expect(captured.request?.imagePNG == Self.png)
        #expect(captured.request?.text == "")
    }

    // S-10: a rejected image keeps the popup open with the reason.
    @Test func aRejectedImageShowsTheReason() async {
        let draft = CaptureDraft(type: .image, title: "t", imagePNG: Self.png)
        let m = model(draft, captured: Captured(), fail: NotedropError("invalid_image"))
        await m.submit()
        #expect(m.errorMessage == L10n.t("invalidImage"))
    }
}
