import Foundation

/// One live global shortcut registration. Releasing it is the only thing callers need.
@MainActor
public protocol ShortcutRegistration: AnyObject {
    func unregister()
}

/// Registers a shortcut with the OS. Two registrations may be alive at once, which is what makes the
/// "register new, then release old" order (checklist C-08) possible.
@MainActor
public protocol ShortcutRegistrar {
    func register(_ shortcut: Shortcut) throws -> any ShortcutRegistration
}

/// Owns the single selected-text shortcut: registers it at startup (C-09) and swaps it safely (C-08).
/// A swap registers the new shortcut, releases the old one, then saves; any failure leaves the old one working.
@MainActor
public final class ShortcutController {
    private let registrar: any ShortcutRegistrar
    private var registration: (shortcut: Shortcut, handle: any ShortcutRegistration)?

    public init(registrar: any ShortcutRegistrar) {
        self.registrar = registrar
    }

    public var current: Shortcut? { registration?.shortcut }

    /// Registers the stored shortcut. Nothing else is registered.
    public func start(_ text: String) throws {
        let shortcut = try Shortcut.parse(text)
        registration = (shortcut, try registrar.register(shortcut))
    }

    /// `save` persists the text; if it throws, the previous shortcut is registered again and the error rethrown.
    public func change(to text: String, save: (String) throws -> Void) throws {
        let shortcut = try Shortcut.parse(text)
        guard let old = registration else {
            registration = (shortcut, try registrar.register(shortcut))
            try save(text)
            return
        }
        if old.shortcut == shortcut {
            try save(text)
            return
        }

        let fresh = try registrar.register(shortcut)
        old.handle.unregister()
        registration = (shortcut, fresh)
        do {
            try save(text)
        } catch {
            fresh.unregister()
            do {
                registration = (old.shortcut, try registrar.register(old.shortcut))
            } catch {
                registration = nil
                throw NotedropError("shortcut_rollback_failed", detail: "\(error)")
            }
            throw error
        }
    }
}
