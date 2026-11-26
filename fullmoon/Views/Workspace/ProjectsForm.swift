#if os(iOS)
import SwiftUI

struct ProjectCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let projectID: String?
    private let onCreated: (String) -> Void
    @State private var name: String
    @State private var goal: String
    @State private var instructions: String
    @State private var files: [String]
    @State private var choosingFile = false
    @State private var showImport = false
    @State private var error: String?

    init(project: WorkspaceProject? = nil, onCreated: @escaping (String) -> Void = { _ in }) {
        projectID = project?.id
        self.onCreated = onCreated
        _name = State(initialValue: project?.title ?? "")
        _goal = State(initialValue: project?.goal ?? "")
        _instructions = State(initialValue: project?.instructions ?? "")
        _files = State(initialValue: project?.files ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(ProjectText.label("Project name")) {
                    TextField(ProjectText.label("Name"), text: $name)
                }
                Section(ProjectText.label("Goal")) {
                    TextField(ProjectText.label("What would you like to achieve?"), text: $goal, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    TextField(ProjectText.label("How should Noctis help?"), text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text(ProjectText.label("Standing instructions"))
                } footer: {
                    Text(ProjectText.label("Used in conversations linked to this project."))
                }
                if projectID == nil {
                    Section(ProjectText.label("Context files")) {
                        ForEach(files, id: \.self) { path in
                            Label(URL(filePath: path).lastPathComponent, systemImage: "doc")
                        }
                        .onDelete { files.remove(atOffsets: $0) }
                        Menu {
                            Button(ProjectText.label("Choose from Space")) { choosingFile = true }
                            Button(ProjectText.label("Import a file")) { showImport = true }
                        } label: {
                            Label(ProjectText.label("Add a file"), systemImage: "paperclip")
                        }
                    }
                }
            }
            .navigationTitle(ProjectText.label(projectID == nil ? "New project" : "Edit project"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProjectText.label("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ProjectText.label(projectID == nil ? "Create" : "Save"), action: save)
                        .disabled(trimmed(name).isEmpty)
                }
            }
            .sheet(isPresented: $choosingFile) {
                WorkspaceItemPicker(section: .files, onPick: attach)
            }
            .sheet(isPresented: $showImport) {
                WorkspaceImportSheet(kind: .file, onImport: attach)
            }
            .projectError($error)
        }
    }

    private func attach(_ url: URL) {
        if let path = WorkspaceFiles.relativePath(for: url), !files.contains(path) { files.append(path) }
    }

    private func save() {
        do {
            if let projectID {
                try ProjectsLibrary.shared.change(projectID) { project in
                    project.title = trimmed(name)
                    project.goal = trimmed(goal)
                    project.instructions = trimmed(instructions)
                }
                dismiss()
            } else {
                let id = try ProjectsLibrary.shared.create(title: trimmed(name), goal: trimmed(goal),
                                                           instructions: trimmed(instructions), files: files)
                dismiss()
                onCreated(id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension View {
    func projectError(_ error: Binding<String?>) -> some View {
        alert(ProjectText.label("Couldn’t update project"), isPresented: Binding(
            get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button(ProjectText.label("OK"), role: .cancel) {}
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}
#endif
