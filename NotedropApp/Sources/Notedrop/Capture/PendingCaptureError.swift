import NotedropCore

/// Keeps the last capture failure until the main window can show it. Reading it clears it (checklist P-13).
@MainActor
final class PendingCaptureError {
    private var error: NotedropError?

    func store(_ error: NotedropError) { self.error = error }

    func take() -> NotedropError? {
        defer { error = nil }
        return error
    }
}
