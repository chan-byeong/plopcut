import AppKit
import Carbon.HIToolbox
import Testing
@testable import Plopcut

/// What the Settings key monitor does with each event (STA-69): swallow it or not, and what it tells the model.
@Suite struct RecorderKeyRouterTests {
    private let q = UInt16(kVK_ANSI_Q)
    private let k = UInt16(kVK_ANSI_K)
    private let pass = RecorderKeyRouter.Effect(swallow: false, command: nil)
    private let swallow = RecorderKeyRouter.Effect(swallow: true, command: nil)

    private func down(_ code: UInt16, repeat isRepeat: Bool = false, _ flags: NSEvent.ModifierFlags = [.command])
        -> RecorderKeyRouter.Input {
        .keyDown(keyCode: code, isRepeat: isRepeat, modifiers: flags)
    }

    @Test func keysPassThroughWhenNotRecording() {
        var router = RecorderKeyRouter()
        #expect(router.route(down(q), isRecording: false) == pass)
        #expect(router.route(down(q, repeat: true), isRecording: false) == pass)
        #expect(router.route(.flagsChanged([.command]), isRecording: false) == pass)
        #expect(router.route(.mouseDown, isRecording: false) == pass)
        #expect(router.route(.focusLost, isRecording: false) == pass)
    }

    @Test func aKeyPressedWhileRecordingIsSwallowedAndInterpreted() {
        var router = RecorderKeyRouter()
        let effect = router.route(down(k, [.shift, .command]), isRecording: true)
        #expect(effect == .init(swallow: true, command: .handle(.recorded("Shift+Cmd+K"))))
        #expect(router.heldKey == k)
    }

    /// A held Cmd+Q must not quit the app once the recording that took it has ended.
    @Test func theRecordedKeysAutoRepeatIsSwallowedUntilItIsReleased() {
        var router = RecorderKeyRouter()
        _ = router.route(down(q), isRecording: true)
        #expect(router.route(down(q, repeat: true), isRecording: false) == swallow)
        #expect(router.route(.keyUp(keyCode: q), isRecording: false) == pass)
        #expect(router.heldKey == nil)
        #expect(router.route(down(q, repeat: true), isRecording: false) == pass)
    }

    /// Repeats while recording are dropped without reaching the model, so a refused key does not flash its error.
    @Test func autoRepeatWhileRecordingIsSwallowedWithoutInterpreting() {
        var router = RecorderKeyRouter()
        #expect(router.route(down(k, []), isRecording: true).command == .handle(.rejected(.needsModifier)))
        #expect(router.route(down(k, repeat: true, []), isRecording: true) == swallow)
    }

    /// If the key-up was lost (focus moved while holding), the next fresh press starts clean.
    @Test func aLostKeyUpIsForgottenOnTheNextPress() {
        var router = RecorderKeyRouter()
        _ = router.route(down(q), isRecording: true)
        #expect(router.route(down(q), isRecording: false) == pass)
        #expect(router.heldKey == nil)
        #expect(router.route(down(q, repeat: true), isRecording: false) == pass)
    }

    @Test func modifierChangesForgetTheHeldKeyAndPreviewOnlyWhileRecording() {
        var router = RecorderKeyRouter()
        _ = router.route(down(q), isRecording: true)
        #expect(router.route(.flagsChanged([]), isRecording: false) == pass)
        #expect(router.heldKey == nil)
        #expect(router.route(.flagsChanged([.shift, .command]), isRecording: true)
            == .init(swallow: false, command: .preview("Shift+Cmd+")))
    }

    /// Review HIGH: focus moving to another window (or app) while recording must end the recording, or every key
    /// press in the app would keep being swallowed.
    @Test func losingFocusOrClickingEndsTheRecordingAndForgetsTheHeldKey() {
        for input in [RecorderKeyRouter.Input.focusLost, .mouseDown] {
            var router = RecorderKeyRouter()
            _ = router.route(down(k, []), isRecording: true)  // refused, still recording
            #expect(router.route(input, isRecording: true) == .init(swallow: false, command: .cancelRecording))
            _ = router.route(down(q), isRecording: true)
            _ = router.route(input, isRecording: false)
            #expect(router.heldKey == nil)
        }
    }

    @Test func startingANewRecordingForgetsTheHeldKey() {
        var router = RecorderKeyRouter()
        _ = router.route(down(q), isRecording: true)
        _ = router.route(.keyUp(keyCode: k), isRecording: false)
        #expect(router.heldKey == q)
        #expect(router.route(down(q, repeat: true), isRecording: true) == swallow)
        #expect(router.heldKey == nil)
    }

    @Test func escapeWhileRecordingCancelsAndIsSwallowed() {
        var router = RecorderKeyRouter()
        let effect = router.route(down(UInt16(kVK_Escape), []), isRecording: true)
        #expect(effect == .init(swallow: true, command: .handle(.cancelled)))
        #expect(router.heldKey == nil)
    }
}
