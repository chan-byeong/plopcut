import SwiftUI

struct SidebarView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        List(selection: $model.collection) {
            Section(L10n.t("collections")) {
                row(L10n.t("library"), "tray.full", .all)
                row(L10n.t("text"), "textformat", .text)
                row(L10n.t("images"), "photo", .image)
                row(L10n.t("pinned"), "pin", .pinned)
            }
            Section(L10n.t("tags")) {
                if model.allTags.isEmpty {
                    Text(L10n.t("noTags")).foregroundStyle(.secondary)
                } else {
                    ForEach(model.allTags, id: \.self) { tag in row(tag, "number", .tag(tag)) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            List(selection: $model.collection) { row(L10n.t("settings"), "gearshape", .settings) }
                .listStyle(.sidebar)
                .frame(height: 44)
                .scrollDisabled(true)
        }
        .accessibilityLabel(L10n.t("librarySidebar"))
    }

    private func row(_ title: String, _ symbol: String, _ value: SidebarSelection) -> some View {
        let count = model.count(for: value)
        // Gray icons (color-icon-secondary); the selected row turns them white with the title.
        return Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(.secondary) }
            .badge(value == .settings ? 0 : count)
            .tag(value)
    }
}
