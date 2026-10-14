import SwiftUI
import Testing
@testable import Plopcut

@Suite struct InspectorOverlayMotionTests {
    @Test func slidesWithStandardAnimationByDefault() {
        #expect(InspectorOverlayMotion.animation(reduceMotion: false) == .default)
        #expect(InspectorOverlayMotion.slides(reduceMotion: false))
    }

    @Test func reduceMotionShowsFinalStateAtOnce() {
        #expect(InspectorOverlayMotion.animation(reduceMotion: true) == nil)
        #expect(!InspectorOverlayMotion.slides(reduceMotion: true))
    }
}
