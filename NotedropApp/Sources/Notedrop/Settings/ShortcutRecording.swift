import AppKit
import Carbon.HIToolbox

/// Turns a key press in the Settings recorder into the stored shortcut text (STA-69, checklist C-06, D-03).
/// Pure: the event monitor below only feeds it key codes and modifier flags.
enum ShortcutRecording {
    enum Outcome: Equatable {
        case recorded(String)
        case cancelled
        case rejected(Rejection)
    }

    enum Rejection: Equatable {
        case needsModifier
        case unsupportedKey

        var messageKey: String {
            switch self {
            case .needsModifier: "shortcutNeedsModifier"
            case .unsupportedKey: "shortcutUnsupportedKey"
            }
        }
    }

    /// Escape on its own cancels; a key outside D-03 or a key without a modifier is refused. F21-F24 have no key on
    /// a Mac keyboard, so they can only come from a hand-edited settings file, where `KeyCodes` refuses them.
    static func interpret(keyCode: UInt16, modifiers flags: NSEvent.ModifierFlags) -> Outcome {
        let names = modifierNames(flags)
        if keyCode == UInt16(kVK_Escape), names.isEmpty { return .cancelled }
        guard let key = KeyCodes.key(forKeyCode: keyCode) else { return .rejected(.unsupportedKey) }
        guard !names.isEmpty else { return .rejected(.needsModifier) }
        return .recorded((names + [key]).joined(separator: "+"))
    }

    /// The modifiers held so far, such as `Shift+Cmd+`, or nil when none is held.
    static func preview(modifiers flags: NSEvent.ModifierFlags) -> String? {
        let names = modifierNames(flags)
        return names.isEmpty ? nil : names.joined(separator: "+") + "+"
    }

    /// macOS order (Control, Option, Shift, Command), spelled the way `Shortcut.parse` and the legacy app read them.
    private static func modifierNames(_ flags: NSEvent.ModifierFlags) -> [String] {
        let order: [(NSEvent.ModifierFlags, String)] = [
            (.control, "Ctrl"), (.option, "Option"), (.shift, "Shift"), (.command, "Cmd"),
        ]
        return order.filter { flags.contains($0.0) }.map(\.1)
    }
}

/// While the recorder listens, takes every key press before menus and buttons see it (Cmd+Q, Cmd+W, Space on the
/// focused button) and hands it to the model. Installed only while the shortcut section is on screen.
@MainActor
final class ShortcutKeyMonitor {
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// The key that ended a recording. Its auto-repeat must not reach the menu: a held Cmd+Q would quit the app.
    private var heldKey: UInt16?

    func install(_ model: ShortcutModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown]) {
            [weak self, weak model] event in
            let type = event.type
            let isKey = type == .keyDown || type == .keyUp
            let code = isKey ? event.keyCode : 0
            let isRepeat = type == .keyDown && event.isARepeat
            let flags = event.modifierFlags
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, let model else { return false }
                return self.handle(type, code: code, isRepeat: isRepeat, flags: flags, model: model)
            }
            return swallow ? nil : event
        }
        // Switching to another app ends the recording; key presses there never reach this monitor anyway.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.cancelRecording() }
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        heldKey = nil
    }

    /// Returns true when the event is consumed.
    private func handle(
        _ type: NSEvent.EventType, code: UInt16, isRepeat: Bool, flags: NSEvent.ModifierFlags, model: ShortcutModel
    ) -> Bool {
        switch type {
        case .keyUp:
            if code == heldKey { heldKey = nil }
            return false
        case .keyDown:
            if isRepeat, code == heldKey { return true }
            guard model.isRecording else { return false }
            let outcome = ShortcutRecording.interpret(keyCode: code, modifiers: flags)
            if case .recorded = outcome { heldKey = code }
            model.handle(outcome)
            return true
        case .flagsChanged:
            model.modifiersChanged(ShortcutRecording.preview(modifiers: flags))
            return false
        default:
            // A click anywhere ends the recording; the click itself still goes through (Save, Cancel, the field).
            model.cancelRecording()
            return false
        }
    }

    isolated deinit { remove() }
}
