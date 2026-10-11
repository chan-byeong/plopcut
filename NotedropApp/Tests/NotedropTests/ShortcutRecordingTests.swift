import AppKit
import Carbon.HIToolbox
import NotedropCore
import Testing
@testable import Notedrop

/// Key press -> shortcut text while the Settings recorder is listening (STA-69, checklist C-06, D-03).
@Suite struct ShortcutRecordingTests {
    private func record(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> ShortcutRecording.Outcome {
        ShortcutRecording.interpret(keyCode: UInt16(keyCode), modifiers: modifiers)
    }

    @Test func aLetterWithModifiersBecomesTheStoredFormat() {
        #expect(record(kVK_ANSI_K, [.shift, .command]) == .recorded("Shift+Cmd+K"))
    }

    /// Always the same order (Ctrl, Option, Shift, Cmd), whatever order the keys went down in.
    @Test func modifiersAreWrittenInAFixedOrder() {
        #expect(record(kVK_F5, [.command, .shift, .option, .control]) == .recorded("Ctrl+Option+Shift+Cmd+F5"))
    }

    /// Arrow and function keys carry `.function` / `.numericPad`; Caps Lock carries `.capsLock`. None of them count.
    @Test func flagsThatAreNotModifiersAreIgnored() {
        #expect(record(kVK_UpArrow, [.command, .function, .numericPad]) == .recorded("Cmd+Up"))
        #expect(record(kVK_ANSI_A, [.control, .capsLock]) == .recorded("Ctrl+A"))
    }

    @Test func everyAllowedKeyCanBeRecorded() {
        let keys: [(Int, String)] = [
            (kVK_ANSI_Z, "Z"), (kVK_ANSI_0, "0"), (kVK_ANSI_9, "9"), (kVK_F1, "F1"), (kVK_F20, "F20"),
            (kVK_LeftArrow, "Left"), (kVK_RightArrow, "Right"), (kVK_DownArrow, "Down"), (kVK_UpArrow, "Up"),
            (kVK_Space, "Space"), (kVK_Return, "Enter"), (kVK_Tab, "Tab"), (kVK_Escape, "Escape"),
            (kVK_Delete, "Backspace"), (kVK_ForwardDelete, "Delete"), (kVK_Home, "Home"), (kVK_End, "End"),
            (kVK_PageUp, "PageUp"), (kVK_PageDown, "PageDown"),
        ]
        for (code, name) in keys {
            #expect(record(code, [.option]) == .recorded("Option+\(name)"), "\(name)")
        }
    }

    /// What is recorded must be accepted by the parser and register the very key that was pressed.
    @Test func recordedTextRegistersThePressedKey() throws {
        for code in [kVK_ANSI_C, kVK_ANSI_5, kVK_F12, kVK_PageDown, kVK_ForwardDelete] {
            guard case .recorded(let text) = record(code, [.shift, .command]) else {
                Issue.record("not recorded: \(code)")
                continue
            }
            let carbon = try #require(KeyCodes.carbon(for: Shortcut.parse(text)))
            #expect(carbon.keyCode == UInt32(code), "\(text)")
            #expect(carbon.modifiers == UInt32(cmdKey | shiftKey), "\(text)")
        }
    }

    // A modifier on its own never ends recording: macOS reports it as flagsChanged, not keyDown, so the recorder
    // only previews it.
    @Test func heldModifiersArePreviewedButNotRecorded() {
        #expect(ShortcutRecording.preview(modifiers: [.command, .shift]) == "Shift+Cmd+")
        #expect(ShortcutRecording.preview(modifiers: [.function, .capsLock]) == nil)
        #expect(ShortcutRecording.preview(modifiers: []) == nil)
    }

    @Test func escapeOnItsOwnCancels() {
        #expect(record(kVK_Escape, []) == .cancelled)
        #expect(record(kVK_Escape, [.capsLock]) == .cancelled)
    }

    @Test func aKeyWithoutModifiersIsRejected() {
        for code in [kVK_ANSI_K, kVK_Return, kVK_Tab, kVK_Space, kVK_Delete, kVK_F5] {
            #expect(record(code, []) == .rejected(.needsModifier), "\(code)")
        }
        #expect(record(kVK_ANSI_K, [.function]) == .rejected(.needsModifier))
    }

    /// The reverse lookup must not lose a key to a shared key code.
    @Test func everyKeyNameHasItsOwnKeyCode() {
        let names = KeyCodes.allKeyNames
        let codes = names.compactMap { KeyCodes.keyCode(for: $0) }
        #expect(codes.count == names.count)
        #expect(Set(codes).count == names.count)
        for name in names {
            #expect(KeyCodes.key(forKeyCode: UInt16(KeyCodes.keyCode(for: name) ?? 0xFFFF)) == name, "\(name)")
        }
    }

    /// Keys outside D-03: punctuation, keypad keys (keypad Enter would otherwise register Return), Help, ISO extras.
    @Test func keysOutsideTheAllowedRangeAreRejected() {
        for code in [kVK_ANSI_Minus, kVK_ANSI_LeftBracket, kVK_ANSI_Grave, kVK_ANSI_Keypad1, kVK_ANSI_KeypadEnter,
                     kVK_Help, kVK_ISO_Section, kVK_JIS_Yen, 0xFF] {
            #expect(record(code, [.command]) == .rejected(.unsupportedKey), "\(code)")
            #expect(record(code, []) == .rejected(.unsupportedKey), "\(code)")
        }
    }
}
