// Created by Sébastien DAGUIN

#if os(iOS)
import SwiftUI

/// Keeps model availability and recovery actions tied to the existing Noctis runtime.
struct NoctisChatStatus: View {
    @Bindable var viewModel: ChatView.ViewModel
    let onRestorePrompt: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !viewModel.isConnected { connectionStatus }
            if let error = viewModel.submissionError { errorStatus(error) }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "moon.stars")
                    .accessibilityHidden(true)
            }
            Text(viewModel.connectionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !viewModel.isLoading {
                Button("common.button.retry") {
                    Task { await viewModel.loadModel() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func errorStatus(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(error).font(.caption).textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if viewModel.lastFailedPrompt != nil {
                Button("chat.error.button.restore_prompt") {
                    viewModel.restoreLastFailedPrompt()
                    onRestorePrompt()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
