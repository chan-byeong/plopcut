import Foundation

/// A global shortcut stored as a Tauri-style string such as `Shift+Cmd+C` (checklist C-06).
/// The key is kept symbolic; mapping it to a key code belongs to the OS layer.
public struct Shortcut: Equatable, Sendable {
    public enum Modifier: Hashable, Sendable { case shift, command, control, option }

    public let modifiers: Set<Modifier>
    public let key: String

    public static func parse(_ string: String) throws -> Shortcut {
        let invalid = NotedropError("invalid_selected_text_shortcut", detail: string)
        let tokens = string.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard tokens.count >= 2, tokens.allSatisfy({ !$0.isEmpty }) else { throw invalid }
        var modifiers = Set<Modifier>()
        for token in tokens.dropLast() {
            guard let modifier = modifierNames[token.lowercased()] else { throw invalid }
            modifiers.insert(modifier)
        }
        guard let key = canonicalKey(tokens[tokens.count - 1]) else { throw invalid }
        return Shortcut(modifiers: modifiers, key: key)
    }

    private static let modifierNames: [String: Modifier] = [
        "shift": .shift, "cmd": .command, "command": .command, "ctrl": .control, "control": .control,
        "alt": .option, "option": .option,
    ]

    private static let namedKeys: [String: String] = [
        "space": "Space", "enter": "Enter", "return": "Enter", "tab": "Tab", "escape": "Escape", "esc": "Escape",
        "backspace": "Backspace", "delete": "Delete", "up": "Up", "down": "Down", "left": "Left", "right": "Right",
        "home": "Home", "end": "End", "pageup": "PageUp", "pagedown": "PageDown",
    ]

    private static func canonicalKey(_ token: String) -> String? {
        let lower = token.lowercased()
        if lower.count == 1, let c = lower.first, c.isASCII, c.isLetter || c.isNumber { return lower.uppercased() }
        if lower.hasPrefix("f"), let n = Int(lower.dropFirst()), (1...24).contains(n) { return "F\(n)" }
        return namedKeys[lower]
    }
}
