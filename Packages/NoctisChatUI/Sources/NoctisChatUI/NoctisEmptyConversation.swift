#if os(iOS)
import SwiftUI

@MainActor
struct NoctisEmptyConversation: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                welcome
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("Noctis")
                .font(.title.weight(.semibold))
            Text(NoctisStrings.text("conversation.welcome"))
                .font(.title3)
            Text(NoctisStrings.text("conversation.welcome.detail"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
#endif
