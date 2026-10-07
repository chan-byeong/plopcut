import SwiftUI

@main
struct NotedropApp: App {
    @State private var model = LibraryModel()

    /// `NOTEDROP_APPEARANCE=light|dark` forces a theme for screenshots until the theme setting lands (stage 5).
    private static var devColorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["NOTEDROP_APPEARANCE"] {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindow(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(Self.devColorScheme)
                .task { await model.reload() }
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
    }
}
