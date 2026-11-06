import SwiftUI

struct WelcomeConversation: View {
    let onSelect: (String) -> Void
    private let suggestions: [(title: LocalizedStringResource, prompt: LocalizedStringResource)] = [
        ("chat.welcome.suggestion.clarify", "chat.welcome.prompt.clarify"),
        ("chat.welcome.suggestion.explain", "chat.welcome.prompt.explain"),
        ("chat.welcome.suggestion.plan", "chat.welcome.prompt.plan")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("chat.welcome.title")
                    .font(.title2.weight(.semibold))
                Text("chat.welcome.description")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    ForEach(suggestions, id: \.prompt.key) { suggestion in
                        Button { onSelect(String(localized: suggestion.prompt)) } label: {
                            HStack {
                                Text(suggestion.title).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                            }
                            .padding(12)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 400)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top)
    }
}

#Preview { WelcomeConversation { _ in } }
