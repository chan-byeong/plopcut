import Testing
@testable import NotedropCore

@Suite struct CaptureConfirmationTests {
    // P-11
    @Test func modalAlwaysOpensThePopup() {
        for type in [DropType.text, .image, .mixed] {
            #expect(CaptureConfirmation.route(mode: .modal, draftType: type) == .popup)
        }
    }

    // P-11
    @Test func instantSavesTextWithoutAPopup() {
        #expect(CaptureConfirmation.route(mode: .instant, draftType: .text) == .saveNow)
    }

    // P-12
    @Test func instantStillOpensThePopupForImagesAndMixedContent() {
        #expect(CaptureConfirmation.route(mode: .instant, draftType: .image) == .popup)
        #expect(CaptureConfirmation.route(mode: .instant, draftType: .mixed) == .popup)
    }
}
