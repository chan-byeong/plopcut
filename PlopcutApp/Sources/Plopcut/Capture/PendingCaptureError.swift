import PlopcutCore

/// Keeps the last capture failure until the main window can show it. Reading it clears it (checklist P-13).
@MainActor
final class PendingCaptureError {
    private var error: PlopcutError?

    func store(_ error: PlopcutError) { self.error = error }

    func take() -> PlopcutError? {
        defer { error = nil }
        return error
    }
}
