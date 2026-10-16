import AppKit
import PlopcutCore
import SwiftUI

struct LibraryListView: View {
    @Bindable var model: LibraryModel
    var listFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.warnings.isEmpty { warningBanner }
            content
        }
        .navigationTitle(model.title)
        .navigationSubtitle(Formatting.dropCount(model.filtered.count))
    }

    /// Title and count live in the window toolbar (navigationTitle/Subtitle); only filter chips stay in the pane.
    @ViewBuilder private var header: some View {
        if model.hasRefiningFilters { chips.padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s) }
    }

    private var chips: some View {
        HStack {
            if let app = model.app { RemovableChip(text: app, removeLabel: L10n.t("removeFilter")) { model.app = nil } }
            if model.dateRange != .all {
                RemovableChip(text: FilterPopover.title(model.dateRange), removeLabel: L10n.t("removeFilter")) { model.dateRange = .all }
            }
            Spacer(minLength: 0)
        }
    }

    private var warningBanner: some View {
        Label(L10n.t("unreadableDrops", ["count": String(model.warnings.count)]), systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange).padding(.horizontal, Spacing.l).padding(.bottom, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.warnings.map(\.message).joined(separator: "\n"))
    }

    @ViewBuilder private var content: some View {
        let groups = model.groups
        if model.isLoading && model.drops.isEmpty {
            ProgressView(L10n.t("loadingDrops")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError {
            ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
        } else if model.drops.isEmpty {
            ContentUnavailableView {
                BrandMarkView().frame(width: 72, height: 72)
            } description: {
                Text(L10n.t("noDrops"))
            }
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
            .slimScrollers()
            .focused(listFocused)
            .focusedValue(\.trashSelectedDrop, model.selectedID == nil ? nil : { if let id = model.selectedID { model.pendingDeleteID = id } })
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
                    Button(L10n.t("exportMarkdown")) { Task { await model.exportWithPanel(id: drop.id) } }
                    Divider()
                    Button(L10n.t("moveTrash"), role: .destructive) { model.pendingDeleteID = drop.id }
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
        .padding(Spacing.l).frame(width: LayoutMetrics.popoverWidth)
    }
}

struct DropRow: View {
    let drop: Drop

    /// The type symbol: the text glyph or a photo. It stays the leading icon when no source app icon is known.
    static func typeSymbol(for type: DropType) -> String { type == .image ? "photo" : "textformat" }

    /// The source app's icon with a small type badge in its lower right corner, so text and image drops can still be
    /// told apart. The app name is printed under the title, so the icon itself is decoration. Without an app icon the
    /// type symbol alone is shown, as before.
    @ViewBuilder private var leadingIcon: some View {
        if let icon = SourceAppIcons.shared.icon(forAppNamed: drop.source.appName) {
            // Gray with extra contrast keeps each logo's shape readable without competing with the title.
            Image(nsImage: icon).resizable().grayscale(1).contrast(1.3).opacity(0.92)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: Radius.appIcon, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.appIcon, style: .continuous).stroke(.separator, lineWidth: 0.5))
                .accessibilityLabel(L10n.t(drop.type == .image ? "image" : "text"))
                .frame(width: 22, height: 20, alignment: .leading)
                .padding(.top, 1)  // optical: centers the icon on the title's cap height
        } else {
            // The same 22 x 20 box as above, so the title starts at the same place with or without an app icon.
            Image(systemName: Self.typeSymbol(for: drop.type)).foregroundStyle(.secondary)
                .frame(width: 22, height: 20, alignment: .leading)
                .padding(.top, 1)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            leadingIcon
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(drop.title).fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: Spacing.xs)
                    Text(Formatting.time(drop.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(Formatting.preview(drop)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: Spacing.s) {
                    if let app = drop.source.appName { Text(app).font(.caption).foregroundStyle(.secondary) }
                    ForEach(drop.tags.prefix(3), id: \.self) { Text(Formatting.tag($0)).font(.caption).foregroundStyle(.secondary) }
                    if drop.tags.count > 3 { Text("+\(drop.tags.count - 3)").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Formatting.rowAccessibilityLabel(drop))
    }
}
