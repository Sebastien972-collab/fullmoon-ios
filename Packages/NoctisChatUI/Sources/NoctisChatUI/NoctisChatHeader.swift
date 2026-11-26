#if os(iOS)
import SwiftUI

@MainActor
struct NoctisChatHeader: View {
    let title: String
    let modelName: String
    let onSidebar: () -> Void
    let onNewConversation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NoctisToolbarButton(
                icon: .menu,
                label: NoctisStrings.text("history.open"),
                action: onSidebar
            )
            .accessibilityIdentifier("noctis.sidebar")

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Noctis" : title)
                    .font(.headline)
                    .lineLimit(1)
                if !modelName.isEmpty {
                    Text(modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            NoctisToolbarButton(
                icon: .newConversation,
                label: NoctisStrings.text("conversation.new"),
                action: onNewConversation
            )
            .accessibilityIdentifier("noctis.newConversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
#endif
