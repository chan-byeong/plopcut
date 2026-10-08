import AppKit
import ApplicationServices
import NotedropCore

/// Collects app name, window title and, for Chrome, the active tab URL. Best effort: every failure is a warning
/// and a missing field, never an error (spec 3.4, checklist M-01..M-04).
struct FrontmostSourceCollector: SourceCollector {
    static let chromeBundleID = "com.google.Chrome"

    func collect() async -> SourceResult {
        guard let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName else {
            return SourceResult(warnings: [CaptureWarning("metadata_failed")])
        }
        var source = DropSource(appName: name)
        var warnings: [CaptureWarning] = []

        source.windowTitle = Self.windowTitle(of: app)
        if app.bundleIdentifier == Self.chromeBundleID {
            if let url = await Self.chromeURL() {
                source.url = url
            } else {
                warnings.append(CaptureWarning("chrome_url_failed"))
            }
        }
        return SourceResult(source: source, warnings: warnings)
    }

    private static func windowTitle(of app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, AXSelectedTextReader.timeout)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String, !text.isEmpty
        else { return nil }
        return text
    }

    /// How long a capture waits for Chrome. The first run shows the Automation consent dialog and a hung Chrome can
    /// take minutes to answer; neither may block the capture or the app.
    static let chromeTimeout = Duration.seconds(1.5)

    /// The script runs on its own thread (one `NSAppleScript` per call) and is raced against a timeout. A script
    /// that outlives the timeout finishes on that thread and its result is dropped.
    private static func chromeURL() async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await runChromeScript() }
            group.addTask {
                try? await Task.sleep(for: chromeTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func runChromeScript() async -> String? {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let script = NSAppleScript(source: "tell application \"Google Chrome\" to return URL of active tab of front window")
                var error: NSDictionary?
                let result = script?.executeAndReturnError(&error)
                let url = error == nil ? result?.stringValue : nil
                continuation.resume(returning: url?.isEmpty == false ? url : nil)
            }
        }
    }
}
