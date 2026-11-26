#if os(iOS)
import QuickLook
import SwiftData
import SwiftUI

private enum ProjectSection: CaseIterable {
    case conversations, files, artifacts, tasks

    var title: String {
        switch self {
        case .conversations: ProjectText.label("Conversations")
        case .files: ProjectText.label("Files")
        case .artifacts: ProjectText.label("Artifacts")
        case .tasks: ProjectText.label("Tasks")
        }
    }
}

struct ProjectDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var library = ProjectsLibrary.shared
    @Query(sort: \Thread.timestamp, order: .reverse) private var threads: [Thread]
    @State private var section: ProjectSection = .conversations
    @State private var editing = false
    @State private var confirmRemoval = false
    @State private var choosingChat = false
    @State private var fileSheet: ProjectFileSheet?
    @State private var preview: URL?
    @State private var textPreview: URL?
    @State private var error: String?
    let id: String
    let onContinue: (Thread?, String) -> Void

    private var linked: [Thread] {
        guard let project = library.project(id) else { return [] }
        return threads.filter { project.threads.contains($0.id) }
            .map { (thread: $0, date: $0.projectLastActivity) }
            .sorted { $0.date > $1.date }.map(\.thread)
    }

    var body: some View {
        Group {
            if let project = library.project(id) {
                List {
                    Section {
                        header(project)
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        sectionContent(project)
                    } header: { sectionPicker }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(project.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .sheet(isPresented: $editing) { ProjectCreationSheet(project: project) }
                .sheet(isPresented: $choosingChat) { chatPicker }
                .sheet(item: $fileSheet, content: filePicker)
                .quickLookPreview($preview)
                .sheet(isPresented: Binding(get: { textPreview != nil }, set: { if !$0 { textPreview = nil } })) {
                    if let textPreview { SpaceTextPreview(url: textPreview) }
                }
                .confirmationDialog(ProjectText.label("Delete this project?"), isPresented: $confirmRemoval,
                                    titleVisibility: .visible) {
                    Button(ProjectText.label("Delete project"), role: .destructive) {
                        do {
                            try library.remove(id)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } message: {
                    Text(ProjectText.label("Your conversations and files stay in History and Space."))
                }
            } else {
                ContentUnavailableView(ProjectText.label("Project unavailable"),
                                       systemImage: "folder.badge.questionmark")
            }
        }
        .projectError($error)
    }

    private func header(_ project: WorkspaceProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !project.goal.isEmpty {
                Text(project.goal).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
            if !project.instructions.isEmpty {
                DisclosureGroup(ProjectText.label("Standing instructions")) { Text(project.instructions) }
                    .font(.subheadline)
            }
            if let latest = linked.first, let message = latest.messages.max(by: { $0.timestamp < $1.timestamp }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ProjectText.label("Latest message")).font(.caption).foregroundStyle(.secondary)
                    Text(message.content).font(.callout).lineLimit(2)
                }
            }
            Button {
                onContinue(linked.first, id)
            } label: {
                Label(ProjectText.label("Continue project"), systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .textCase(nil)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(ProjectSection.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(section == item ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                if section == item { Capsule().fill(.tint.opacity(0.12)) }
                            }
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(section == item ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets())
        .textCase(nil)
    }

    @ViewBuilder private func sectionContent(_ project: WorkspaceProject) -> some View {
        switch section {
        case .conversations:
            if linked.isEmpty { Text(ProjectText.label("No linked conversations")).foregroundStyle(.secondary) }
            ForEach(linked) { thread in
                Button { onContinue(thread, id) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(thread.projectDisplayTitle).foregroundStyle(.primary).lineLimit(2)
                            Text(thread.projectLastActivity, style: .date).font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "bubble.left") }
                }
                .swipeActions {
                    Button(ProjectText.label("Unlink")) {
                        update { $0.threads.remove(thread.id) }
                    }
                }
                .contextMenu {
                    Button(ProjectText.label("Unlink")) { update { $0.threads.remove(thread.id) } }
                }
            }
            Button { onContinue(nil, id) } label: {
                Label(ProjectText.label("New conversation"), systemImage: "square.and.pencil")
            }
            Button { choosingChat = true } label: {
                Label(ProjectText.label("Link a conversation"), systemImage: "link")
            }
        case .artifacts, .files:
            ProjectFilesSection(projectID: id, artifacts: section == .artifacts,
                                sheet: $fileSheet, error: $error) { url in
                if section == .artifacts || WorkspaceFiles.isCode(url) { textPreview = url } else { preview = url }
            }
        case .tasks:
            ProjectTasksSection(projectID: id)
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { editing = true } label: { Label(ProjectText.label("Edit project"), systemImage: "pencil") }
                Button(role: .destructive) { confirmRemoval = true } label: {
                    Label(ProjectText.label("Delete project"), systemImage: "trash")
                }
            } label: { Label(ProjectText.label("Project actions"), systemImage: "ellipsis") }
        }
    }

    private var chatPicker: some View {
        let available = threads.filter { library.projectID(for: $0.id) == nil }
        return NavigationStack {
            List(available) { thread in
                Button(thread.projectDisplayTitle) {
                    do {
                        try library.link(threadID: thread.id, to: id)
                        choosingChat = false
                    } catch { choosingChat = false; self.error = error.localizedDescription }
                }
            }
            .overlay {
                if available.isEmpty {
                    ContentUnavailableView(ProjectText.label("No available conversations"), systemImage: "bubble.left")
                }
            }
            .navigationTitle(ProjectText.label("Link a conversation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProjectText.label("Cancel")) { choosingChat = false }
                }
            }
        }
    }

    @ViewBuilder private func filePicker(_ sheet: ProjectFileSheet) -> some View {
        let attach: (URL) -> Void = { url in
            guard let path = WorkspaceFiles.relativePath(for: url) else { return }
            update { project in
                if sheet.isArtifact {
                    if !project.artifacts.contains(path) { project.artifacts.append(path) }
                } else if !project.files.contains(path) {
                    project.files.append(path)
                }
            }
        }
        switch sheet {
        case .chooseFile, .chooseArtifact:
            WorkspaceItemPicker(section: sheet.isArtifact ? .artifacts : .files, onPick: attach)
        case .importFile, .createArtifact:
            WorkspaceImportSheet(kind: sheet.isArtifact ? .artifact : .file, onImport: attach)
        }
    }

    private func update(_ edit: (inout WorkspaceProject) -> Void) {
        do { try library.change(id, edit) } catch { self.error = error.localizedDescription }
    }
}
#endif
