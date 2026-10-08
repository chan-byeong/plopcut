import AppKit
import ApplicationServices
import NotedropCore

/// Reads the selection of the capture's target app through the accessibility API, without touching the clipboard.
///
/// It asks the frontmost app's own accessibility element for its focused element. The system-wide element is not
/// used: it failed for every app in the probe (docs/swift-migration/ax-probe.md).
struct AXSelectedTextReader: SelectedTextReader {
    /// Apps that never answer must not hold a capture; the clipboard fallback takes over after this.
    static let timeout: Float = 0.3

    func readSelection(in target: CaptureTarget?) -> String? {
        guard AXIsProcessTrusted(), let target,
              target.processID != ProcessInfo.processInfo.processIdentifier
        else { return nil }

        let appElement = AXUIElementCreateApplication(target.processID)
        AXUIElementSetMessagingTimeout(appElement, Self.timeout)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement  // type checked above

        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selection) == .success
        else { return nil }
        return selection as? String
    }
}
