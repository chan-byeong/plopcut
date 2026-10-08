import NotedropCore
import Observation

/// The text field behind the selected-text shortcut setting. `apply` is the whole change (register, release, save);
/// when it throws, the field goes back to the shortcut that is still working.
@MainActor
@Observable
final class ShortcutModel {
    var text: String
    private(set) var errorMessage: String?
    private var working: String
    private let applyChange: (String) throws -> Void

    init(initial: String, apply: @escaping (String) throws -> Void) {
        text = initial
        working = initial
        applyChange = apply
    }

    func apply() {
        do {
            try applyChange(text)
            working = text
            errorMessage = nil
        } catch {
            errorMessage = ErrorText.message(for: error)
            text = working
        }
    }

    func revert() { text = working }
}
