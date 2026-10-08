import AppKit
import Foundation

/// The seam in front of the system folder dialog, so the settings logic can be tested without a window.
@MainActor
protocol FolderPicker {
    /// The chosen folder, or `nil` when the user cancelled.
    func pickFolder(startingAt: URL?) -> URL?
}

@MainActor
struct OpenPanelFolderPicker: FolderPicker {
    func pickFolder(startingAt: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("chooseFolder")
        panel.prompt = L10n.t("chooseFolderAction")
        panel.directoryURL = startingAt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
