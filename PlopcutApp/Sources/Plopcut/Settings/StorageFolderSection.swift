import SwiftUI

/// Settings row for the storage folder: the path, a button to change it, and what happened last.
struct StorageFolderSection: View {
    @Environment(StorageFolderModel.self) private var model

    var body: some View {
        Section {
            LabeledContent(L10n.t("storageFolder")) {
                Text(model.path)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Button(L10n.t("chooseFolder")) { Task { await model.chooseFolder() } }
        } header: {
            Text(L10n.t("storageFolder"))
        } footer: {
            // A Section footer is plain subtext under the card: no row background, and it takes the standard
            // footnote style. Failures keep red because their meaning differs from a plain status.
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let problem = model.problem {
                    Text(problem).foregroundStyle(.red)
                }
                StorageFolderNoticeText(notice: model.notice)
            }
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Status line for the folder controls. Only failures carry a color; the rest is secondary subtext.
struct StorageFolderNoticeText: View {
    let notice: StorageFolderNotice?

    var body: some View {
        switch notice {
        case .none:
            EmptyView()
        case .cancelled:
            Text(L10n.t("folderCancelled")).foregroundStyle(.secondary)
        case .updated:
            Text(L10n.t("folderSet")).foregroundStyle(.secondary)
        case .confirmed:
            Text(L10n.t("folderConfirmed")).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

/// Shown over the main window until the user confirms the default folder or picks another. It has no cancel:
/// cancelling the folder dialog leaves this sheet in place.
struct FirstRunSheet: ViewModifier {
    let model: StorageFolderModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model.needsFirstRun }, set: { _ in })) {
            VStack(alignment: .leading, spacing: Spacing.m) {
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
            .padding(Spacing.xl)
            .frame(width: 420)
            .interactiveDismissDisabled()
        }
    }
}
