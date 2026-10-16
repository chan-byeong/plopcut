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
    @State private var filtersOpen = false
    @State private var sidebarColumnWidth: CGFloat = 0
    @State private var listColumnWidth: CGFloat = 0
    @State private var recorder = PaneWidthRecorder()
    @State private var pendingSave: Task<Void, Never>?
    /// Closing the overlay returns focus to the drop list; toolbar buttons take no key focus without Full Keyboard Access.
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        LayoutMetrics.inspectorFitsBeside(contentWidth: width, sidebarHidden: columns == .detailOnly)
    }

    private func layout(sideBySide: Bool, width: CGFloat) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.sidebarRange.lowerBound, ideal: model.paneWidths.sidebar, max: LayoutMetrics.sidebarRange.upperBound)
        } content: {
            if model.collection == .settings {
                // The window title comes from this column; in Settings it is the only toolbar item (spec 2.3).
                Color.clear.navigationSplitViewColumnWidth(0)
                    .navigationTitle(L10n.t("settings"))
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
                    .navigationSplitViewColumnWidth(
                        min: LayoutMetrics.listRange.lowerBound, ideal: model.paneWidths.library, max: LayoutMetrics.listRange.upperBound)
                    .background(SplitViewRestorer(widths: model.paneWidths))
            }
        } detail: {
            if model.collection == .settings {
                SettingsView(model: settings)
            } else {
                // A plain HStack instead of `.inspector`: toggling that modifier from layout code crashed AppKit constraints.
                HStack(spacing: 0) {
                    DropDetailView(model: model, listFocused: $listFocused)
                        // Keeps a narrow window from squeezing the list below its minimum.
                        .frame(minWidth: LayoutMetrics.bodyMin)
                    if sideBySide && model.inspectorVisible {
                        Divider()
                        InspectorView(model: model).frame(width: LayoutMetrics.inspectorWidth)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !sideBySide && model.inspectorOverlayOpen && model.collection != .settings {
                InspectorView(model: model)
                    .frame(width: LayoutMetrics.inspectorWidth, alignment: .topLeading)
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
            visible: model.collection != .settings && (!LayoutMetrics.searchIsCompact(windowWidth: width) || searchOpen)))
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
        // [Filter · Clear filters] [Inspector toggle], then the search field, which macOS keeps at the trailing edge
        // (spec 2.3, PLO-92). Refresh is the Cmd+R menu command and Settings is the sidebar row, so neither has a
        // button; Settings shows only its title.
        ToolbarItemGroup(placement: .primaryAction) {
            if model.collection != .settings {
                ToolbarButton(L10n.t("openFilters"), systemImage: "line.3.horizontal.decrease") { filtersOpen.toggle() }
                    .popover(isPresented: $filtersOpen) { FilterPopover(model: model) }
                    .disabled(model.drops.isEmpty)
                if model.hasRefiningFilters {
                    ToolbarButton(L10n.t("clearFilters"), systemImage: "xmark.circle") { model.clearFilters() }
                }
                if LayoutMetrics.searchIsCompact(windowWidth: width) {
                    ToolbarButton(L10n.t("search"), systemImage: "magnifyingglass") { openSearch() }
                }
                let inspectorShown = sideBySide ? model.inspectorVisible : model.inspectorOverlayOpen
                ToolbarButton(
                    L10n.t(inspectorShown ? "hideInspector" : "showInspector"), systemImage: "sidebar.right",
                    help: L10n.t("inspectorPanelHelp")
                ) {
                    if sideBySide { model.inspectorVisible.toggle() } else { model.inspectorOverlayOpen.toggle() }
                }
                .disabled(model.drops.isEmpty)
            }
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
