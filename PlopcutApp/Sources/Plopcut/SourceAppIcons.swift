import AppKit
import Foundation
import Observation

/// Looks up the icon of the app a drop was captured from. `drop.json` only stores the app's name, so the app is found
/// by name among the installed apps; an app that is not installed has no icon and the caller falls back to the type icon.
///
/// The index of installed apps is built in the background. Until it is ready no icon is returned (and nothing is
/// cached), so rows show the type icon first and redraw when `isReady` flips.
@MainActor @Observable
final class SourceAppIcons {
    static let shared = SourceAppIcons.loading(folders: AppIndex.systemFolders())

    private(set) var isReady: Bool
    @ObservationIgnored private var find: ((String) -> NSImage?)?
    @ObservationIgnored private var cache: [String: NSImage?] = [:]

    /// Ready immediately, with the given lookup (tests, or a finder that needs no index).
    init(find: @escaping (String) -> NSImage?) {
        self.find = find
        isReady = true
    }

    private init() {
        find = nil
        isReady = false
    }

    /// Builds the index of the apps in `folders` off the main thread, then becomes ready.
    static func loading(folders: [String]) -> SourceAppIcons {
        let icons = SourceAppIcons()
        Task.detached(priority: .utility) {
            let index = AppIndex.build(folders: folders)
            await icons.finish(index)
        }
        return icons
    }

    private func finish(_ index: AppIndex) {
        find = { index.icon(forAppNamed: $0) }
        isReady = true
    }

    /// Each name is looked up once, including the "not found" answer, so scrolling a long list stays cheap.
    func icon(forAppNamed name: String?) -> NSImage? {
        guard let key = name?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        _ = isReady  // read so a view that called this before the index existed is redrawn when it is ready
        guard let find else { return nil }
        if let known = cache[key] { return known }
        let image = find(key)
        cache[key] = .some(image)
        return image
    }
}

/// The installed apps by name. Both the localized name the system shows ("메모") and the file name ("Notes") lead to
/// the app; the first folder that has a name wins. Names are compared in Unicode composed form, because Korean file
/// names on disk are often decomposed.
struct AppIndex: Sendable {
    let paths: [String: String]

    static func systemFolders() -> [String] {
        let apps = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask).map(\.path)
        return apps + apps.map { $0 + "/Utilities" } + ["/System/Library/CoreServices"]
    }

    static func build(folders: [String]) -> AppIndex {
        var paths: [String: String] = [:]
        let manager = FileManager.default
        for folder in folders {
            guard let names = try? manager.contentsOfDirectory(atPath: folder) else { continue }
            for entry in names where entry.hasSuffix(".app") {
                let path = folder + "/" + entry
                let displayed = manager.displayName(atPath: path)
                let shown = displayed.hasSuffix(".app") ? String(displayed.dropLast(4)) : displayed
                for key in [shown, String(entry.dropLast(4))] {
                    let normalized = key.precomposedStringWithCanonicalMapping
                    if paths[normalized] == nil { paths[normalized] = path }
                }
            }
        }
        return AppIndex(paths: paths)
    }

    /// Falls back to a running app with that name, for apps outside the usual folders.
    @MainActor func icon(forAppNamed name: String) -> NSImage? {
        let key = name.precomposedStringWithCanonicalMapping
        let path = paths[key]
            ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL?.path
        return path.map { NSWorkspace.shared.icon(forFile: $0) }
    }
}
