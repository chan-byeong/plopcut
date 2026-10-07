import SwiftUI

struct MainWindow: View {
    @Bindable var model: LibraryModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var searchPresented = false
    /// In narrow windows the field only exists after the icon (or Cmd+F) opens it.
    @State private var searchOpen = false

    /// Sidebar 220 + list 300 + body 360 + two 8 pt dividers + inspector 280 (design-system.md).
    private static let sideBySideWidth: CGFloat = 1176
    private static let sidebarWidth: CGFloat = 220
    /// Below this window width the search field becomes an icon (spec 2.3).
    private static let compactSearchWidth: CGFloat = 1050

    var body: some View {
        GeometryReader { proxy in layout(sideBySide: isSideBySide(width: proxy.size.width), width: proxy.size.width) }
    }

    private func openSearch() {
        searchOpen = true
        searchPresented = true
    }

    private func isSideBySide(width: CGFloat) -> Bool {
        width >= Self.sideBySideWidth - (columns == .detailOnly ? Self.sidebarWidth : 0)
    }

    private func layout(sideBySide: Bool, width: CGFloat) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            if model.collection == .settings {
                Color.clear.navigationSplitViewColumnWidth(0)
            } else {
                LibraryListView(model: model)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 560)
            }
        } detail: {
            if model.collection == .settings {
                SettingsPlaceholder()
            } else {
                DropDetailView(drop: model.selectedDrop)
                    .inspector(isPresented: Binding(
                        get: { sideBySide && model.inspectorVisible },
                        set: { model.inspectorVisible = $0 })) {
                        InspectorView(drop: model.selectedDrop)
                            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                    }
            }
        }
        .overlay(alignment: .trailing) {
            if !sideBySide && model.inspectorOverlayOpen && model.collection != .settings {
                InspectorView(drop: model.selectedDrop)
                    .frame(width: 280, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Rectangle().fill(.regularMaterial).ignoresSafeArea())
                    .overlay(alignment: .leading) { Divider() }
                    .shadow(radius: 8)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.default, value: model.inspectorOverlayOpen)
        .modifier(ToolbarSearch(
            text: $model.search, presented: $searchPresented,
            visible: width >= Self.compactSearchWidth || searchOpen))
        .onChange(of: searchPresented) { _, presented in if !presented { searchOpen = false } }
        .toolbar { toolbarContent(sideBySide: sideBySide, width: width) }
        .onExitCommand { model.inspectorOverlayOpen = false } // the search field consumes Escape first
    }

    @ToolbarContentBuilder
    private func toolbarContent(sideBySide: Bool, width: CGFloat) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if width < Self.compactSearchWidth {
                Button { openSearch() } label: { Label(L10n.t("search"), systemImage: "magnifyingglass") }
                    .help(L10n.t("search"))
                    .keyboardShortcut("f", modifiers: .command)
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

struct SettingsPlaceholder: View {
    var body: some View {
        ContentUnavailableView(L10n.t("settings"), systemImage: "gearshape", description: Text("Settings arrive in stage 5 (STA-40)."))
    }
}


/// The toolbar search field. Hidden (icon only) in narrow windows; the query survives while hidden.
struct ToolbarSearch: ViewModifier {
    @Binding var text: String
    @Binding var presented: Bool
    let visible: Bool

    func body(content: Content) -> some View {
        if visible {
            content.searchable(text: $text, isPresented: $presented, placement: .toolbar, prompt: L10n.t("searchPlaceholder"))
        } else {
            content
        }
    }
}
