#if os(iOS)
import SwiftUI

/// Observe text only for the active spoken turn, without redrawing the whole workspace per chunk.
struct SpokenReplyStream: View {
    let reply: Message
    let viewModel: ChatView.ViewModel
    let speaker: ReplySpeaker
    let cancel: () -> Void

    private enum Update: Equatable {
        case text(String, final: Bool)
        case cancelled
    }

    private var update: Update {
        guard !reply.isDeleted, reply.modelContext != nil, !reply.hasError, !reply.isInterrupted,
              !viewModel.isStopping, viewModel.submissionError == nil else { return .cancelled }
        return .text(reply.content, final: !viewModel.isSending)
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: update, initial: true) { _, update in
                guard speaker.currentMessageID == reply.id else { return }
                switch update {
                case .text(let text, let final):
                    speaker.updateStream(messageID: reply.id, text: text, isFinal: final)
                case .cancelled:
                    cancel()
                }
            }
    }
}
#endif
