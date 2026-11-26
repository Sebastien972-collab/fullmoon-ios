#if os(iOS)
import SwiftUI

/// Native presentation only. The host supplies its transcript, status and all side effects.
@MainActor
public struct NoctisChatView<Transcript: View, Status: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var prompt: String
    @State private var showsDrawer = false
    @State private var composerFocused = false
    @State private var historySearch = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let title: String
    private let modelName: String
    private let conversations: [NoctisConversationSummary]
    private let selectedConversationID: UUID?
    private let isEmpty: Bool
    private let isGenerating: Bool
    private let isStopping: Bool
    private let canSend: Bool
    private let contentWidth: CGFloat
    private let focusRequest: UUID?
    private let onSend: () -> Void
    private let onStop: () -> Void
    private let onNewConversation: () -> Void
    private let onSelectConversation: (UUID) -> Void
    private let onDeleteConversation: (UUID) -> Void
    private let onSettings: () -> Void
    private let transcript: Transcript
    private let status: Status

    public init(
        prompt: Binding<String>,
        title: String,
        modelName: String,
        conversations: [NoctisConversationSummary],
        selectedConversationID: UUID?,
        isEmpty: Bool,
        isGenerating: Bool,
        isStopping: Bool,
        canSend: Bool,
        contentWidth: CGFloat = 760,
        focusRequest: UUID? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onNewConversation: @escaping () -> Void,
        onSelectConversation: @escaping (UUID) -> Void,
        onDeleteConversation: @escaping (UUID) -> Void,
        onSettings: @escaping () -> Void,
        @ViewBuilder transcript: () -> Transcript,
        @ViewBuilder status: () -> Status
    ) {
        self._prompt = prompt
        self.title = title
        self.modelName = modelName
        self.conversations = conversations
        self.selectedConversationID = selectedConversationID
        self.isEmpty = isEmpty
        self.isGenerating = isGenerating
        self.isStopping = isStopping
        self.canSend = canSend
        self.contentWidth = contentWidth
        self.focusRequest = focusRequest
        self.onSend = onSend
        self.onStop = onStop
        self.onNewConversation = onNewConversation
        self.onSelectConversation = onSelectConversation
        self.onDeleteConversation = onDeleteConversation
        self.onSettings = onSettings
        self.transcript = transcript()
        self.status = status()
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background(NoctisStyle.canvas)
        .onChange(of: horizontalSizeClass) { _, _ in showsDrawer = false }
        .onChange(of: selectedConversationID) { _, _ in showsDrawer = false }
        .onChange(of: focusRequest) { _, request in
            if request != nil { composerFocused = true }
        }
        .accessibilityAction(.escape) { showsDrawer = false }
    }

    private var regularLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            history
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            conversation
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var compactLayout: some View {
        GeometryReader { geometry in
            let drawerWidth = min(330, max(0, geometry.size.width - 60))
            ZStack(alignment: .leading) {
                if showsDrawer {
                    history.frame(width: drawerWidth)
                }
                ZStack {
                    conversation
                        .disabled(showsDrawer)
                        .accessibilityHidden(showsDrawer)
                    if showsDrawer {
                        Button {
                            showsDrawer = false
                        } label: {
                            Color.black.opacity(0.12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    }
                }
                .frame(width: geometry.size.width)
                .background(NoctisStyle.canvas)
                .clipShape(RoundedRectangle(cornerRadius: showsDrawer ? 28 : 0))
                .offset(x: showsDrawer ? drawerWidth : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(sidebarAnimation, value: showsDrawer)
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            NoctisChatHeader(
                title: title,
                modelName: modelName,
                onSidebar: toggleSidebar,
                onNewConversation: newConversation,
                onSettings: openSettings
            )
            if isEmpty {
                NoctisEmptyConversation()
            } else {
                transcript.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                status.frame(maxWidth: .infinity, alignment: .leading)
                NoctisChatComposer(
                    prompt: $prompt,
                    focused: $composerFocused,
                    isGenerating: isGenerating,
                    isStopping: isStopping,
                    canSend: canSend,
                    onSend: onSend,
                    onStop: onStop
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity)
            .background(NoctisStyle.canvas)
        }
    }

    private var history: some View {
        NoctisConversationList(
            search: $historySearch,
            conversations: conversations,
            selectedID: selectedConversationID,
            onSelect: selectConversation,
            onDelete: onDeleteConversation,
            onClose: horizontalSizeClass == .regular ? nil : { showsDrawer = false }
        )
    }

    private var sidebarAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private func toggleSidebar() {
        composerFocused = false
        if horizontalSizeClass == .regular {
            withAnimation(sidebarAnimation) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        } else {
            showsDrawer.toggle()
        }
    }

    private func selectConversation(_ identifier: UUID) {
        composerFocused = false
        showsDrawer = false
        onSelectConversation(identifier)
    }

    private func newConversation() {
        composerFocused = false
        showsDrawer = false
        onNewConversation()
    }

    private func openSettings() {
        composerFocused = false
        onSettings()
    }
}
#endif
