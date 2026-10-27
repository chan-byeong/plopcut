import AppKit
import Testing
@testable import Plopcut

@MainActor
@Suite struct MenuBarTests {
    @Test func openLibraryIdIsRouted() {
        #expect(MenuBarAction(id: "open-library") == .openLibrary)
        #expect(MenuBarAction(id: "save-clipboard") == .saveClipboard)
        #expect(MenuBarAction(id: "open-settings") == .openSettings)
    }

    @Test func unknownIdsAreIgnored() {
        #expect(MenuBarAction(id: "nope") == nil)
        #expect(MenuBarAction(id: "") == nil)
    }

    /// Records what the status item shows and holds each scheduled step until the test fires it.
    @MainActor final class Harness {
        var shown: [MenuBarAppearance] = []
        var pending: [Int: (delay: Duration, work: @MainActor () -> Void)] = [:]
        var cancelled: [Int] = []
        var reduceMotion = false
        private var next = 0
        var feedback: MenuBarFeedback!

        init() {
            feedback = MenuBarFeedback(
                apply: { [unowned self] in shown.append($0) },
                schedule: { [unowned self] delay, work in
                    let id = next
                    next += 1
                    pending[id] = (delay, work)
                    return { [unowned self] in
                        cancelled.append(id)
                        pending[id] = nil
                    }
                },
                reduceMotion: { [unowned self] in reduceMotion })
        }

        var delays: [Duration] { pending.keys.sorted().compactMap { pending[$0]?.delay } }

        /// Runs the step scheduled for `delay`.
        func fire(_ delay: Duration) {
            guard let id = pending.first(where: { $0.value.delay == delay })?.key, let step = pending[id] else { return }
            pending[id] = nil
            step.work()
        }
    }

    // T-03: the dot falls (200 ms), turns into a check, and is back 1.1 s after the start.
    @Test func savedDropsThenChecksThenRestores() {
        let h = Harness()
        h.feedback.showSaved()
        #expect(h.shown.last == MenuBarAppearance(accent: .dot, motion: .drop, tooltip: L10n.t("menuBarSaved")))
        #expect(h.delays == [.milliseconds(200), .milliseconds(1100)])
        h.fire(.milliseconds(200))
        #expect(h.shown.last == MenuBarAppearance(accent: .check, motion: nil, tooltip: L10n.t("menuBarSaved")))
        h.fire(.milliseconds(1100))
        #expect(h.shown.last == .idle)
        #expect(h.shown.last?.tooltip == "Plopcut")
    }

    // T-03: the mark shakes and the exclamation mark stays; nothing is scheduled to clear it.
    @Test func errorShakesAndStaysUntilTheMenuOpens() {
        let h = Harness()
        h.feedback.showError(reason: "Storage folder is not writable.")
        #expect(h.shown.last == MenuBarAppearance(accent: .exclamation, motion: .shake, tooltip: L10n.t("menuBarFailed")))
        #expect(h.pending.isEmpty)
        #expect(h.feedback.failureReason == "Storage folder is not writable.")
    }

    // T-05: opening the menu hands over the reason once and puts the dot back.
    @Test func openingTheMenuTakesTheFailure() {
        let h = Harness()
        h.feedback.showError(reason: "Boom")
        #expect(h.feedback.menuWillOpen() == "Boom")
        #expect(h.shown.last == .idle)
        #expect(h.feedback.menuWillOpen() == nil)
    }

    @Test func openingTheMenuWithoutAFailureChangesNothing() {
        let h = Harness()
        #expect(h.feedback.menuWillOpen() == nil)
        #expect(h.shown.isEmpty)
    }

    // spec 2.1: a success during a failure replaces it and drops the error items.
    @Test func aSuccessReplacesAFailure() {
        let h = Harness()
        h.feedback.showError(reason: "Boom")
        h.feedback.showSaved()
        #expect(h.shown.last?.accent == .dot)
        #expect(h.feedback.failureReason == nil)
        #expect(h.feedback.menuWillOpen() == nil)
    }

    @Test func aNewSaveRestartsTheTimers() {
        let h = Harness()
        h.feedback.showSaved()
        h.feedback.showSaved()
        #expect(h.cancelled == [0, 1])
        #expect(h.pending.count == 2)
    }

    @Test func aFailureCancelsAPendingRestore() {
        let h = Harness()
        h.feedback.showSaved()
        h.feedback.showError(reason: "Boom")
        #expect(h.pending.isEmpty)
        #expect(h.shown.last?.accent == .exclamation)
    }

    // Reduce Motion: same symbols and timing, no movement.
    @Test func reduceMotionSwapsSymbolsWithoutMoving() {
        let h = Harness()
        h.reduceMotion = true
        h.feedback.showSaved()
        #expect(h.shown.last?.motion == nil)
        #expect(h.delays == [.milliseconds(200), .milliseconds(1100)])
        h.feedback.showError(reason: "Boom")
        #expect(h.shown.last == MenuBarAppearance(accent: .exclamation, motion: nil, tooltip: L10n.t("menuBarFailed")))
    }

    // T-05: the failure header, reason, separator and Open settings come first, only while failing.
    @Test func menuListsTheFailureOnTop() {
        let items = MenuBarController.menuItems(failure: "Boom")
        #expect(items.map(\.title) == [L10n.t("pendingFailed"), "Boom", "", L10n.t("openSettings"), L10n.t("saveClipboard"), L10n.t("openLibrary")])
        #expect(items[2].isSeparatorItem)
        #expect(items[1].isEnabled == false)
        #expect(items[3].representedObject as? String == MenuBarAction.openSettings.rawValue)
    }

    @Test func menuWithoutAFailureHasOnlyTheTwoCommands() {
        let items = MenuBarController.menuItems(failure: nil)
        #expect(items.map(\.title) == [L10n.t("saveClipboard"), L10n.t("openLibrary")])
    }

    // F-11: the Floating Drops section, only while a panel floats (spec 2.8).
    private static let floating = [
        MenuBarController.FloatingEntry(id: "a", title: "First"),
        MenuBarController.FloatingEntry(id: "b", title: "Second"),
    ]

    @Test func withoutFloatingPanelsTheSectionIsLeftOut() {
        let items = MenuBarController.menuItems(failure: nil, floating: [], hasHidden: false)
        #expect(items.map(\.title) == [L10n.t("saveClipboard"), L10n.t("openLibrary")])
        #expect(!items.contains { $0.isSeparatorItem })
    }

    @Test func oneFloatingPanelGetsTheWholeSection() {
        let items = MenuBarController.menuItems(failure: nil, floating: [Self.floating[0]])
        #expect(items.map(\.title) == [
            L10n.t("saveClipboard"), L10n.t("openLibrary"), "", L10n.t("floatingDrops"), "First", "",
            L10n.t("hideAllFloating"), L10n.t("closeAllFloating"),
        ])
        #expect(items[2].isSeparatorItem && items[5].isSeparatorItem)
        #expect(items[3].isSectionHeader)
        #expect(items[4].representedObject as? String == "a")
        #expect(items[6].representedObject as? String == MenuBarAction.hideAllFloating.rawValue)
        #expect(items[7].representedObject as? String == MenuBarAction.closeAllFloating.rawValue)
    }

    @Test func floatingDropsAreListedInFloatOrder() {
        let items = MenuBarController.menuItems(failure: nil, floating: Self.floating)
        #expect(items.compactMap { $0.representedObject as? String }.filter { ["a", "b"].contains($0) } == ["a", "b"])
        #expect(items.map(\.title).contains("Second"))
    }

    @Test func anyHiddenPanelTurnsHideAllIntoShowAll() {
        let items = MenuBarController.menuItems(failure: nil, floating: Self.floating, hasHidden: true)
        #expect(items.map(\.title).suffix(2) == [L10n.t("showAllFloating"), L10n.t("closeAllFloating")])
        #expect(!items.map(\.title).contains(L10n.t("hideAllFloating")))
        #expect(items[items.count - 2].representedObject as? String == MenuBarAction.showAllFloating.rawValue)
    }

    @Test func theFailureStaysOnTopAboveTheFloatingSection() {
        let items = MenuBarController.menuItems(failure: "Boom", floating: [Self.floating[0]])
        #expect(items.first?.title == L10n.t("pendingFailed"))
        #expect(items.map(\.title).suffix(6) == [
            "", L10n.t("floatingDrops"), "First", "", L10n.t("hideAllFloating"), L10n.t("closeAllFloating"),
        ])
    }

    // The registry answers hasHidden for the menu: one panel shown again from the list still leaves Show All.
    @Test func showingOnePanelFromTheListStillOffersShowAll() {
        let floating = FloatingDrops { _, _, _ in FloatingDropsTests.FakePanel(id: "", cascade: 0) }
        floating.float("a")
        floating.float("b")
        floating.hideAll()
        floating.show("a")
        #expect(floating.hasHidden)
        floating.show("b")
        #expect(!floating.hasHidden)
    }

    @Test func floatingActionIdsAreRouted() {
        #expect(MenuBarAction(id: "hide-all-floating") == .hideAllFloating)
        #expect(MenuBarAction(id: "show-all-floating") == .showAllFloating)
        #expect(MenuBarAction(id: "close-all-floating") == .closeAllFloating)
    }

    @Test func motionFramesSettleOnTheRestingMark() {
        #expect(MenuBarController.frames(.drop).first?.lift ?? 0 > 0)
        #expect(MenuBarController.frames(.drop).allSatisfy { $0.shift == 0 })
        #expect(MenuBarController.frames(.shake).last?.shift == 0)
        #expect(MenuBarController.frames(.shake).allSatisfy { $0.lift == 0 })
    }
}
