import SwiftUI

struct MainWindow: View {
    @Bindable var model: LibraryModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var searchPresented = false

    var body: some View {
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
                    .inspector(isPresented: $model.inspectorVisible) {
                        InspectorView(drop: model.selectedDrop)
                            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                    }
            }
        }
        .searchable(text: $model.search, isPresented: $searchPresented, placement: .toolbar, prompt: L10n.t("searchPlaceholder"))
        .toolbar { toolbarContent }
        .onKeyPress(.escape) {
            guard searchPresented else { return .ignored }
            searchPresented = false
            return .handled
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await model.reload() } } label: { Label(L10n.t("refreshLibrary"), systemImage: "arrow.clockwise") }
                .help(L10n.t("refreshLibrary"))
            Button { model.inspectorVisible.toggle() } label: {
                Label(L10n.t(model.inspectorVisible ? "hideInspector" : "showInspector"), systemImage: "sidebar.right")
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
