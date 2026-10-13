import Foundation
import PlopcutCore

/// Decides what a fresh draft does: open the Save Popup, or in `instant` mode save the text right away
/// (spec 3.3, checklist P-11, P-12). The mode is read for every draft, so a change in Settings applies at once.
@MainActor
struct CaptureRouter {
    let mode: () -> CaptureConfirmationMode
    let save: @Sendable (SaveRequest) async throws -> Drop
    let showPopup: (CaptureDraft) -> Void
    let saved: (Drop) -> Void
    let failed: (PlopcutError) -> Void

    func route(_ draft: CaptureDraft) async {
        switch CaptureConfirmation.route(mode: mode(), draftType: draft.type) {
        case .popup:
            showPopup(draft)
        case .saveNow:
            let request = SaveRequest(
                text: draft.text ?? "", title: draft.title, source: draft.source, note: "", tags: [], imagePNG: nil)
            do {
                saved(try await save(request))
            } catch let error as PlopcutError {
                failed(error)
            } catch {
                failed(PlopcutError("save_failed", detail: error.localizedDescription))
            }
        }
    }
}
