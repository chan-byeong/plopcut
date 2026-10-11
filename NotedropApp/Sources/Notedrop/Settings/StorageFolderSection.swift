import SwiftUI

/// Settings row for the storage folder: the path, a button to change it, and what happened last.
struct StorageFolderSection: View {
    @Environment(StorageFolderModel.self) private var model

    var body: some View {
        Section(L10n.t("storageFolder")) {
            LabeledContent(L10n.t("storageFolder")) {
                Text(model.path)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Button(L10n.t("chooseFolder")) { Task { await model.chooseFolder() } }
            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).listRowBackground(Color.clear)
            }
            StorageFolderNoticeText(notice: model.notice).listRowBackground(Color.clear)
        }
    }
}

/// Status line under the folder controls. Rendered as caption-sized subtext with no background;
/// only failures keep a color (red) to signal the difference in meaning.
struct StorageFolderNoticeText: View {
    let notice: StorageFolderNotice?

    var body: some View {
        switch notice {
        case .none:
            EmptyView()
        case .cancelled:
            Text(L10n.t("folderCancelled")).font(.caption).foregroundStyle(.secondary)
        case .updated:
            Text(L10n.t("folderSet")).font(.caption).foregroundStyle(.secondary)
        case .confirmed:
            Text(L10n.t("folderConfirmed")).font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }
}

/// Shown over the main window until the user confirms the default folder or picks another. It has no cancel:
/// cancelling the folder dialog leaves this sheet in place.
struct FirstRunSheet: ViewModifier {
    let model: StorageFolderModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model.needsFirstRun }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("chooseStorage")).font(.headline)
                Text(L10n.t("firstRunBody")).fixedSize(horizontal: false, vertical: true)
                Text(model.path).textSelection(.enabled).lineLimit(2).truncationMode(.middle).foregroundStyle(.secondary)
                StorageFolderNoticeText(notice: model.notice)
                HStack {
                    Spacer()
                    Button(L10n.t("chooseFolderAction")) { Task { await model.chooseFolderOnFirstRun() } }
                    Button(L10n.t("useDefaultFolder")) { Task { await model.useDefaultFolder() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 420)
            .interactiveDismissDisabled()
        }
    }
}
