import SwiftUI

@main
struct NotedropApp: App {
    @State private var model = LibraryModel(settings: LibraryModel.defaultSettings)

    init() {
        // settings.json owns the column widths (spec L-15). AppKit's own split autosave would restore widths that a
        // narrow window squeezed, so drop it before the window is built.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
        }
    }

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
