// This workspace draft depends on view interfaces that are not integrated yet.
// Keep it available without compiling it into the active application.
#if false
import QuickLook
import SwiftData
import SwiftUI

struct NoctisWorkspace: View {
    @Environment(AppManager.self) private var manager
    @Environment(\.modelContext) private var context
    @Binding var currentThread: Thread?
    @Bindable var viewModel: ChatView.ViewModel
    @Query(sort: \Thread.timestamp, order: .reverse) private var threads: [Thread]
    @AppStorage(ConversationArchive.storageKey) private var archive = ""
    @State private var tab = WorkspaceTab.home
    @State private var inConversation = false
    @State private var sheet: WorkspaceSheet?
    @State private var pendingCreation: WorkspaceCreation?
    @State private var activeProject: String?
    @State private var visibleProject: String?
    @State private var composerDrafts = ComposerDrafts()
    @State private var projectToOpen: String?
    @State private var spaceSection = WorkspaceSection.files
    @State private var previewURL: URL?
    @State private var recentFiles: [URL] = []
    @State private var composerRequest: ComposerAction?
    @State private var draft = ""
    @State private var focusNewChat = false
    @FocusState private var rootFocused: Bool
    @FocusState private var chatFocused: Bool

    private var recent: [Thread] {
        let archived = Set(archive.split(separator: "\n").map(String.init))
        return threads.filter { !archived.contains($0.id.uuidString) }
            .map { ($0, WorkspaceHome.activity($0)) }
            .sorted { $0.1 > $1.1 }.prefix(4).map(\.0)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: WorkspaceTab.home) {
                homeStack.toolbarVisibility(.hidden, for: .tabBar)
            } label: { tabLabel(.home) }
            Tab(value: WorkspaceTab.projects) {
                ProjectsScreen(
                    projectToOpen: $projectToOpen,
                    onVisibleProjectChange: { visibleProject = $0 },
                    onContinue: { thread, project in open(thread, project: project, focus: thread == nil) }
                )
                .toolbarVisibility(.hidden, for: .tabBar)
            } label: { tabLabel(.projects) }
            Tab(value: WorkspaceTab.space) {
                WorkspaceLibraryScreen(section: $spaceSection)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: { tabLabel(.space) }
            Tab(value: WorkspaceTab.settings) {
                SettingsView(currentThread: $currentThread, viewModel: viewModel, isTab: true)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: { tabLabel(.settings) }
        }
        .tabViewStyle(.tabBarOnly)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !inConversation || tab != .home { bottomControls }
        }
        .environment(\.composerDrafts, composerDrafts)
        .onChange(of: tab) { manager.playHaptic() }
        .sheet(item: $sheet, onDismiss: finishCreation) { item in
            sheetContent(item).noctisAppLock()
        }
        .quickLookPreview($previewURL)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
            await viewModel.loadModel()
        }
        .task { await loadRecents() }
        .onReceive(NotificationCenter.default.publisher(for: WorkspaceFiles.didChange)) { _ in
            Task { await loadRecents() }
        }
    }

    private func tabLabel(_ item: WorkspaceTab) -> some View { Label(item.title, systemImage: item.icon) }

    private var homeStack: some View {
        NavigationStack {
            WorkspaceHome(threads: recent, generatingID: viewModel.generatingMessageID,
                          open: { open($0) }, showHistory: { sheet = .history }, useShortcut: useShortcut)
                .navigationDestination(isPresented: $inConversation) {
                    ChatView(
                        currentThread: $currentThread, isPromptFocused: $chatFocused,
                        showChats: sheetBinding(.history), showSettings: sheetBinding(.settings),
                        viewModel: viewModel, embedded: true,
                        onThreadSelected: { try link($0, to: activeProject) }
                    )
                    .environment(\.composerRequest, $composerRequest)
                    .environment(\.composerProjectTitle, projectTitle(activeProject))
                    .onAppear {
                        if focusNewChat { chatFocused = true }
                        focusNewChat = false
                    }
                }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            if let error = viewModel.submissionError {
                HStack {
                    Text(error).font(.caption).lineLimit(3)
                    if !viewModel.isConnected {
                        Button("common.button.retry") { Task { await viewModel.loadModel() } }
                    }
                }
                .padding(.horizontal, 20)
            }
            ChatInputView(
                prompt: $draft, isEnabled: viewModel.isInputEnabled, isSending: viewModel.isSending,
                isStopping: viewModel.isStopping, isLoading: viewModel.isLoading,
                status: viewModel.isConnected ? "chat.connection.status.ready" : viewModel.connectionMessage,
                onSend: sendDraft, onStop: { viewModel.stop() }, focusState: $rootFocused
            )
            .environment(\.composerIsWorkspaceDraft, true)
            .environment(\.composerProjectTitle, projectTitle(draftProject))
            .padding(.horizontal, 16)
            .frame(maxWidth: 760)
            if !rootFocused {
                WorkspaceDock(selection: $tab, onCreate: { sheet = .create }, recentMenu: recentMenu)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sheetContent(_ item: WorkspaceSheet) -> some View {
        switch item {
        case .create:
            WorkspaceCreationSheet { action in
                pendingCreation = action
                sheet = nil
            }
            .presentationDetents([.medium, .large])
        case .history:
            ChatsListView(currentThread: $currentThread, isPromptFocused: $chatFocused, onOpen: { chosen in
                sheet = nil
                open(chosen, focus: chosen == nil)
            })
        case .settings:
            SettingsView(currentThread: $currentThread, viewModel: viewModel)
        case .project:
            ProjectCreationSheet(onCreated: { projectToOpen = $0 })
        case .file: WorkspaceImportSheet(kind: .file)
        case .artifact: WorkspaceImportSheet(kind: .artifact)
        }
    }

    private func sheetBinding(_ item: WorkspaceSheet) -> Binding<Bool> {
        Binding(get: { sheet == item }, set: { sheet = $0 ? item : nil })
    }

    private func finishCreation() {
        guard let action = pendingCreation else { return }
        pendingCreation = nil
        switch action {
        case .chat: open(nil, focus: true)
        case .project: showProjectForm()
        case .file, .artifact:
            spaceSection = action == .artifact ? .artifacts : .files
            tab = .space
            sheet = action == .artifact ? .artifact : .file
        case .photo, .voice:
            composerRequest = action == .photo ? .photo : .voice
            open(nil)
        }
    }

    private func showProjectForm() {
        tab = .projects
        sheet = .project
    }

    private func useShortcut(_ shortcut: WorkspaceShortcut) {
        if shortcut == .project {
            showProjectForm()
        } else {
            let prefix = String(localized: shortcut.prompt)
            draft = draft.isEmpty ? prefix : prefix + "\n" + draft
            rootFocused = true
        }
    }

    private func open(_ thread: Thread?, project: String? = nil, focus: Bool = false) {
        rootFocused = false
        if viewModel.isSending, currentThread?.id != thread?.id { viewModel.stop() }
        activeProject = project ?? thread.flatMap { ProjectsLibrary.shared.projectID(for: $0.id) }
        viewModel.updateThreadSelection(thread)
        currentThread = thread
        tab = .home
        focusNewChat = focus
        if inConversation { chatFocused = focus }
        inConversation = true
    }

    private var draftProject: String? { tab == .projects ? visibleProject : nil }

    private func sendDraft() {
        guard viewModel.isInputEnabled, !viewModel.isSending else { return }
        viewModel.updateThreadSelection(nil)
        let previous = viewModel.prompt
        let project = draftProject
        viewModel.prompt = draft
        viewModel.send(to: nil, in: context) { thread in
            try link(thread, to: project)
            draft = ""
            rootFocused = false
            currentThread = thread
            activeProject = project
            tab = .home
            inConversation = true
        }
        if !draft.isEmpty { viewModel.prompt = previous }
    }

    private func link(_ thread: Thread, to project: String?) throws {
        if let project { try ProjectsLibrary.shared.link(threadID: thread.id, to: project) }
    }

    private func projectTitle(_ id: String?) -> String? { id.flatMap { ProjectsLibrary.shared.title(for: $0) } }

    private func loadRecents() async {
        recentFiles = await Task.detached {
            Array(((try? WorkspaceFiles.items(in: .files)) ?? []).prefix(3))
        }.value
    }

    @ViewBuilder
    private func recentMenu(_ item: WorkspaceTab) -> some View {
        switch item {
        case .home:
            ForEach(recent) { thread in
                Button(viewModel.chatTitle(for: thread)) { open(thread) }
            }
            Button(workspaceText("History"), systemImage: "clock") { sheet = .history }
        case .projects:
            ForEach(ProjectsLibrary.shared.recentProjects, id: \.id) { project in
                Button(project.title) {
                    projectToOpen = project.id
                    tab = .projects
                }
            }
            Button(workspaceText("New project"), systemImage: "folder.badge.plus", action: showProjectForm)
        case .space:
            ForEach(recentFiles, id: \.self) { url in
                Button(url.lastPathComponent) { previewURL = url }
            }
            Button(workspaceText("Import a file"), systemImage: "doc.badge.plus") {
                pendingCreation = .file
                finishCreation()
            }
        case .settings:
            Button(workspaceText("Settings"), systemImage: "gearshape") { tab = .settings }
        }
    }
}

private enum WorkspaceSheet: String, Identifiable {
    case create, history, settings, project, file, artifact
    var id: Self { self }
}
#endif
