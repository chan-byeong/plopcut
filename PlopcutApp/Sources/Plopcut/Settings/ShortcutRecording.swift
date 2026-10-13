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


/// Decides what the Settings key monitor does with each event (STA-69). Pure, so focus and auto-repeat rules are
/// unit tested; `ShortcutKeyMonitor` only translates `NSEvent`s and applies the effect.
struct RecorderKeyRouter {
    enum Input: Equatable {
        case keyDown(keyCode: UInt16, isRepeat: Bool, modifiers: NSEvent.ModifierFlags)
        case keyUp(keyCode: UInt16)
        case flagsChanged(NSEvent.ModifierFlags)
        case mouseDown
        /// The window or the app lost keyboard focus (another window, Cmd+`, app switch).
        case focusLost
    }

    enum Command: Equatable {
        case handle(ShortcutRecording.Outcome)
        case preview(String?)
        case cancelRecording
    }

    struct Effect: Equatable {
        var swallow: Bool
        var command: Command?
    }

    /// The key that ended a recording and is still held. Its auto-repeat must not reach the menu after the recording
    /// ends: a held Cmd+Q would quit the app.
    private(set) var heldKey: UInt16?
    private var wasRecording = false

    mutating func route(_ input: Input, isRecording: Bool) -> Effect {
        if isRecording, !wasRecording { heldKey = nil }  // a new recording starts clean
        wasRecording = isRecording
        switch input {
        case let .keyDown(code, isRepeat, flags):
            if isRepeat {
                // While recording, a repeat never reaches the model, so a refused key does not flash its error.
                return Effect(swallow: isRecording || code == heldKey, command: nil)
            }
            heldKey = nil  // a fresh press: a key-up lost earlier no longer matters
            guard isRecording else { return Effect(swallow: false, command: nil) }
            let outcome = ShortcutRecording.interpret(keyCode: code, modifiers: flags)
            if case .recorded = outcome { heldKey = code }
            return Effect(swallow: true, command: .handle(outcome))
        case .keyUp(let code):
            if code == heldKey { heldKey = nil }
            return Effect(swallow: false, command: nil)
        case .flagsChanged(let flags):
            heldKey = nil
            return Effect(swallow: false, command: isRecording ? .preview(ShortcutRecording.preview(modifiers: flags)) : nil)
        case .mouseDown, .focusLost:
            // The click itself still goes through (Save, Cancel, the field).
            heldKey = nil
            return Effect(swallow: false, command: isRecording ? .cancelRecording : nil)
        }
    }
}

/// While the recorder listens, takes every key press before menus and buttons see it (Cmd+Q, Cmd+W, Space on the
/// focused button) and hands it to the model. Installed only while the shortcut section is on screen.
@MainActor
final class ShortcutKeyMonitor {
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var router = RecorderKeyRouter()

    func install(_ model: ShortcutModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown]) {
            [weak self, weak model] event in
            let input: RecorderKeyRouter.Input = switch event.type {
            case .keyDown: .keyDown(keyCode: event.keyCode, isRepeat: event.isARepeat, modifiers: event.modifierFlags)
            case .keyUp: .keyUp(keyCode: event.keyCode)
            case .flagsChanged: .flagsChanged(event.modifierFlags)
            default: .mouseDown
            }
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, let model else { return false }
                return self.apply(input, to: model)
            }
            return swallow ? nil : event
        }
        // Only the key window receives key presses, so any window giving up key status (another plopcut window,
        // Cmd+`, a popup) or the app deactivating ends the recording. Otherwise keys elsewhere would keep being eaten.
        let center = NotificationCenter.default
        observers = [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak model] _ in
                MainActor.assumeIsolated {
                    guard let self, let model else { return }
                    _ = self.apply(.focusLost, to: model)
                }
            }
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
        monitor = nil
        observers = []
        router = RecorderKeyRouter()
    }

    /// Returns true when the event is consumed.
    private func apply(_ input: RecorderKeyRouter.Input, to model: ShortcutModel) -> Bool {
        let effect = router.route(input, isRecording: model.isRecording)
        switch effect.command {
        case .handle(let outcome): model.handle(outcome)
        case .preview(let text): model.modifiersChanged(text)
        case .cancelRecording: model.cancelRecording()
        case nil: break
        }
        return effect.swallow
    }

    isolated deinit { remove() }
}
