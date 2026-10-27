import AppKit
import Foundation
import Observation
import PlopcutCore
import Testing
@testable import Plopcut

/// F-01: one panel per drop, in float order, and the none · visible · hidden states (spec 2.8).
@MainActor
@Suite struct FloatingDropsTests {
    final class FakePanel: FloatingPanel {
        let id: String
        let cascade: Int
        var calls: [String] = []
        init(id: String, cascade: Int) { self.id = id; self.cascade = cascade }
        func show() { calls.append("show") }
        func hide() { calls.append("hide") }
        func close() { calls.append("close") }
    }

    private final class Made {
        var panels: [FakePanel] = []
        func panel(_ id: String) -> FakePanel? { panels.first { $0.id == id } }
    }

    private func registry() -> (FloatingDrops, Made) {
        let made = Made()
        let registry = FloatingDrops { _, id, cascade in
            let panel = FakePanel(id: id, cascade: cascade)
            made.panels.append(panel)
            return panel
        }
        return (registry, made)
    }

    @Test func floatingTheSameDropAgainBringsItsPanelForward() {
        let (floating, made) = registry()
        floating.float("a")
        floating.float("a")
        #expect(made.panels.count == 1)
        #expect(made.panel("a")?.calls == ["show", "show"])
        #expect(floating.ids == ["a"])
        #expect(floating.state(of: "a") == .visible)
    }

    @Test func eachNewPanelCascadesFromTheOnesAlreadyFloating() {
        let (floating, made) = registry()
        floating.float("a")
        floating.float("b")
        floating.float("c")
        #expect(made.panels.map(\.cascade) == [0, 1, 2])
        #expect(floating.ids == ["a", "b", "c"])
        floating.close("b")
        floating.float("d")
        #expect(made.panel("d")?.cascade == 2)
        #expect(floating.ids == ["a", "c", "d"])
    }

    @Test func hideAllAndShowAllSwitchTheStatesAndKeepTheOrder() {
        let (floating, made) = registry()
        floating.float("a")
        floating.float("b")
        floating.hideAll()
        #expect(floating.state(of: "a") == .hidden && floating.state(of: "b") == .hidden)
        #expect(floating.hasHidden)
        floating.showAll()
        #expect(floating.state(of: "a") == .visible && floating.state(of: "b") == .visible)
        #expect(!floating.hasHidden)
        #expect(made.panel("a")?.calls == ["show", "hide", "show"])
        #expect(floating.ids == ["a", "b"])
    }

    @Test func showingOneHiddenPanelLeavesTheOthersHidden() {
        let (floating, _) = registry()
        floating.float("a")
        floating.float("b")
        floating.hideAll()
        floating.show("b")
        #expect(floating.state(of: "a") == .hidden)
        #expect(floating.state(of: "b") == .visible)
        floating.float("a")
        #expect(floating.state(of: "a") == .visible)
    }

    @Test func closingForgetsThePanel() {
        let (floating, made) = registry()
        floating.float("a")
        floating.hideAll()
        floating.close("a")
        #expect(made.panel("a")?.calls == ["show", "hide", "close"])
        #expect(floating.state(of: "a") == .none)
        #expect(floating.ids.isEmpty && !floating.hasHidden)
        floating.close("a")
        #expect(made.panel("a")?.calls.last == "close" && made.panel("a")?.calls.count == 3)
    }

    @Test func aPanelClosedByItsOwnButtonIsOnlyForgotten() {
        let (floating, made) = registry()
        floating.float("a")
        floating.panelDidClose("a")
        #expect(floating.state(of: "a") == .none)
        #expect(made.panel("a")?.calls == ["show"])
        floating.float("a")
        #expect(made.panels.count == 2)
    }

    @Test func closeAllClosesEveryPanel() {
        let (floating, made) = registry()
        floating.float("a")
        floating.float("b")
        floating.closeAll()
        #expect(floating.ids.isEmpty)
        #expect(made.panels.allSatisfy { $0.calls.last == "close" })
    }

    // F-07
    @Test func panelsCloseForDropsThatAreGone() {
        let (floating, made) = registry()
        floating.float("a")
        floating.float("b")
        floating.closeAll { $0 == "b" }
        #expect(floating.ids == ["b"])
        #expect(made.panel("a")?.calls.last == "close")
        #expect(made.panel("b")?.calls == ["show"])
    }

    @Test func showAndHideIgnoreDropsThatAreNotFloating() {
        let (floating, made) = registry()
        floating.show("a")
        floating.close("a")
        floating.hideAll()
        floating.showAll()
        #expect(made.panels.isEmpty)
        #expect(floating.state(of: "a") == .none)
    }

    @Test func withoutAWindowFactoryNothingFloats() {
        let floating = FloatingDrops()
        floating.float("a")
        #expect(floating.state(of: "a") == .none)
    }
}

/// F-04 and F-03: where a panel opens, how tall it gets, and when it is translucent (spec 2.8).
@Suite struct FloatingPanelLayoutTests {
    private let screen = NSRect(x: 0, y: 25, width: 1440, height: 875)
    private let size = NSSize(width: 300, height: 400)

    @Test func theFirstPanelOpensTopRightInsideTheInset() {
        let frame = FloatingPanelLayout.openingFrame(size: size, cascade: 0, in: screen)
        #expect(frame.maxX == screen.maxX - 24)
        #expect(frame.maxY == screen.maxY - 24)
        #expect(frame.size == size)
    }

    @Test func laterPanelsStepLeftAndDown() {
        let first = FloatingPanelLayout.openingFrame(size: size, cascade: 0, in: screen)
        let third = FloatingPanelLayout.openingFrame(size: size, cascade: 2, in: screen)
        #expect(third.minX == first.minX - 48)
        #expect(third.maxY == first.maxY - 48)
    }

    @Test func aStepThatLeavesTheScreenIsPulledBackInside() {
        let frame = FloatingPanelLayout.openingFrame(size: size, cascade: 60, in: screen)
        #expect(screen.contains(frame))
        #expect(frame.minX == screen.minX && frame.minY == screen.minY)
    }

    @Test func aSecondScreenIsMeasuredFromItsOwnCorner() {
        let right = NSRect(x: 1440, y: -200, width: 1920, height: 1055)
        let frame = FloatingPanelLayout.openingFrame(size: size, cascade: 0, in: right)
        #expect(frame.maxX == right.maxX - 24 && frame.maxY == right.maxY - 24)
    }

    @Test func theOpeningHeightFitsTheContentUpToSixtyPercent() {
        let titleBar: CGFloat = 22
        #expect(FloatingPanelLayout.openingHeight(contentHeight: 200.4, titleBar: titleBar, in: screen) == 223)
        #expect(FloatingPanelLayout.openingHeight(contentHeight: 5000, titleBar: titleBar, in: screen) == 525)
        #expect(FloatingPanelLayout.openingHeight(contentHeight: 30, titleBar: titleBar, in: screen) == 142)
    }

    @Test func aTinyScreenStillGetsTheMinimumHeight() {
        let tiny = NSRect(x: 0, y: 0, width: 400, height: 150)
        #expect(FloatingPanelLayout.openingHeight(contentHeight: 500, titleBar: 22, in: tiny) == 142)
    }

    @Test(arguments: [
        (false, false, false, true),
        (true, false, false, false),
        (false, true, false, false),
        (true, true, false, false),
        (false, false, true, false),
        (true, true, true, false),
    ])
    func translucentOnlyWhenIdle(cursorInside: Bool, isKey: Bool, reduceTransparency: Bool, expected: Bool) {
        #expect(FloatingPanelLayout.isTranslucent(
            cursorInside: cursorInside, isKey: isKey, reduceTransparency: reduceTransparency) == expected)
    }
}

/// The panel window itself, over the fixture drops (read only).
@MainActor
@Suite struct FloatingPanelWindowTests {
    nonisolated private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/swift-migration/fixtures/storage")

    private func loadedModel() async -> LibraryModel {
        let model = LibraryModel(storageRoot: { Self.fixtures })
        await model.reload()
        return model
    }

    /// A model over a copy of the fixtures, for tests that write.
    private func writableModel() async throws -> (LibraryModel, URL) {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: Self.fixtures, to: copy)
        let model = LibraryModel(storageRoot: { copy })
        await model.reload()
        return (model, copy)
    }

    private func panel(for drop: Drop, in model: LibraryModel, closed: @escaping () -> Void = {}) -> FloatingPanelController {
        _ = NSApplication.shared
        return FloatingPanelController(id: drop.id, model: model, cascade: 0, openInLibrary: {}, didClose: closed)
    }

    @Test func thePanelIsANonActivatingUtilityWindowThatIsNotRestored() async throws {
        let model = await loadedModel()
        let drop = try #require(model.drops.first { $0.type == .text })
        let controller = panel(for: drop, in: model)
        defer { controller.close() }
        let window = controller.window
        #expect(window.styleMask.contains(.nonactivatingPanel) && window.styleMask.contains(.utilityWindow))
        #expect(!window.styleMask.contains(.miniaturizable))
        #expect(window.level == .floating)
        #expect(!window.isRestorable && !window.hidesOnDeactivate)
        #expect(!window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.collectionBehavior.contains(.managed))
        #expect(window.title == drop.title)
        #expect(window.frame.width == FloatingPanelLayout.defaultWidth)
        #expect(window.minSize.width == 240 && window.maxSize.width == 420)
    }

    @Test func collapsingKeepsTheTopEdgeAndExpandingRestoresTheHeight() async throws {
        let model = await loadedModel()
        let drop = try #require(model.drops.first { $0.type == .text })
        let controller = panel(for: drop, in: model)
        defer { controller.close() }
        let window = controller.window
        let before = window.frame
        controller.toggleCollapse()
        #expect(controller.isCollapsed)
        #expect(window.frame.maxY == before.maxY)
        #expect(window.frame.height < before.height)
        #expect(window.minSize.height == window.maxSize.height)
        controller.toggleCollapse()
        #expect(!controller.isCollapsed)
        #expect(window.frame == before)
    }

    @Test func escapeKeepsThePanelOpen() async throws {
        let model = await loadedModel()
        let drop = try #require(model.drops.first)
        var closed = 0
        let controller = panel(for: drop, in: model) { closed += 1 }
        defer { controller.close() }
        controller.show()
        controller.window.cancelOperation(nil)
        #expect(closed == 0)
        #expect(controller.window.isVisible)
    }

    @Test func closingTheWindowReportsBack() async throws {
        let model = await loadedModel()
        let drop = try #require(model.drops.first)
        var closed = 0
        let controller = panel(for: drop, in: model) { closed += 1 }
        controller.window.performClose(nil)
        #expect(closed == 1)
    }

    // F-07
    @Test func theTitleFollowsLibraryEdits() async throws {
        let (model, root) = try await writableModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(model.selectedID)
        let controller = FloatingPanelController(id: id, model: model, cascade: 0, openInLibrary: {}, didClose: {})
        defer { controller.close() }
        model.editor.setTitle("Floating title")
        await model.editor.flush()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(controller.window.title == "Floating title")
    }

    // F-09: closing the panel right after typing leaves the note on disk.
    @Test func closingThePanelWritesTheTypedNote() async throws {
        let (model, root) = try await writableModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let drop = try #require(model.drops.first { $0.type == .text && $0.id != model.selectedID })
        let controller = FloatingPanelController(id: drop.id, model: model, cascade: 0, openInLibrary: {}, didClose: {})
        model.editor.setNote("typed in the panel", of: drop)
        controller.window.performClose(nil)
        let file = root.appendingPathComponent("drops/\(drop.id)/note.md")
        // The file lands before the editor settles its state, so wait for both.
        for _ in 0..<50
        where (try? String(contentsOf: file, encoding: .utf8)) != "typed in the panel" || model.editor.hasUnsavedEdits {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "typed in the panel")
        #expect(!model.editor.hasUnsavedEdits)
    }

    @Test func onlyAPlainEscapeHandsTheKeyboardBack() throws {
        func key(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        }
        #expect(FloatingPanelWindow.isPlainEscape(try key([])))
        #expect(!FloatingPanelWindow.isPlainEscape(try key([.command])))
    }

    // F-06
    @Test func openInLibrarySelectsTheDropAndClearsHidingFilters() async throws {
        let model = await loadedModel()
        let image = try #require(model.drops.first { $0.type == .image })
        model.collection = .text
        model.search = "zzz-no-match"
        model.reveal(image.id)
        #expect(model.selectedID == image.id)
        #expect(model.search.isEmpty && model.collection == .all)
        #expect(model.filtered.contains { $0.id == image.id })
    }

    @Test func cmdWClosesByKeyPosition() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅈ", charactersIgnoringModifiers: "ㅈ", isARepeat: false, keyCode: 13))
        #expect(FloatingPanelWindow.closesWindow(event))
        let shifted = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0,
            context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        #expect(!FloatingPanelWindow.closesWindow(shifted))
    }
}

/// F-10: the drop view's Float on Screen button (spec 2.6, 2.8).
@MainActor
@Suite struct FloatButtonTests {
    private func registry() -> FloatingDrops {
        FloatingDrops { _, id, cascade in FloatingDropsTests.FakePanel(id: id, cascade: cascade) }
    }

    @Test func theButtonFloatsClosesAndBringsBackAHiddenPanel() {
        let floating = registry()
        floating.toggle("a")
        #expect(floating.state(of: "a") == .visible)
        floating.toggle("a")
        #expect(floating.state(of: "a") == .none)
        floating.toggle("a")
        floating.hideAll()
        floating.toggle("a")
        #expect(floating.state(of: "a") == .visible)
    }

    @Test func theStateChangeIsObserved() {
        let floating = registry()
        floating.float("a")
        let changed = Flag()
        withObservationTracking { _ = floating.state(of: "a") } onChange: { changed.set() }
        floating.panelDidClose("a")
        #expect(changed.value)
    }

    @Test func titleAndTooltipFollowTheFloatingState() {
        #expect(DropAction.float(floating: false).title == L10n.t("floatDrop"))
        #expect(DropAction.float(floating: true).tooltip == L10n.t("closeFloating"))
        #expect(DropAction.float(floating: true).systemImage == "macwindow.on.rectangle")
        #expect(DropAction.float(floating: false).shortcut == nil)
    }
}

private final class Flag: @unchecked Sendable {
    private(set) var value = false
    func set() { value = true }
}
