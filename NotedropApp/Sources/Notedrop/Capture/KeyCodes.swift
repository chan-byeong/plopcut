import Carbon.HIToolbox
import NotedropCore

/// Maps a parsed `Shortcut` to what `RegisterEventHotKey` wants. ANSI layout key codes.
enum KeyCodes {
    static func carbon(for shortcut: Shortcut) -> (keyCode: UInt32, modifiers: UInt32)? {
        guard let code = keyCode(for: shortcut.key) else { return nil }
        var modifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if shortcut.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        return (code, modifiers)
    }

    static func keyCode(for key: String) -> UInt32? { table[key] }

    /// The key name for a pressed key, read the same way registration maps it back, so a recorded shortcut fires on
    /// the key that was pressed whatever the keyboard layout or input source (Korean input included).
    static func key(forKeyCode code: UInt16) -> String? { names[UInt32(code)] }

    private static let names: [UInt32: String] = Dictionary(uniqueKeysWithValues: table.map { ($1, $0) })

    private static let table: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13,
        "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45,
        "M": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "Enter": 36, "Tab": 48, "Space": 49, "Backspace": 51, "Escape": 53, "Delete": 117,
        "Left": 123, "Right": 124, "Down": 125, "Up": 126,
        "Home": 115, "End": 119, "PageUp": 116, "PageDown": 121,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100, "F9": 101, "F10": 109,
        "F11": 103, "F12": 111, "F13": 105, "F14": 107, "F15": 113, "F16": 106, "F17": 64, "F18": 79, "F19": 80,
        "F20": 90,
    ]
}
