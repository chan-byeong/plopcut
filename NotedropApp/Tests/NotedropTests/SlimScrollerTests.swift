import AppKit
import NotedropCore
import SwiftUI
import Testing
@testable import Notedrop

/// Thinner scroll bars (STA-68): the Save Popup's scroll areas and the Library's lists use the small scroller, and
/// the system's own scroll bar settings (style, auto-hide) are left alone.
@MainActor
@Suite struct SlimScrollerTests {
    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// Hosts `view` in an ordered-in window so SwiftUI creates and tiles its scroll views.
    private func host<V: View>(_ view: V, size: NSSize) async -> (window: NSWindow, host: NSHostingView<V>) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        // ARC owns the window; a window that releases itself on close would be freed twice.
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        await settle()
        host.layoutSubtreeIfNeeded()
        return (window, host)
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

    private func pair() async throws -> (plain: NSScrollView, slim: NSScrollView, window: NSWindow) {
        let (window, host) = await host(Pair(), size: NSSize(width: 320, height: 120))
        let found = scrollViews(in: host).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        try #require(found.count == 2)
        return (found[0], found[1], window)
    }

    @Test func aSwiftUIScrollViewGetsTheSmallScroller() async throws {
        let (plain, slim, window) = try await pair()
        defer { window.close() }
        #expect(plain.verticalScroller?.controlSize == .regular)
        #expect(slim.verticalScroller?.controlSize == SlimScroller.controlSize)
    }

    @Test func theScrollBarIsNarrowerWhenTheSystemShowsLegacyBars() async throws {
        let (plain, slim, window) = try await pair()
        defer { window.close() }
        let plainWidth = try #require(plain.verticalScroller).frame.width
        let slimWidth = try #require(slim.verticalScroller).frame.width
        #expect(slimWidth <= plainWidth)
        // Overlay scroll bars are drawn thin already and only appear while scrolling; legacy bars take space.
        if slim.scrollerStyle == .legacy { #expect(slimWidth < plainWidth) }
    }

    @Test func theSystemScrollBarSettingsAreKept() async throws {
        let (plain, slim, window) = try await pair()
        defer { window.close() }
        #expect(slim.scrollerStyle == plain.scrollerStyle)
        #expect(slim.autohidesScrollers == plain.autohidesScrollers)
        #expect(slim.hasVerticalScroller == plain.hasVerticalScroller)
        // The helper never picks a style itself: a scroll view in the overlay style stays in it.
        slim.scrollerStyle = .overlay
        SlimScroller.apply(to: slim)
        #expect(slim.scrollerStyle == .overlay)
    }

    @Test func theKnobCanStillBeGrabbed() async throws {
        let (_, slim, window) = try await pair()
        defer { window.close() }
        let scroller = try #require(slim.verticalScroller)
        try #require(!scroller.isHidden)
        #expect(scroller.isEnabled)
        let knob = scroller.rect(for: .knob)
        #expect(knob.width > 0 && knob.height > 0)
        // `testPart` takes window coordinates.
        #expect(scroller.testPart(scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil)) == .knob)
    }

    @Test func aChangedSystemStyleDoesNotBringBackTheRegularScroller() async throws {
        let (_, slim, window) = try await pair()
        defer { window.close() }
        slim.verticalScroller?.controlSize = .regular
        NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        await settle()
        #expect(slim.verticalScroller?.controlSize == SlimScroller.controlSize)
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
        let (window, host) = await host(Nested(), size: NSSize(width: 200, height: 160))
        defer { window.close() }
        let found = scrollViews(in: host).sorted { $0.frame.width > $1.frame.width }
        try #require(found.count == 2)
        #expect(found[0].verticalScroller?.controlSize == SlimScroller.controlSize)
        #expect(found[1].verticalScroller?.controlSize == .regular)
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
        await settle()
        let window = try #require(controller.window)
        let found = scrollViews(in: try #require(window.contentView))
        // The outer fields, the text preview and the note.
        try #require(found.count >= 3)
        #expect(found.contains { $0 is NoteScrollView })
        for scrollView in found { #expect(scrollView.verticalScroller?.controlSize == SlimScroller.controlSize) }
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
        let (window, host) = await host(DetailHost(model: model), size: NSSize(width: 600, height: 200))
        defer { window.close() }
        let found = scrollViews(in: host)
        // The body, the inspector and the inspector's note editor.
        try #require(found.count >= 3)
        for scrollView in found { #expect(scrollView.verticalScroller?.controlSize == SlimScroller.controlSize) }
    }

    @Test func theLibraryListIsSlim() async throws {
        let model = await fixtureModel()
        let (window, host) = await host(LibraryHost(model: model), size: NSSize(width: 360, height: 220))
        defer { window.close() }
        let found = scrollViews(in: host)
        try #require(!found.isEmpty)
        for scrollView in found { #expect(scrollView.verticalScroller?.controlSize == SlimScroller.controlSize) }
    }
}
