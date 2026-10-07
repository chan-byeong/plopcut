import AppKit
import NotedropCore
import SwiftUI

struct DropDetailView: View {
    let drop: Drop?

    var body: some View {
        if let drop {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(drop.type == .image ? L10n.t("imageDrops") : drop.type == .text ? L10n.t("textDrops") : drop.type.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(drop.title).font(.title.bold()).textSelection(.enabled)
                    HStack {
                        Button { openSource(drop) } label: { Label(L10n.t("openSource"), systemImage: "arrow.up.right.square") }
                            .disabled(URL(string: drop.source.url ?? "") == nil || drop.source.url?.isEmpty != false)
                    }
                    Divider()
                    body(of: drop)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(L10n.t("selectHint"), systemImage: "text.cursor")
        }
    }

    @ViewBuilder private func body(of drop: Drop) -> some View {
        if let url = drop.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 640)
        } else if drop.type == .image {
            Label(L10n.t("imagePreviewUnavailable"), systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
        } else if let text = drop.text {
            Text(text).font(.body).textSelection(.enabled)
        }
    }

    private func openSource(_ drop: Drop) {
        if let value = drop.source.url, let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }
}

struct InspectorView: View {
    let drop: Drop?

    var body: some View {
        ScrollView {
            if let drop {
                VStack(alignment: .leading, spacing: 18) {
                    section(L10n.t("note")) { Text(drop.note ?? L10n.t("noNote")).foregroundStyle(drop.note == nil ? .secondary : .primary) }
                    section(L10n.t("tags")) {
                        if drop.tags.isEmpty { Text(L10n.t("noTags")).foregroundStyle(.secondary) } else { Text(drop.tags.map { "#\($0)" }.joined(separator: "  ")) }
                    }
                    section(L10n.t("source")) {
                        Text(drop.source.appName ?? L10n.t("unknownApp"))
                        Text("\(L10n.t("savedAt")) \(Formatting.dateTime(drop.createdAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup(L10n.t("sourceDetails")) {
                        VStack(alignment: .leading, spacing: 6) {
                            detail(L10n.t("window"), drop.source.windowTitle)
                            detail(L10n.t("updatedAt"), Formatting.dateTime(drop.updatedAt))
                            detail(L10n.t("url"), drop.source.url)
                            detail(L10n.t("file"), drop.source.filePath)
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(L10n.t("information"))
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); body() }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}
