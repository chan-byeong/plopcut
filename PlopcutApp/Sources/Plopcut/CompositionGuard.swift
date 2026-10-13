import AppKit

/// Tells tag registration to skip the Return or comma that only committed an input-method composition (spec I-01).
///
/// A Korean input method keeps the last syllable "in composition" until a commit key arrives, but in AppKit text
/// fields it inserts that syllable directly, so `hasMarkedText` is false. It also passes the Return on after
/// committing, so by the time `onSubmit` runs there is nothing left to inspect. The guard therefore follows the
/// keys: letters typed since the last commit key while the field ends in Hangul mean a composition is open, and
/// the first Return or comma then only closes it, like `isComposing` on the web.
struct CompositionGuard {
    static let returnKey: UInt16 = 36
    static let keypadEnterKey: UInt16 = 76
    static let commaKey: UInt16 = 43
    private static let registerKeys: Set<UInt16> = [returnKey, keypadEnterKey, commaKey]
    /// Return, Enter, comma, Space, Tab, Escape and the arrows all end a composition.
    private static let commitKeys: Set<UInt16> = registerKeys.union([49, 48, 53, 123, 124, 125, 126])
    /// The key and the registration it triggers arrive in the same event; anything later is a click.
    static let window: TimeInterval = 0.5

    private var typedSinceCommit = 0
    private var armedAt: TimeInterval?

    mutating func keyDown(keyCode: UInt16, endsWithHangul: Bool, markedText: Bool = false, at time: TimeInterval) {
        if Self.registerKeys.contains(keyCode) {
            armedAt = (markedText || (endsWithHangul && typedSinceCommit > 0)) ? time : nil
        } else {
            armedAt = nil
        }
        typedSinceCommit = Self.commitKeys.contains(keyCode) ? 0 : typedSinceCommit + 1
    }

    /// A new field focus or a click starts a fresh composition state.
    mutating func reset() {
        typedSinceCommit = 0
        armedAt = nil
    }

    func shouldIgnoreRegistration(at time: TimeInterval) -> Bool {
        guard let armedAt else { return false }
        return time - armedAt < Self.window
    }

    /// Hangul syllables and jamo, including the compatibility block the IME uses while a syllable is open.
    static func endsWithHangul(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last?.value else { return false }
        return (0xAC00...0xD7A3).contains(scalar) || (0x1100...0x11FF).contains(scalar)
            || (0x3130...0x318F).contains(scalar) || (0xA960...0xA97F).contains(scalar) || (0xD7B0...0xD7FF).contains(scalar)
    }
}

/// Watches key-down events for the whole app and feeds `CompositionGuard`.
@MainActor
final class CompositionMonitor {
    static let shared = CompositionMonitor()
    private var guardian = CompositionGuard()
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Shortcuts such as Cmd+A are not typing.
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return event }
            let editor = event.window?.firstResponder as? NSTextView
            let hangul = CompositionGuard.endsWithHangul(editor?.string ?? "")
            let marked = editor?.hasMarkedText() == true
            let (code, time) = (event.keyCode, event.timestamp)
            MainActor.assumeIsolated { self?.guardian.keyDown(keyCode: code, endsWithHangul: hangul, markedText: marked, at: time) }
            return event
        }
    }

    func reset() { guardian.reset() }

    var shouldIgnoreRegistration: Bool { guardian.shouldIgnoreRegistration(at: ProcessInfo.processInfo.systemUptime) }
}
