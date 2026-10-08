import Carbon.HIToolbox
import NotedropCore
import Testing
@testable import Notedrop

@Suite struct KeyCodesTests {
    @Test func defaultShortcutMapsToCommandShiftC() throws {
        let carbon = try #require(KeyCodes.carbon(for: Shortcut.parse("Shift+Cmd+C")))
        #expect(carbon.keyCode == 8)
        #expect(carbon.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func allModifiersAreMapped() throws {
        let carbon = try #require(KeyCodes.carbon(for: Shortcut.parse("Ctrl+Alt+Shift+Cmd+F5")))
        #expect(carbon.keyCode == 96)
        #expect(carbon.modifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey))
    }

    /// `Shortcut.parse` accepts F1-F24, but F21-F24 have no key code here, so they must be rejected, not misfired.
    @Test func functionKeysBeyondF20AreRejected() throws {
        let shortcut = try Shortcut.parse("Cmd+F21")
        #expect(KeyCodes.carbon(for: shortcut) == nil)
    }
}
