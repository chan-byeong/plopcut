import Testing
@testable import Plopcut

@Suite struct CompositionGuardTests {
    private let r = CompositionGuard.returnKey

    @Test func hangulIsRecognizedAtTheEndOfTheText() {
        #expect(CompositionGuard.endsWithHangul("가"))
        #expect(CompositionGuard.endsWithHangul("tag ㄱ"))
        #expect(CompositionGuard.endsWithHangul("ab한"))
        #expect(!CompositionGuard.endsWithHangul("한a"))
        #expect(!CompositionGuard.endsWithHangul(""))
    }

    // I-01: typing Hangul letters and pressing Return only commits the syllable.
    @Test func returnRightAfterTypingHangulIsIgnoredOnce() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: 15, endsWithHangul: true, at: 10)   // ㄱ
        guardian.keyDown(keyCode: 40, endsWithHangul: true, at: 10.1) // ㅏ
        guardian.keyDown(keyCode: r, endsWithHangul: true, at: 10.5)
        #expect(guardian.shouldIgnoreRegistration(at: 10.55))
        guardian.keyDown(keyCode: r, endsWithHangul: true, at: 11)    // second Return registers
        #expect(!guardian.shouldIgnoreRegistration(at: 11.05))
    }

    @Test func commaCommitsLikeReturn() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: 15, endsWithHangul: true, at: 10)
        guardian.keyDown(keyCode: CompositionGuard.commaKey, endsWithHangul: true, at: 10.2)
        #expect(guardian.shouldIgnoreRegistration(at: 10.25))
    }

    @Test func returnWithoutTypingSinceTheLastCommitRegisters() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: r, endsWithHangul: true, at: 10)    // nothing typed yet, text ends in Hangul from before
        #expect(!guardian.shouldIgnoreRegistration(at: 10.05))
    }

    @Test func latinTextIsNeverTreatedAsComposing() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: 0, endsWithHangul: false, at: 10)
        guardian.keyDown(keyCode: r, endsWithHangul: false, at: 10.2)
        #expect(!guardian.shouldIgnoreRegistration(at: 10.25))
    }

    @Test func spaceAndFocusResetTheComposition() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: 15, endsWithHangul: true, at: 10)
        guardian.keyDown(keyCode: 49, endsWithHangul: true, at: 10.1) // space commits
        guardian.keyDown(keyCode: r, endsWithHangul: true, at: 10.3)
        #expect(!guardian.shouldIgnoreRegistration(at: 10.35))
        guardian.keyDown(keyCode: 15, endsWithHangul: true, at: 11)
        guardian.reset()
        guardian.keyDown(keyCode: r, endsWithHangul: true, at: 11.2)
        #expect(!guardian.shouldIgnoreRegistration(at: 11.25))
    }

    @Test func markedTextAlsoCounts() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: r, endsWithHangul: false, markedText: true, at: 10)
        #expect(guardian.shouldIgnoreRegistration(at: 10.05))
    }

    @Test func aStaleFlagDoesNotBlockTheAddButton() {
        var guardian = CompositionGuard()
        guardian.keyDown(keyCode: 15, endsWithHangul: true, at: 10)
        guardian.keyDown(keyCode: r, endsWithHangul: true, at: 10.2)
        #expect(!guardian.shouldIgnoreRegistration(at: 12), "a click long after the key must still register")
    }
}
