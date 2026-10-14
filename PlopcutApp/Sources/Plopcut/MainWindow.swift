import AppKit
import PlopcutCore
import SwiftUI

struct MainWindow: View {
    @Bindable var model: LibraryModel
    let settings: SettingsModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var searchPresented = false
    /// In narrow windows the field only exists after the icon (or Cmd+F) opens it.
    @State private var searchOpen = false
    @State private var sidebarColumnWidth: CGFloat = 0
    @State private var listColumnWidth: CGFloat = 0
    @State private var recorder = PaneWidthRecorder()
    @State private var pendingSave: Task<Void, Never>?
    /// Closing the overlay returns focus to the drop list; toolbar buttons take no key focus without Full Keyboard Access.
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sidebar 220 + list 300 + body 360 + two 8 pt dividers + inspector 280 (design-system.md).
    private static let sideBySideWidth: CGFloat = 1176
    private static let sidebarWidth: CGFloat = 220
    /// Keeps a narrow window from squeezing the list below its 300 pt minimum.
    private static let bodyMinWidth: CGFloat = 360
    /// Below this window width the search field becomes an icon (spec 2.3).
    private static let compactSearchWidth: CGFloat = 1050

    var body: some View {
        GeometryReader { proxy in
            layout(sideBySide: isSideBySide(width: proxy.size.width), width: proxy.size.width)
                .onChange(of: [sidebarColumnWidth, listColumnWidth]) { paneWidthsChanged(window: proxy.size.width) }
        }
    }

    /// Saves after the divider stops moving, so a drag writes settings.json once.
    private func paneWidthsChanged(window: CGFloat) {
        let visibleSidebar = columns == .detailOnly ? 0 : sidebarColumnWidth
        guard let widths = recorder.observe(
            sidebar: visibleSidebar, list: listColumnWidth, window: window, mouseDown: NSEvent.pressedMouseButtons & 1 != 0) else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // The last layout pass after mouse-up is not seen as a drag; save the widths as they are now.
            let settled = columns == .detailOnly ? widths.sidebar : sidebarColumnWidth
            model.savePaneWidths(PaneWidths(sidebar: settled, library: listColumnWidth > 0 ? listColumnWidth : widths.library))
        }
    }

    private func openSearch() {
        guard !searchOpen else { searchPresented = true; return }
        searchOpen = true
        // In narrow windows the field is only inserted now; request focus once it exists.
        Task { @MainActor in searchPresented = true }
    }

    private func isSideBySide(width: CGFloat) -> Bool {
        width >= Self.sideBySideWidth - (columns == .detailOnly ? Self.sidebarWidth : 0)
    }

    private func layout(sideBySide: Bool, width: CGFloat) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: model.paneWidths.sidebar, max: 320)
        } content: {
            if model.collection == .settings {
                Color.clear.navigationSplitViewColumnWidth(0)
                    .onAppear { listColumnWidth = 0 }
            } else {
                LibraryListView(model: model, listFocused: $listFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Measure the filled column, not the content's intrinsic size. The floating sidebar is drawn
                    // inset, so its own width under-reports; the list's left edge is the divider.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        sidebarColumnWidth = $0.minX
                        listColumnWidth = $0.width
                    }
                    .navigationSplitViewColumnWidth(min: 300, ideal: model.paneWidths.library, max: 560)
                    .background(SplitViewRestorer(widths: model.paneWidths))
            }
        } detail: {
            if model.collection == .settings {
                SettingsView(model: settings)
            } else {
                // A plain HStack instead of `.inspector`: toggling that modifier from layout code crashed AppKit constraints.
                HStack(spacing: 0) {
                    DropDetailView(model: model, listFocused: $listFocused)
                        .frame(minWidth: Self.bodyMinWidth)
                    if sideBySide && model.inspectorVisible {
                        Divider()
                        InspectorView(model: model).frame(width: 280)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !sideBySide && model.inspectorOverlayOpen && model.collection != .settings {
                InspectorView(model: model)
                    .frame(width: 280, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Rectangle().fill(.regularMaterial).ignoresSafeArea())
                    .overlay(alignment: .leading) { Divider() }
                    .shadow(radius: 8)
                    .background {
                        // Escape closes the overlay without needing keyboard focus inside it.
                        Button("") { model.inspectorOverlayOpen = false }
                            .keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
                    }
                    .transition(InspectorOverlayMotion.slides(reduceMotion: reduceMotion) ? .move(edge: .trailing) : .identity)
            }
        }
        .animation(InspectorOverlayMotion.animation(reduceMotion: reduceMotion), value: model.inspectorOverlayOpen)
        .onChange(of: model.inspectorOverlayOpen) { _, open in if !open { listFocused = true } }
        .modifier(ToolbarSearch(
            text: $model.search, presented: $searchPresented,
            visible: model.collection != .settings && (width >= Self.compactSearchWidth || searchOpen)))
        .onChange(of: searchPresented) { _, presented in if !presented { searchOpen = false } }
        .toolbar { toolbarContent(sideBySide: sideBySide, width: width) }
        .confirmationDialog(
            L10n.t("confirmTrash"), isPresented: Binding(get: { model.pendingDeleteID != nil }, set: { if !$0 { model.pendingDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("moveTrash"), role: .destructive) {
                if let id = model.pendingDeleteID { Task { await model.delete(id: id) } }
                model.pendingDeleteID = nil
            }
            Button(L10n.t("cancel"), role: .cancel) { model.pendingDeleteID = nil }
        } message: { Text(L10n.t("confirmTrashBody")) }
        .alert(model.alertMessage ?? "", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            if let recovery = model.alertRecovery {
                Button(L10n.t(recovery.titleKey)) { model.performRecovery() }
            }
            Button(L10n.t("ok"), role: .cancel) {}
        }
        .overlay(alignment: .bottom) { NoticeBanner(model: model) }
        .background {
            // Cmd+F focuses search at every width; the toolbar icon only exists in narrow windows.
            Button("") { openSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model.collection == .settings)
                .opacity(0).accessibilityHidden(true)
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(sideBySide: Bool, width: CGFloat) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if width < Self.compactSearchWidth && model.collection != .settings {
                Button { openSearch() } label: { Label(L10n.t("search"), systemImage: "magnifyingglass") }
                    .help(L10n.t("search"))
            }
            Button { Task { await model.reload() } } label: { Label(L10n.t("refreshLibrary"), systemImage: "arrow.clockwise") }
                .help(L10n.t("refreshLibrary"))
            Button {
                if sideBySide { model.inspectorVisible.toggle() } else { model.inspectorOverlayOpen.toggle() }
            } label: {
                let shown = sideBySide ? model.inspectorVisible : model.inspectorOverlayOpen
                Label(L10n.t(shown ? "hideInspector" : "showInspector"), systemImage: "sidebar.right")
            }
            .help(L10n.t("inspectorPanelHelp"))
            .disabled(model.collection == .settings)
            Button { model.collection = model.collection == .settings ? .all : .settings } label: {
                Label(L10n.t(model.collection == .settings ? "openLibrary" : "openSettings"),
                      systemImage: model.collection == .settings ? "tray.full" : "gearshape")
            }
            .help(L10n.t(model.collection == .settings ? "openLibrary" : "openSettings"))
        }
    }
}

/// How the inspector overlay appears. With Reduce Motion on it shows its final state at once (design-system.md).
enum InspectorOverlayMotion {
    static func slides(reduceMotion: Bool) -> Bool { !reduceMotion }
    static func animation(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .default }
}

/// The toolbar search field. Hidden (icon only) in narrow windows; the query survives while hidden.
struct ToolbarSearch: ViewModifier {
    @Binding var text: String
    @Binding var presented: Bool
    let visible: Bool

    func body(content: Content) -> some View {
        if visible {
            content.searchable(text: keepingQueryOnDismiss, isPresented: $presented, placement: .toolbar,
                               prompt: L10n.t("searchPlaceholder"))
        } else {
            content
        }
    }

    /// AppKit empties the field when Escape dismisses it, but Escape must keep the query (spec L-08).
    /// The clear button and deleting the text still empty it.
    private var keepingQueryOnDismiss: Binding<String> {
        Binding(get: { text }, set: { value in
            let event = NSApp.currentEvent
            if value.isEmpty, event?.type == .keyDown, event?.keyCode == Self.escapeKeyCode { return }
            text = value
        })
    }

    private static let escapeKeyCode: UInt16 = 53

}

/// A short confirmation ("Drop moved to Trash.") that fades after a few seconds.
struct NoticeBanner: View {
    @Bindable var model: LibraryModel

    var body: some View {
        if let notice = model.notice {
            Text(notice)
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, Spacing.l)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    model.notice = nil
                }
        }
    }
}
