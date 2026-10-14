import SwiftUI

extension View {
    /// The chip look: a small bordered button. Tags, filters and suggestions all use it.
    func chipStyle() -> some View {
        buttonStyle(.bordered).controlSize(.small)
    }
}

/// A chip that removes its value when pressed: tags in the inspector and the Save Popup, active filters.
/// VoiceOver reads the action and the value ("Remove tag #swift"), not the xmark.
struct RemovableChip: View {
    let text: String
    /// The localized action, such as "Remove tag".
    let removeLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(text, systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption)
        }
        .chipStyle()
        .accessibilityLabel("\(removeLabel) \(text)")
    }
}
