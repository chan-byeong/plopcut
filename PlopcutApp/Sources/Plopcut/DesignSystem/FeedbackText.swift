import SwiftUI

/// Inline feedback text (design-system.md, "피드백"). Picking a kind picks the size, the color and how VoiceOver hears
/// it, so the same situation looks the same on every screen.
struct FeedbackText: View {
    enum Kind {
        /// One field's input is wrong; shown right under the field.
        case fieldError
        /// Work went ahead but the user should know (a duplicate tag, a clipboard that could not be restored).
        case warning
        /// A form or section action failed (Save Popup, Settings).
        case error
    }

    let text: String
    let kind: Kind

    init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        Text(text)
            .font(kind == .error ? .callout : .caption)
            .foregroundStyle(kind == .warning ? Color.orange : Color.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(kind == .warning ? [] : .updatesFrequently)
    }
}
