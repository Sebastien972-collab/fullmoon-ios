// Created by Sébastien DAGUIN

#if os(iOS)
import Noctis
import NoctisChatUI
import SwiftData
import SwiftUI

/// Connects the presentation package to Fullmoon's existing conversations and local runtime.
struct NoctisChatWorkspace: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppManager.self) private var appManager
    @Query(sort: \Thread.timestamp, order: .reverse) private var threads: [Thread]
    @Binding var currentThread: Thread?
    @Binding var showSettings: Bool
    @Bindable var viewModel: ChatView.ViewModel
    let speaker: ReplySpeaker

    @State private var pendingDestination: Destination?
    @State private var pendingDeletion: Thread?
    @State private var deletionError: String?
    @State private var newConversationDraft = ""
    @State private var composerDrafts = ComposerDrafts()
    @State private var composerFocusRequest = UUID()
    @State private var showsLibrary = false
    @State private var handsFree = HandsFreeConversation()
    @State private var spokenReply: Message?

    private var chatVisible: Bool { scenePhase == .active && !showSettings && !showsLibrary }

    private enum Destination: Equatable {
        case conversation(UUID?)
        case delete(UUID)
    }

    var body: some View {
        workspace
            .environment(\.handsFreeConversation, handsFree)
            .background {
                if let spokenReply {
                    SpokenReplyStream(reply: spokenReply, viewModel: viewModel, speaker: speaker, cancel: endVoice)
                        .id(spokenReply.id)
                }
            }
            .sheet(isPresented: $showsLibrary) {
                WorkspaceLibraryScreen(sections: [.files, .images, .artifacts, .code]) {
                    showsLibrary = false
                }
                .noctisAppLock()
            }
            .confirmationDialog(
                "chats.delete.confirmation.title",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("common.button.delete", role: .destructive, action: confirmDeletion)
                Button("common.button.cancel", role: .cancel) { pendingDeletion = nil }
            }
            .alert(
                "chats.delete.error.title",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("common.button.ok") { deletionError = nil }
            } message: {
                Text(deletionError ?? "")
            }
            .onChange(of: currentThread?.id) { previousID, _ in
                // The first send creates and selects a thread in the same turn.
                if previousID != nil { endVoice() }
                synchronizeSelection(previousID: previousID)
            }
            .onChange(of: showSettings || showsLibrary || scenePhase == .background) { _, hidden in
                if hidden { endVoice() }
            }
            .onChange(of: handsFree.isActive) { _, active in
                if !active, spokenReply != nil { stopReading() }
            }
            .onChange(of: viewModel.isSending) { _, sending in
                if !sending { finishPendingNavigation() }
            }
            .onDisappear {
                endVoice()
                pendingDestination = nil
                viewModel.stop()
            }
            .task {
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                await viewModel.loadModel()
            }
    }

    private var workspace: some View {
        NoctisChatView(
            prompt: $viewModel.prompt,
            title: viewModel.chatTitle(for: currentThread),
            modelName: modelName,
            conversations: conversationSummaries,
            selectedConversationID: currentThread?.id,
            isEmpty: currentThread?.messages.isEmpty ?? true,
            isGenerating: viewModel.isSending,
            isStopping: viewModel.isStopping,
            canSend: canSend,
            contentWidth: appManager.appearance.contentWidth,
            focusRequest: composerFocusRequest,
            onSend: { send(.keyboard) },
            onStop: stopGenerating,
            onNewConversation: { requestNavigation(.conversation(nil)) },
            onSelectConversation: { requestNavigation(.conversation($0)) },
            onDeleteConversation: { identifier in
                pendingDeletion = threads.first { $0.id == identifier }
            },
            onSettings: { showSettings = true },
            onLibrary: { showsLibrary = true },
            transcript: { transcript },
            status: {
                NoctisChatStatus(viewModel: viewModel) { composerFocusRequest = UUID() }
            }
        )
        .composer { focus in
            ComposerInput(
                prompt: $viewModel.prompt,
                isEnabled: viewModel.isInputEnabled && pendingDestination == nil,
                isSending: viewModel.isSending,
                isStopping: viewModel.isStopping,
                isLoading: viewModel.isLoading,
                modelName: modelName,
                status: viewModel.isConnected ? "chat.connection.status.ready" : viewModel.connectionMessage,
                onSend: send,
                onStop: stopGenerating,
                focus: focus
            )
            .environment(\.composerThreadID, currentThread?.id)
            .environment(\.composerDrafts, composerDrafts)
            .disabled(showSettings || showsLibrary)
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if let currentThread {
            ConversationView(
                thread: currentThread,
                onRegenerate: { regenerate($0, in: currentThread) },
                onRetry: { regenerate($0, in: currentThread) },
                onEdit: { message in
                    viewModel.editUserMessage(message, in: currentThread, context: modelContext)
                    composerFocusRequest = UUID()
                },
                onDelete: { message in
                    if speaker.currentMessageID == message.id { endVoice() }
                    viewModel.deleteMessage(message, in: currentThread, context: modelContext)
                },
                onBranch: { message in
                    viewModel.createBranch(from: message, in: currentThread, context: modelContext) {
                        self.currentThread = $0
                    }
                },
                generatingMessageID: viewModel.generatingMessageID,
                generationPhase: viewModel.generationPhase,
                usesChatGPTLayout: true
            )
        }
    }

    private var canSend: Bool {
        viewModel.isInputEnabled && !viewModel.isSending && !viewModel.isStopping
            && viewModel.hasMeaningfulPrompt && pendingDestination == nil
    }

    private var modelName: String {
        if viewModel.modelRuntime == .foundationModels {
            return String(localized: viewModel.modelRuntime.title)
        }
        return NoctisConfiguration.modelID.split(separator: "/").last.map(String.init)
            ?? NoctisConfiguration.modelID
    }

    private var conversationSummaries: [NoctisConversationSummary] {
        threads.filter { !$0.isDeleted }.map { thread in
            let title = viewModel.chatTitle(for: thread)
            let preview = thread.sortedMessages.last?.previewText
                .replacingOccurrences(of: "\n", with: " ") ?? ""
            let searchText = ([title] + thread.messages.map(\.content)).joined(separator: "\n")
            return NoctisConversationSummary(
                id: thread.id,
                title: title,
                preview: String(preview.prefix(120)),
                searchText: searchText
            )
        }
    }

    private func send(_ origin: ChatInputOrigin) {
        guard canSend, chatVisible else {
            if origin == .handsFree { handsFree.end() }
            return
        }
        stopReading()
        viewModel.send(to: currentThread, in: modelContext) { currentThread = $0 }
        guard origin != .keyboard else { return }
        guard let id = viewModel.generatingMessageID,
              let reply = currentThread?.messages.first(where: { $0.id == id }) else {
            handsFree.end()
            return
        }
        if origin == .handsFree { handsFree.submitted(replyID: id) }
        spokenReply = reply
        speaker.beginStream(messageID: id) { finished in
            guard spokenReply?.id == id else { return }
            spokenReply = nil
            if origin == .handsFree {
                if finished && chatVisible { handsFree.replyFinished(id) } else { handsFree.end() }
            }
        }
    }

    private func stopReading() {
        spokenReply = nil
        speaker.stop()
    }

    private func endVoice() {
        handsFree.end()
        stopReading()
    }

    private func stopGenerating() {
        endVoice()
        viewModel.stop()
    }

    private func regenerate(_ message: Message, in thread: Thread) {
        guard pendingDestination == nil else { return }
        endVoice()
        viewModel.regenerate(message, in: thread, context: modelContext)
    }
}

private extension NoctisChatWorkspace {
    private func requestNavigation(_ destination: Destination) {
        if case .conversation(let identifier) = destination, identifier == currentThread?.id {
            pendingDestination = nil
            return
        }
        appManager.playHaptic()
        endVoice()
        pendingDestination = destination
        if viewModel.isSending {
            // Keep the active thread alive until Noctis has flushed and saved the interrupted response.
            viewModel.stop()
        } else {
            finishPendingNavigation()
        }
    }

    func finishPendingNavigation() {
        guard !viewModel.isSending, let destination = pendingDestination else { return }
        pendingDestination = nil
        switch destination {
        case .conversation(let identifier):
            guard identifier != currentThread?.id else { return }
            if let identifier {
                guard let thread = threads.first(where: { $0.id == identifier && !$0.isDeleted }) else { return }
                currentThread = thread
            } else {
                currentThread = nil
            }
        case .delete(let identifier):
            guard let thread = threads.first(where: { $0.id == identifier && !$0.isDeleted }) else { return }
            delete(thread)
        }
    }

    func synchronizeSelection(previousID: UUID?) {
        // The runtime tracks drafts for saved conversations; retain the unsent new-chat draft here.
        if previousID == nil { newConversationDraft = viewModel.prompt }
        viewModel.updateThreadSelection(currentThread)
        if currentThread == nil { viewModel.prompt = newConversationDraft }
        if let generatingID = viewModel.generatingMessageID,
           currentThread?.messages.contains(where: { $0.id == generatingID }) != true {
            viewModel.stop()
        }
    }

    func confirmDeletion() {
        guard let thread = pendingDeletion, !thread.isDeleted else { return }
        pendingDeletion = nil
        if viewModel.isSending && currentThread?.id == thread.id {
            requestNavigation(.delete(thread.id))
        } else {
            delete(thread)
        }
    }

    func delete(_ thread: Thread) {
        let identifier = thread.id
        let wasSelected = currentThread?.id == identifier
        var deletionStarted = false
        do {
            // Save unrelated edits before the deletion so rollback only restores this operation.
            try modelContext.save()
            deletionStarted = true
            for message in thread.messages { modelContext.delete(message) }
            modelContext.delete(thread)
            try modelContext.save()
            if wasSelected { currentThread = nil }
        } catch {
            if deletionStarted { modelContext.rollback() }
            deletionError = error.localizedDescription
        }
    }
}
#endif
