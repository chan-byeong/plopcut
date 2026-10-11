import AppKit
import NotedropCore
import SwiftUI
import Testing
@testable import Notedrop

/// Thinner scroll bars (STA-68): the Save Popup's scroll areas and the Library's lists use the small scroller, and
/// the system's own scroll bar settings (style, auto-hide) are left alone.
///
/// The system's "Show scroll bars" setting decides the real style on the machine running the tests, so tests that
/// compare widths or grab the knob force the legacy style on the scroll views they look at.
@MainActor
@Suite struct SlimScrollerTests {
    // MARK: Helpers

    /// Polls the main run loop until `condition` holds, so a test waits for SwiftUI instead of a fixed time.
    private func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Lets queued work, such as the probe's deferred search, run when the test expects that nothing changes.
    private func settle() async { try? await Task.sleep(for: .milliseconds(200)) }

    private func allViews(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap { allViews(in: $0) } }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// Hosts `view` in a window, runs `body`, and closes the window however `body` ends.
    private func withWindow<V: View>(
        _ view: V, size: NSSize, styleMask: NSWindow.StyleMask = [.titled],
        _ body: (NSWindow, NSHostingView<V>) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: styleMask, backing: .buffered, defer: false)
        // ARC owns the window; a window that releases itself on close would be freed twice.
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await body(window, host)
    }

    private static var lines: String { (0..<80).map { "line \($0)" }.joined(separator: "\n") }

    /// Two scroll areas side by side: the left one plain, the right one slim.
    private struct Pair: View {
        var body: some View {
            HStack(spacing: 0) {
                ScrollView { Text(SlimScrollerTests.lines).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(width: 160, height: 120)
                ScrollView { Text(SlimScrollerTests.lines).frame(maxWidth: .infinity, alignment: .leading) }
                    .slimScrollers().frame(width: 160, height: 120)
            }
        }
    }

    /// The plain and the slim scroll view of `Pair`, once the probe has done its work.
    private func withPair(forceLegacy: Bool = false, _ body: (NSScrollView, NSScrollView) async throws -> Void) async throws {
        try await withWindow(Pair(), size: NSSize(width: 320, height: 120)) { _, host in
            let found = scrollViews(in: host).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            try #require(found.count == 2)
            let (plain, slim) = (found[0], found[1])
            try #require(await eventually { slim.verticalScroller?.controlSize == SlimScroller.controlSize })
            if forceLegacy {
                for scrollView in found { scrollView.scrollerStyle = .legacy; scrollView.tile() }
                host.layoutSubtreeIfNeeded()
            }
            try await body(plain, slim)
        }
    }

    // MARK: SwiftUI scroll areas

    @Test func aSwiftUIScrollViewGetsTheSmallScroller() async throws {
        try await withPair { plain, slim in
            #expect(plain.verticalScroller?.controlSize == .regular)
            #expect(slim.verticalScroller?.controlSize == SlimScroller.controlSize)
        }
    }

    @Test func theLegacyScrollBarIsNarrower() async throws {
        try await withPair(forceLegacy: true) { plain, slim in
            let plainWidth = try #require(plain.verticalScroller).frame.width
            let slimWidth = try #require(slim.verticalScroller).frame.width
            #expect(slimWidth < plainWidth)
            #expect(slim.contentSize.width > plain.contentSize.width)
        }
    }

    @Test func theScrollBarIsNeverWiderWhateverTheSystemStyleIs() async throws {
        try await withPair { plain, slim in
            #expect(slim.scrollerStyle == plain.scrollerStyle)
            let plainWidth = try #require(plain.verticalScroller).frame.width
            let slimWidth = try #require(slim.verticalScroller).frame.width
            #expect(slimWidth <= plainWidth)
        }
    }

    @Test func theSystemScrollBarSettingsAreKept() async throws {
        try await withPair { plain, slim in
            #expect(slim.scrollerStyle == plain.scrollerStyle)
            #expect(slim.autohidesScrollers == plain.autohidesScrollers)
            #expect(slim.hasVerticalScroller == plain.hasVerticalScroller)
            // The helper never picks a style itself: a scroll view in either style stays in it.
            for style in [NSScroller.Style.overlay, .legacy] {
                slim.scrollerStyle = style
                SlimScroller.apply(to: slim)
                #expect(slim.scrollerStyle == style)
            }
        }
    }

    @Test func theKnobCanStillBeGrabbed() async throws {
        try await withPair(forceLegacy: true) { _, slim in
            let scroller = try #require(slim.verticalScroller)
            try #require(!scroller.isHidden)
            #expect(scroller.isEnabled)
            let knob = scroller.rect(for: .knob)
            try #require(knob.width > 0 && knob.height > 0)
            // `testPart` takes window coordinates.
            #expect(scroller.testPart(scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil)) == .knob)
        }
    }

    @Test func aChangedSystemStyleReappliesTheSmallScroller() async throws {
        try await withPair { _, slim in
            slim.verticalScroller?.controlSize = .regular
            // The probe reapplies on its next layout or on the system's notification, whichever comes first.
            NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
            #expect(await eventually { slim.verticalScroller?.controlSize == SlimScroller.controlSize })
        }
    }

    @Test func aNestedScrollViewIsNotMistakenForItsParent() async throws {
        struct Nested: View {
            var body: some View {
                ScrollView {
                    ScrollView { Text(SlimScrollerTests.lines) }.frame(height: 100)
                    Text(SlimScrollerTests.lines)
                }
                .slimScrollers().frame(width: 200, height: 160)
            }
        }
        try await withWindow(Nested(), size: NSSize(width: 200, height: 160)) { _, host in
            let found = scrollViews(in: host)
            try #require(found.count == 2)
            let inner = try #require(found.first { $0.enclosingScrollView != nil })
            let outer = try #require(found.first { $0.enclosingScrollView == nil })
            #expect(await eventually { outer.verticalScroller?.controlSize == SlimScroller.controlSize })
            #expect(inner.verticalScroller?.controlSize == .regular)
        }
    }

    @Test func aScrollAreaThatIsNotAScrollViewIsLeftAloneAndSearchedOnlyAFewTimes() async throws {
        struct NoScroll: View {
            var body: some View { Text("plain").slimScrollers().frame(width: 100, height: 40) }
        }
        try await withWindow(NoScroll(), size: NSSize(width: 100, height: 40)) { _, host in
            await settle()
            for _ in 0..<10 {
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
                await settle()
            }
            #expect(scrollViews(in: host).isEmpty)
            let probe = try #require(allViews(in: host).compactMap { $0 as? ProbeView }.first)
            #expect(probe.searchCount > 0)
            #expect(probe.searchCount <= ProbeView.maxFailedSearches)
        }
    }

    // MARK: Overlap rule

    @Test func aScrollViewUnderTheToolbarStillMatchesItsProbe() {
        // A list 600 tall that extends 52 under the toolbar, with its probe in the safe area below it.
        let probe = NSRect(x: 0, y: 0, width: 400, height: 548)
        let list = NSRect(x: 0, y: 0, width: 400, height: 600)
        #expect(ProbeView.overlap(list, probe) > ProbeView.minimumOverlap)
        // A nested scroll view that is only part of the area does not.
        #expect(ProbeView.overlap(NSRect(x: 0, y: 0, width: 400, height: 100), probe) < ProbeView.minimumOverlap)
        #expect(ProbeView.overlap(NSRect(x: 900, y: 0, width: 10, height: 10), probe) == 0)
    }

    // MARK: The app's own scroll areas

    @Test func everyScrollAreaOfTheSavePopupIsSlim() async throws {
        _ = NSApplication.shared
        let draft = CaptureDraft(
            type: .text, title: "T", text: Self.lines, source: DropSource(appName: "Notes"))
        let model = SavePopupModel(
            draft: draft, recentTags: [], save: { _ in throw CancellationError() }, onSaved: { _ in }, onCancel: {})
        // A short screen makes the outer fields scroll too.
        let controller = SavePopupWindowController(visibleFrame: { _ in NSRect(x: 0, y: 0, width: 900, height: 420) })
        controller.show(model)
        defer { controller.close() }
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        // The outer fields, the text preview and the note.
        try #require(await eventually { scrollViews(in: content).count >= 3 })
        #expect(scrollViews(in: content).contains { $0 is NoteScrollView })
        #expect(await eventually { scrollViews(in: content).allSatisfy { $0.verticalScroller?.controlSize == SlimScroller.controlSize } })
    }

    private func noteEditor() -> PopupNoteEditor {
        PopupNoteEditor(text: .constant(""), placeholder: "", accessibilityLabel: "Note")
    }

    @Test func theNoteScrollViewKeepsTheSmallScrollerWheneverItIsTiled() async throws {
        try await withWindow(noteEditor().frame(width: 200, height: 60), size: NSSize(width: 200, height: 60)) { _, host in
            let note = try #require(scrollViews(in: host).first { $0 is NoteScrollView })
            #expect(note.verticalScroller?.controlSize == SlimScroller.controlSize)
            note.verticalScroller?.controlSize = .regular
            note.tile()
            #expect(note.verticalScroller?.controlSize == SlimScroller.controlSize)
            // A new scroller, as after a change of the system's scroll bar setting, starts regular; AppKit tiles
            // the scroll view by itself afterwards.
            note.verticalScroller = NSScroller()
            #expect(await eventually { note.verticalScroller?.controlSize == SlimScroller.controlSize })
            NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
            note.verticalScroller?.controlSize = .regular
            #expect(await eventually { note.verticalScroller?.controlSize == SlimScroller.controlSize })
        }
    }

    private struct LibraryHost: View {
        let model: LibraryModel
        @FocusState var focused: Bool
        var body: some View { LibraryListView(model: model, listFocused: $focused) }
    }

    private func fixtureModel() async -> LibraryModel {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/swift-migration/fixtures/storage")
        let model = LibraryModel(storageRoot: { root })
        await model.reload()
        return model
    }

    private struct DetailHost: View {
        let model: LibraryModel
        @FocusState var focused: Bool
        var body: some View {
            HStack(spacing: 0) {
                DropDetailView(model: model, listFocused: $focused).frame(width: 300, height: 200)
                InspectorView(model: model).frame(width: 300, height: 200)
            }
        }
    }

    @Test func theDropBodyAndTheInspectorAreSlim() async throws {
        let model = await fixtureModel()
        try #require(model.selectedDrop != nil)
        try await withWindow(DetailHost(model: model), size: NSSize(width: 600, height: 200)) { _, host in
            // The body, the inspector and the inspector's note editor.
            try #require(await eventually { scrollViews(in: host).count >= 3 })
            #expect(await eventually { scrollViews(in: host).allSatisfy { $0.verticalScroller?.controlSize == SlimScroller.controlSize } })
        }
    }

    @Test func theLibraryListIsSlim() async throws {
        let model = await fixtureModel()
        try await withWindow(LibraryHost(model: model), size: NSSize(width: 360, height: 220)) { _, host in
            try #require(await eventually { !scrollViews(in: host).isEmpty })
            #expect(await eventually { scrollViews(in: host).allSatisfy { $0.verticalScroller?.controlSize == SlimScroller.controlSize } })
        }
    }

    /// The Library list inside a split view with a toolbar, as in the main window: the list can extend under the
    /// toolbar, so its frame is not the probe's.
    @Test func theLibraryListIsSlimUnderAToolbar() async throws {
        let model = await fixtureModel()
        struct Split: View {
            let model: LibraryModel
            @FocusState var focused: Bool
            var body: some View {
                NavigationSplitView { Text("sidebar") } detail: { LibraryListView(model: model, listFocused: $focused) }
            }
        }
        try await withWindow(
            Split(model: model), size: NSSize(width: 700, height: 420),
            styleMask: [.titled, .fullSizeContentView, .resizable]
        ) { window, host in
            window.titlebarAppearsTransparent = true
            host.layoutSubtreeIfNeeded()
            try #require(await eventually { !scrollViews(in: host).isEmpty })
            #expect(await eventually { scrollViews(in: host).allSatisfy { $0.verticalScroller?.controlSize == SlimScroller.controlSize } })
        }
    }
}
