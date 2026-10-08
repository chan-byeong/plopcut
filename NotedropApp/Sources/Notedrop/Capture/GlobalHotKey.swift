import Carbon.HIToolbox
import Foundation
import NotedropCore

/// One system-wide hot key (Carbon `RegisterEventHotKey`, which needs no extra permission).
/// Registration failure throws `shortcut_registration_failed` so the caller can keep it as a pending error.
@MainActor
final class GlobalHotKey {
    private static let signature: OSType = 0x4E_44_52_50  // 'NDRP'
    /// The C callback holds this box, not the hot key, so a hot key released while a press is queued is skipped.
    private final class Box {
        weak var hotKey: GlobalHotKey?
        init(_ hotKey: GlobalHotKey) { self.hotKey = hotKey }
    }

    private var box: Unmanaged<Box>?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func register(_ shortcut: Shortcut) throws {
        guard let carbon = KeyCodes.carbon(for: shortcut) else {
            throw NotedropError("invalid_selected_text_shortcut", detail: shortcut.key)
        }
        unregister()

        let retained = Unmanaged.passRetained(Box(self))
        box = retained
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let box = Unmanaged<Box>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { box.hotKey?.action() } }
                return noErr
            },
            1, &spec, retained.toOpaque(), &handlerRef)
        guard status == noErr else {
            unregister()  // releases the box once
            throw NotedropError("shortcut_registration_failed", detail: "\(status)")
        }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(carbon.keyCode, carbon.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            unregister()
            throw NotedropError("shortcut_registration_failed", detail: "\(registered)")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        box?.release()
        box = nil
    }

    isolated deinit { unregister() }
}
