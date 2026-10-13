import Foundation
import PlopcutCore

/// Shared by every capture trigger so only one capture runs at a time: the selected-text fallback borrows the
/// clipboard, and a clipboard capture in that window would read the borrowed content.
@MainActor
final class CaptureGate {
    private(set) var isBusy = false

    func enter() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    func leave() { isBusy = false }
}

/// Runs one capture per trigger and routes the result: a draft opens the popup, a failure is kept for the main
/// window (spec 3.3, checklist P-13). A trigger that arrives while a capture is running is dropped.
@MainActor
final class CaptureCoordinator {
    private let capture: () async throws -> CaptureDraft
    private let present: (CaptureDraft) async -> Void
    private let failed: (PlopcutError) -> Void
    private let gate: CaptureGate

    init(
        capture: @escaping () async throws -> CaptureDraft, present: @escaping (CaptureDraft) async -> Void,
        failed: @escaping (PlopcutError) -> Void, gate: CaptureGate = CaptureGate()
    ) {
        self.gate = gate
        self.capture = capture
        self.present = present
        self.failed = failed
    }

    func trigger() async {
        guard gate.enter() else { return }
        defer { gate.leave() }
        do {
            // The gate stays closed until the draft is routed, so an instant save is not overlapped by a new capture.
            await present(try await capture())
        } catch let error as PlopcutError {
            failed(error)
        } catch {
            failed(PlopcutError("capture_failed", detail: error.localizedDescription))
        }
    }
}
