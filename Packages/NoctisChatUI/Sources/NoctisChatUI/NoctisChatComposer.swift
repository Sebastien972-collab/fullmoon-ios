#if os(iOS)
import SwiftUI

@MainActor
struct NoctisChatComposer: View {
    @Binding var prompt: String
    @Binding var focused: Bool
    let isGenerating: Bool
    let isStopping: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text(NoctisStrings.text("composer.placeholder"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                NoctisComposerTextView(text: $prompt, focused: $focused)
            }
            .padding(.vertical, 10)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            primaryButton
        }
        .padding(12)
        .modifier(NoctisGlassSurface(shape: RoundedRectangle(cornerRadius: 28)))
    }

    private var primaryButton: some View {
        Button(action: performPrimaryAction) {
            Group {
                if isStopping {
                    ProgressView().tint(NoctisStyle.canvas)
                } else {
                    Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(NoctisStyle.canvas)
            .background(
                isGenerating || canSend ? Color.primary : Color.secondary,
                in: Circle()
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isStopping || (!isGenerating && !canSend))
        .accessibilityLabel(NoctisStrings.text(primaryActionKey))
        .accessibilityIdentifier("noctis.composer.primary")
    }

    private var primaryActionKey: String {
        if isStopping { return "composer.stopping" }
        return isGenerating ? "composer.stop" : "composer.send"
    }

    private func performPrimaryAction() {
        guard !isStopping else { return }
        if isGenerating {
            onStop()
        } else if canSend {
            onSend()
        }
    }
}
#endif
