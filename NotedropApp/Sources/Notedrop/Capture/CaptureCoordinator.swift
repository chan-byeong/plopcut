import Foundation
import NotedropCore

/// Runs one capture per trigger and routes the result: a draft opens the popup, a failure is kept for the main
/// window (spec 3.3, checklist P-13). A trigger that arrives while a capture is running is dropped.
@MainActor
final class CaptureCoordinator {
    private let capture: () async throws -> CaptureDraft
    private let present: (CaptureDraft) -> Void
    private let failed: (NotedropError) -> Void
    private var isRunning = false

    init(
        capture: @escaping () async throws -> CaptureDraft, present: @escaping (CaptureDraft) -> Void,
        failed: @escaping (NotedropError) -> Void
    ) {
        self.capture = capture
        self.present = present
        self.failed = failed
    }

    func trigger() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            present(try await capture())
        } catch let error as NotedropError {
            failed(error)
        } catch {
            failed(NotedropError("capture_failed", detail: error.localizedDescription))
        }
    }
}
