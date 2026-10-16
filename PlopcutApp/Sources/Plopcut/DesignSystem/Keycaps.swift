import PlopcutCore
import SwiftUI

/// A shortcut drawn as key caps (`⇧` `⌘` `C`) for the empty Library (spec 2.5). VoiceOver reads the whole shortcut
/// once instead of each cap (checklist U-05).
struct Keycaps: View {
    /// The stored form, such as `Shift+Cmd+C`.
    let shortcut: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(Self.caps(shortcut).enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.body.weight(.medium)).monospaced()
                    .frame(minWidth: 28, minHeight: 28)
                    .padding(.horizontal, Spacing.xs)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).stroke(.separator, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(shortcut))
    }

    /// Modifier symbols in the macOS order (⌃ ⌥ ⇧ ⌘), then the key. An unreadable value is shown as written.
    nonisolated static func caps(_ shortcut: String) -> [String] {
        guard let parsed = try? Shortcut.parse(shortcut) else { return [shortcut] }
        let modifiers: [(Shortcut.Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return modifiers.filter { parsed.modifiers.contains($0.0) }.map(\.1) + [keySymbols[parsed.key] ?? parsed.key]
    }

    /// The accessibility name: the stored form with spaces, such as `Shift Cmd C`.
    nonisolated static func spoken(_ shortcut: String) -> String {
        shortcut.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    nonisolated private static let keySymbols: [String: String] = [
        "Enter": "↩", "Tab": "⇥", "Escape": "⎋", "Backspace": "⌫", "Delete": "⌦", "Space": "Space",
        "Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Home": "↖", "End": "↘", "PageUp": "⇞", "PageDown": "⇟",
    ]
}
