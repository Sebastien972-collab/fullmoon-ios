#if os(iOS)
import SwiftUI

/// Native presentation only. The host supplies its transcript, status and all side effects.
@MainActor
public struct NoctisChatView<Transcript: View, Status: View>: View {
    @Environment(\.noctisPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var prompt: String
    @State private var showsDrawer = false
    @FocusState private var hostEditorFocused: Bool
    @State private var defaultEditorFocused = false
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
    private let onLibrary: (() -> Void)?
    private let transcript: Transcript
    private let status: Status

    private var customComposer: ((FocusState<Bool>.Binding) -> AnyView)?

    /// Hosts a composer with app-specific capabilities while preserving drawer and keyboard focus.
    public func composer<Content: View>(
        @ViewBuilder _ content: @escaping (FocusState<Bool>.Binding) -> Content
    ) -> Self {
        var chat = self
        chat.customComposer = { AnyView(content($0)) }
        return chat
    }

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
        onLibrary: (() -> Void)? = nil,
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
        self.onLibrary = onLibrary
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
        .background(palette.canvas)
        .onChange(of: horizontalSizeClass) { _, _ in showsDrawer = false }
        .onChange(of: selectedConversationID) { _, _ in showsDrawer = false }
        .onChange(of: focusRequest) { _, request in
            if request != nil { focusComposer(true) }
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
            let drawerOffset = layoutDirection == .rightToLeft ? -drawerWidth : drawerWidth
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
                .background(palette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: showsDrawer ? 28 : 0))
                .offset(x: showsDrawer ? drawerOffset : 0)
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
                onNewConversation: newConversation
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
                if let customComposer {
                    customComposer($hostEditorFocused)
                } else {
                    NoctisChatComposer(
                        prompt: $prompt,
                        focused: $defaultEditorFocused,
                        isGenerating: isGenerating,
                        isStopping: isStopping,
                        canSend: canSend,
                        onSend: onSend,
                        onStop: onStop
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity)
            .background(palette.canvas)
        }
    }

    private var history: some View {
        NoctisConversationList(
            search: $historySearch,
            conversations: conversations,
            selectedID: selectedConversationID,
            onSelect: selectConversation,
            onDelete: onDeleteConversation,
            onSettings: { openFromDrawer(onSettings) },
            onLibrary: onLibrary.map { action in { openFromDrawer(action) } },
            onClose: horizontalSizeClass == .regular ? nil : { showsDrawer = false }
        )
    }

    private var sidebarAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private func focusComposer(_ focused: Bool) {
        if customComposer == nil {
            defaultEditorFocused = focused
        } else {
            hostEditorFocused = focused
        }
    }

    private func toggleSidebar() {
        focusComposer(false)
        if horizontalSizeClass == .regular {
            withAnimation(sidebarAnimation) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        } else {
            showsDrawer.toggle()
        }
    }

    private func selectConversation(_ identifier: UUID) {
        focusComposer(false)
        showsDrawer = false
        onSelectConversation(identifier)
    }

    private func newConversation() {
        focusComposer(false)
        showsDrawer = false
        onNewConversation()
    }

    private func openFromDrawer(_ action: () -> Void) {
        focusComposer(false)
        showsDrawer = false
        action()
    }
}
#endif
