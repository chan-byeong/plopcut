import PlopcutCore
import Testing
@testable import Plopcut

@Suite struct PaneWidthRecorderTests {
    @Test func firstObservationOnlyRecords() {
        var recorder = PaneWidthRecorder()
        #expect(recorder.observe(sidebar: 220, list: 330, window: 1300) == nil)
    }

    @Test func dividerDragAtSameWindowWidthSaves() {
        var recorder = PaneWidthRecorder()
        _ = recorder.observe(sidebar: 220, list: 330, window: 1300)
        #expect(recorder.observe(sidebar: 260, list: 330, window: 1300) == PaneWidths(sidebar: 260, library: 330))
        #expect(recorder.observe(sidebar: 260, list: 400, window: 1300) == PaneWidths(sidebar: 260, library: 400))
    }

    @Test func windowResizeDoesNotSave() {
        var recorder = PaneWidthRecorder()
        _ = recorder.observe(sidebar: 220, list: 330, window: 1300)
        #expect(recorder.observe(sidebar: 200, list: 300, window: 960) == nil)
        // A later drag compares against the shrunken widths, not the saved ones.
        #expect(recorder.observe(sidebar: 240, list: 300, window: 960) == PaneWidths(sidebar: 240, library: 300))
    }

    @Test func hiddenColumnsAndSubPointNoiseAreIgnored() {
        var recorder = PaneWidthRecorder()
        _ = recorder.observe(sidebar: 220, list: 330, window: 1300)
        #expect(recorder.observe(sidebar: 0, list: 330, window: 1300) == nil)
        #expect(recorder.observe(sidebar: 220.4, list: 330, window: 1300) == nil)
    }

    @Test func layoutSettlingWithoutMouseDownDoesNotSave() {
        var recorder = PaneWidthRecorder()
        _ = recorder.observe(sidebar: 220, list: 330, window: 1300, mouseDown: false)
        #expect(recorder.observe(sidebar: 220, list: 331, window: 1300, mouseDown: false) == nil)
        #expect(recorder.observe(sidebar: 220, list: 360, window: 1300) == PaneWidths(sidebar: 220, library: 360))
    }
}
