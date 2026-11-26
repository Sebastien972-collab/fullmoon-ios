#if os(iOS)
import SwiftUI

@MainActor
struct NoctisEmptyConversation: View {
    @Environment(\.noctisPalette) private var palette

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
            NoctisEmblem(tint: palette.accent)
            Text("Noctis")
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
            Text(NoctisStrings.text("conversation.welcome"))
                .font(.title3)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
#endif
