import SwiftUI

@main
struct NotedropApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        WindowGroup {
            MainWindow(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .task { await model.reload() }
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
    }
}
