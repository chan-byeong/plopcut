import AppKit
import SwiftUI

/// When an input surface shows its field background and border.
enum InputChrome {
    /// Always looks like a field: the note, the popup note, the shortcut field.
    case always
    /// Reads as plain text until it is edited: the drop title.
    case whileFocused
}

/// The look of an input the app draws itself, for controls without a system bezel (design-system.md, "형태").
/// A text background, a 1 pt quiet border, and a 2 pt accent ring while focused. The ring is drawn on the edge, so it
/// never moves the layout. Insets stay with the caller, because text views bring their own.
private struct InputSurface: ViewModifier {
    let focused: Bool
    let chrome: InputChrome

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        let showsChrome = chrome == .always || focused
        content
            .background(showsChrome ? Color(nsColor: .textBackgroundColor) : .clear, in: shape)
            .overlay(shape.stroke(borderColor(showsChrome), lineWidth: focused ? 2 : 1))
    }

    private func borderColor(_ showsChrome: Bool) -> Color {
        if focused { return .accentColor }
        return showsChrome ? Color.secondary.opacity(0.3) : .clear
    }
}

extension View {
    func inputSurface(focused: Bool, chrome: InputChrome = .always) -> some View {
        modifier(InputSurface(focused: focused, chrome: chrome))
    }

    /// A recessed, read-only content well, such as the Save Popup preview.
    func contentWell() -> some View {
        background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
    }
}
