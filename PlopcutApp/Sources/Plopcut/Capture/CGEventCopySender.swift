import AppKit
import ApplicationServices
import PlopcutCore

/// Sends Cmd+C to the frontmost app. Needs the Accessibility permission.
struct CGEventCopySender: CopyShortcutSender {
    private static let cKeyCode: CGKeyCode = 8

    /// The capture shortcut is still physically held when it fires. Wait for its keys to come up, so the target app
    /// sees a clean Cmd+C and not Shift+Cmd+C, but never longer than this.
    static let releaseTimeout: TimeInterval = 0.4
    private static let heldModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl]

    func sendCopy() throws {
        guard AXIsProcessTrusted() else { throw PlopcutError("automation_unavailable") }
        Self.waitForKeysUp()
        // A private-state source ignores the keys still physically held (the capture shortcut's Shift), so the app
        // receives a plain Cmd+C.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.cKeyCode, keyDown: false)
        else { throw PlopcutError("automation_failed") }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func waitForKeysUp() {
        let deadline = Date().addingTimeInterval(releaseTimeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let cDown = CGEventSource.keyState(.combinedSessionState, key: cKeyCode)
            if flags.intersection(heldModifiers).isEmpty && !cDown { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
