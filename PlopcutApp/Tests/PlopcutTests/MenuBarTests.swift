import Testing
@testable import Plopcut

@MainActor
@Suite struct MenuBarTests {
    @Test func openLibraryIdIsRouted() {
        #expect(MenuBarAction(id: "open-library") == .openLibrary)
        #expect(MenuBarAction(id: "save-clipboard") == .saveClipboard)
    }

    @Test func unknownIdsAreIgnored() {
        #expect(MenuBarAction(id: "nope") == nil)
        #expect(MenuBarAction(id: "") == nil)
    }

    /// Records what the status item shows and holds the scheduled restore until the test fires it.
    @MainActor final class Harness {
        var shown: [(title: String?, tooltip: String)] = []
        var pending: [Int: @MainActor () -> Void] = [:]
        var cancelled: [Int] = []
        var delays: [Duration] = []
        private var next = 0
        var feedback: MenuBarFeedback!
        init() {
            feedback = MenuBarFeedback(
            apply: { [unowned self] in shown.append(($0, $1)) },
            schedule: { [unowned self] delay, work in
                let id = next
                next += 1
                delays.append(delay)
                pending[id] = work
                return { [unowned self] in
                    cancelled.append(id)
                    pending[id] = nil
                }
            })
        }
    }

    @Test func errorShowsFor900msThenRestores() {
        let h = Harness()
        h.feedback.showError()
        #expect(h.shown.last?.title == "Error")
        #expect(h.shown.last?.tooltip == "Error")
        #expect(h.delays == [.milliseconds(900)])
        h.pending.values.forEach { $0() }
        #expect(h.shown.last?.title == nil)
        #expect(h.shown.last?.tooltip == "plopcut")
    }

    @Test func secondErrorRestartsTheTimer() {
        let h = Harness()
        h.feedback.showError()
        h.feedback.showError()
        #expect(h.cancelled == [0])
        #expect(h.pending.count == 1)
    }

    // T-03
    @Test func savedShowsFor900msThenRestores() {
        let h = Harness()
        h.feedback.showSaved()
        #expect(h.shown.last?.title == "Saved")
        #expect(h.shown.last?.tooltip == "Saved")
        #expect(h.delays == [.milliseconds(900)])
        h.pending.values.forEach { $0() }
        #expect(h.shown.last?.title == nil)
        #expect(h.shown.last?.tooltip == "plopcut")
    }

    @Test func aNewMessageReplacesTheOneStillShowing() {
        let h = Harness()
        h.feedback.showSaved()
        h.feedback.showError()
        #expect(h.shown.last?.title == "Error")
        #expect(h.cancelled == [0])
        #expect(h.pending.count == 1)
    }
}
