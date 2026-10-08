import Testing
@testable import NotedropCore

@MainActor
private final class FakeRegistrar: ShortcutRegistrar {
    final class Registration: ShortcutRegistration {
        let shortcut: Shortcut
        private let log: Log
        init(_ shortcut: Shortcut, _ log: Log) { self.shortcut = shortcut; self.log = log }
        func unregister() { log.events.append("unregister \(shortcut.key)") }
    }
    final class Log { var events: [String] = [] }

    let log = Log()
    var failing: Set<String> = []  // keys whose registration fails (a conflict with another app)
    var failingOnce: Set<String> = []

    func register(_ shortcut: Shortcut) throws -> any ShortcutRegistration {
        if failing.contains(shortcut.key) || failingOnce.remove(shortcut.key) != nil {
            log.events.append("fail \(shortcut.key)")
            throw NotedropError("shortcut_registration_failed")
        }
        log.events.append("register \(shortcut.key)")
        return Registration(shortcut, log)
    }
}

@MainActor
@Suite struct ShortcutControllerTests {
    private func started(_ registrar: FakeRegistrar, _ text: String = "Shift+Cmd+C") throws -> ShortcutController {
        let controller = ShortcutController(registrar: registrar)
        try controller.start(text)
        return controller
    }

    // C-09
    @Test func startupRegistersOnlyTheStoredShortcut() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        #expect(registrar.log.events == ["register C"])
        #expect(controller.current == (try Shortcut.parse("Shift+Cmd+C")))
    }

    @Test func startupRegistrationFailureIsThrownAndNothingIsRegistered() {
        let registrar = FakeRegistrar()
        registrar.failing = ["C"]
        let controller = ShortcutController(registrar: registrar)
        #expect(throws: NotedropError.self) { try controller.start("Shift+Cmd+C") }
        #expect(controller.current == nil)
    }

    // C-08: register new, release old, then save
    @Test func changeRegistersTheNewShortcutBeforeReleasingTheOldOneAndSavingLast() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        try controller.change(to: "Shift+Cmd+K") { _ in registrar.log.events.append("save") }
        #expect(registrar.log.events == ["register C", "register K", "unregister C", "save"])
        #expect(controller.current == (try Shortcut.parse("Shift+Cmd+K")))
    }

    @Test func failedRegistrationKeepsTheOldShortcutAndNeverSaves() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        registrar.failing = ["K"]
        var saved = false
        #expect(throws: NotedropError.self) { try controller.change(to: "Shift+Cmd+K") { _ in saved = true } }
        #expect(!saved)
        #expect(controller.current == (try Shortcut.parse("Shift+Cmd+C")))
        #expect(registrar.log.events == ["register C", "fail K"])
    }

    @Test func persistenceFailureRestoresThePreviousShortcut() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        #expect(throws: NotedropError.self) {
            try controller.change(to: "Shift+Cmd+K") { _ in throw NotedropError("settings_unwritable") }
        }
        #expect(controller.current == (try Shortcut.parse("Shift+Cmd+C")))
        #expect(registrar.log.events == ["register C", "register K", "unregister C", "unregister K", "register C"])
    }

    @Test func persistenceFailureWithAFailedRestoreReportsTheRollbackFailure() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        do {
            try controller.change(to: "Shift+Cmd+K") { _ in
                registrar.failing = ["C"]  // someone else took the old shortcut in the meantime
                throw NotedropError("settings_unwritable")
            }
            Issue.record("expected shortcut_rollback_failed")
        } catch let error as NotedropError {
            #expect(error.code == "shortcut_rollback_failed")
        } catch { Issue.record("unexpected \(error)") }
        #expect(controller.current == nil)
    }

    @Test func persistenceFailureAfterAFailedStartupLeavesNothingRegistered() throws {
        let registrar = FakeRegistrar()
        registrar.failing = ["C"]
        let controller = ShortcutController(registrar: registrar)
        #expect(throws: NotedropError.self) { try controller.start("Shift+Cmd+C") }
        #expect(throws: NotedropError.self) {
            try controller.change(to: "Shift+Cmd+K") { _ in throw NotedropError("settings_unwritable") }
        }
        #expect(controller.current == nil)
        #expect(registrar.log.events.last == "unregister K")
    }

    // C-06
    @Test func invalidFormatIsRejectedWithoutTouchingRegistrationOrStorage() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        var saved = false
        do {
            try controller.change(to: "Banana") { _ in saved = true }
            Issue.record("expected invalid_selected_text_shortcut")
        } catch let error as NotedropError {
            #expect(error.code == "invalid_selected_text_shortcut")
        } catch { Issue.record("unexpected \(error)") }
        #expect(!saved)
        #expect(registrar.log.events == ["register C"])
    }

    @Test func choosingTheCurrentShortcutOnlySaves() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        var savedText: String?
        try controller.change(to: " shift+cmd+c ") { savedText = $0 }
        #expect(savedText == " shift+cmd+c ")
        #expect(registrar.log.events == ["register C"])
    }

    @Test func savingPassesTheTextAsTyped() throws {
        let registrar = FakeRegistrar()
        let controller = try started(registrar)
        var savedText: String?
        try controller.change(to: "Cmd+Shift+K") { savedText = $0 }
        #expect(savedText == "Cmd+Shift+K")
    }
}
