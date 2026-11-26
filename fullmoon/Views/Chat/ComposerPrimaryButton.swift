#if os(iOS)
import NoctisChatUI
import SwiftUI

struct ComposerPrimaryButton: View {
    @Environment(AppManager.self) private var appManager
    enum Mode {
        case stopping, stop, authorizing, finishing, sendDictation, insert, send, microphone

        var label: String {
            switch self {
            case .stopping, .stop: String(localized: "chat.input.stop.accessibility.label")
            case .authorizing: composerCopy("Preparing microphone…")
            case .finishing: composerCopy("Finishing dictation…")
            case .sendDictation: composerCopy("Send dictation")
            case .insert: composerCopy("Insert")
            case .send: String(localized: "chat.input.send.accessibility.label")
            case .microphone: composerCopy("Start dictation")
            }
        }
    }

    let mode: Mode
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            appManager.playHaptic()
        } label: {
            Group {
                if [.stopping, .authorizing, .finishing].contains(mode) {
                    ProgressView().controlSize(.small)
                } else {
                    NoctisIcon(primaryIcon, size: 19)
                        .foregroundStyle(ContrastingSymbolColor(background: actionColor))
                        .frame(width: 34, height: 34)
                        .background(actionColor, in: Circle())
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("noctis.composer.primary")
        .accessibilityLabel(mode.label)
    }

    private var primaryIcon: NoctisIcon.Glyph {
        switch mode {
        case .stop: .stop
        case .microphone: .microphone
        default: .send
        }
    }

    private var actionColor: Color { mode == .stop ? .red : appManager.resolvedAccent }
}
#endif
