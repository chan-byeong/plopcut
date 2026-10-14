import SwiftUI

/// A toolbar action: an SF Symbol whose title is both the VoiceOver name and, unless `help` says more, the tooltip.
struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var help: String?
    let action: () -> Void

    init(_ title: String, systemImage: String, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) { Label(title, systemImage: systemImage) }
            .help(help ?? title)
    }
}
