// Created by Sébastien DAGUIN

import Foundation

extension ChatView.ViewModel {
    var hasMeaningfulPrompt: Bool { prompt.contains { !$0.isWhitespace } }
    var isInputEnabled: Bool { isConnected && !isLoading }

    var connectionMessage: LocalizedStringResource {
        guard isLoading else { return "chat.connection.status.disconnected" }
        switch loadPhase {
        case .downloading: return "chat.connection.status.downloading"
        case .loading: return "chat.connection.status.loading"
        case .ready: return "chat.connection.status.ready"
        }
    }

    func chatTitle(for thread: Thread?) -> String {
        thread?.title ?? thread?.sortedMessages.first.map { String($0.content.prefix(70)) }
            ?? String(localized: "chats.default_title")
    }
}
