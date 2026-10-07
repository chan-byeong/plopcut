import AppKit
import NotedropCore
import SwiftUI

struct LibraryListView: View {
    @Bindable var model: LibraryModel
    @State private var filtersOpen = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.warnings.isEmpty { warningBanner }
            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(.title3.bold())
                    Text(L10n.t("dropCount", ["count": String(model.filtered.count)])).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.hasRefiningFilters {
                    Button { model.clearFilters() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless).help(L10n.t("clearFilters")).accessibilityLabel(L10n.t("clearFilters"))
                }
                Button { filtersOpen.toggle() } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .buttonStyle(.borderless).help(L10n.t("openFilters")).accessibilityLabel(L10n.t("openFilters"))
                    .popover(isPresented: $filtersOpen) { FilterPopover(model: model) }
            }
            if model.hasRefiningFilters { chips }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var chips: some View {
        HStack {
            if let app = model.app { chip(app) { model.app = nil } }
            if model.dateRange != .all { chip(FilterPopover.title(model.dateRange)) { model.dateRange = .all } }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) { Label(text, systemImage: "xmark").labelStyle(.titleAndIcon).font(.caption) }
            .buttonStyle(.bordered).controlSize(.small).accessibilityLabel("\(L10n.t("removeFilter")) \(text)")
    }

    private var warningBanner: some View {
        Label("\(model.warnings.count) drop(s) could not be read", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.warnings.map(\.message).joined(separator: "\n"))
    }

    @ViewBuilder private var content: some View {
        let groups = DateGroup.group(model.filtered)
        if model.isLoading && model.drops.isEmpty {
            ProgressView(L10n.t("loadingDrops")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
        } else if model.drops.isEmpty {
            ContentUnavailableView(L10n.t("noDrops"), systemImage: "tray")
        } else if groups.isEmpty {
            ContentUnavailableView(L10n.t("noMatches"), systemImage: "magnifyingglass")
        } else {
            List(selection: $model.selectedID) {
                ForEach(groups, id: \.group) { entry in
                    Section(Formatting.groupTitle(entry.group)) {
                        ForEach(entry.drops) { drop in DropRow(drop: drop).tag(drop.id) }
                    }
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: String.self) { ids in
                if let drop = model.drops.first(where: { ids.contains($0.id) }) {
                    if let url = drop.source.url.flatMap(URL.init(string:)), drop.source.url?.isEmpty == false {
                        Button(L10n.t("openSource")) { NSWorkspace.shared.open(url) }
                    }
                    if drop.type == .text, let text = drop.text {
                        Button(L10n.t("copyContent")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                }
            }
        }
    }
}

struct FilterPopover: View {
    @Bindable var model: LibraryModel

    static func title(_ range: DateRange) -> String {
        switch range {
        case .all: L10n.t("anyTime")
        case .today: L10n.t("today")
        case .last7Days: L10n.t("last7")
        case .last30Days: L10n.t("last30")
        }
    }

    var body: some View {
        Form {
            Picker(L10n.t("filterApp"), selection: $model.app) {
                Text(L10n.t("allApps")).tag(String?.none)
                ForEach(model.allApps, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Picker(L10n.t("filterDate"), selection: $model.dateRange) {
                ForEach([DateRange.all, .today, .last7Days, .last30Days], id: \.self) { Text(Self.title($0)).tag($0) }
            }
        }
        .padding(16).frame(width: 280)
    }
}

struct DropRow: View {
    let drop: Drop

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: drop.type == .image ? "photo" : "textformat").foregroundStyle(.secondary).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(drop.title).fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Formatting.time(drop.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(Formatting.preview(drop)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let app = drop.source.appName { Text(app).font(.caption).foregroundStyle(.secondary) }
                    ForEach(drop.tags.prefix(3), id: \.self) { Text("#\($0)").font(.caption).foregroundStyle(.tint) }
                    if drop.tags.count > 3 { Text("+\(drop.tags.count - 3)").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(.vertical, 3)
    }
}
