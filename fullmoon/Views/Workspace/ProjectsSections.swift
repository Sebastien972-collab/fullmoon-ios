#if os(iOS)
import QuickLook
import SwiftUI

enum ProjectFileSheet: Identifiable {
    case chooseFile, chooseArtifact, importFile, createArtifact
    var id: Self { self }
    var isArtifact: Bool { self == .chooseArtifact || self == .createArtifact }
}

struct ProjectFilesSection: View {
    @State private var library = ProjectsLibrary.shared
    let projectID: String
    let artifacts: Bool
    @Binding var sheet: ProjectFileSheet?
    @Binding var error: String?
    let open: (URL) -> Void

    private var paths: [String] {
        guard let project = library.project(projectID) else { return [] }
        return artifacts ? project.artifacts : project.files
    }

    var body: some View {
        Group {
            if paths.isEmpty {
                Text(ProjectText.label(artifacts ? "No linked artifacts" : "No context files"))
                    .foregroundStyle(.secondary)
            }
            ForEach(paths, id: \.self) { path in
                fileRow(path)
            }
            Menu {
                Button(ProjectText.label("Choose from Space")) { sheet = artifacts ? .chooseArtifact : .chooseFile }
                Button(ProjectText.label(artifacts ? "Create an artifact" : "Import a file")) {
                    sheet = artifacts ? .createArtifact : .importFile
                }
            } label: {
                Label(ProjectText.label(artifacts ? "Add an artifact" : "Add a file"),
                      systemImage: artifacts ? "doc.badge.plus" : "paperclip")
            }
            if !artifacts && !paths.isEmpty {
                Text(ProjectText.label("Text and small PDFs can provide short excerpts to Noctis."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func fileRow(_ path: String) -> some View {
        let url = WorkspaceFiles.resolve(relativePath: path)
        return HStack {
            if let url {
                Button { open(url) } label: {
                    SpaceFileLabel(url: url, card: artifacts)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(filePath: path).lastPathComponent)
                    Text(ProjectText.label("File unavailable")).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                if let url {
                    ShareLink(item: url) { Label(ProjectText.label("Share"), systemImage: "square.and.arrow.up") }
                }
                Button { unlink(path) } label: { Label(ProjectText.label("Unlink"), systemImage: "link") }
            } label: {
                Label(ProjectText.label("File actions"), systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private func unlink(_ path: String) {
        do {
            try library.change(projectID) {
                if artifacts { $0.artifacts.removeAll { $0 == path } } else { $0.files.removeAll { $0 == path } }
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct ProjectTasksSection: View {
    @State private var library = ProjectsLibrary.shared
    @State private var draft = ""
    @State private var error: String?
    let projectID: String

    var body: some View {
        Group {
            ForEach(library.project(projectID)?.tasks ?? []) { task in
                Button {
                    update { project in
                        if let index = project.tasks.firstIndex(where: { $0.id == task.id }) {
                            project.tasks[index].isComplete.toggle()
                        }
                    }
                } label: {
                    Label {
                        Text(task.title).strikethrough(task.isComplete)
                    } icon: {
                        Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    }
                }
                .accessibilityValue(ProjectText.label(task.isComplete ? "Complete" : "Incomplete"))
                .swipeActions {
                    Button(ProjectText.label("Delete task"), role: .destructive) {
                        update { $0.tasks.removeAll { $0.id == task.id } }
                    }
                }
            }
            HStack {
                TextField(ProjectText.label("New task"), text: $draft).onSubmit(addTask)
                Button(action: addTask) {
                    Label(ProjectText.label("Add task"), systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .projectError($error)
    }

    private func addTask() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try library.change(projectID) { $0.tasks.append(ProjectTask(title: value)) }
            draft = ""
        } catch { self.error = error.localizedDescription }
    }

    private func update(_ edit: (inout WorkspaceProject) -> Void) {
        do { try library.change(projectID, edit) } catch { self.error = error.localizedDescription }
    }
}
#endif
