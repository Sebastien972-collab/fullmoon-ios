#if os(iOS)
import SwiftUI

func workspaceText(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, table: "Workspace")
}

enum WorkspaceTab: Int, CaseIterable {
    case home, projects, space, settings

    var title: LocalizedStringResource {
        switch self {
        case .home: workspaceText("Home")
        case .projects: workspaceText("Projects")
        case .space: workspaceText("Space")
        case .settings: workspaceText("Settings")
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .projects: "folder"
        case .space: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }
}

enum WorkspaceCreation: CaseIterable {
    case chat, project, photo, file, voice, artifact

    var title: LocalizedStringResource {
        switch self {
        case .chat: workspaceText("New conversation")
        case .project: workspaceText("New project")
        case .photo: workspaceText("Read text from an image")
        case .file: workspaceText("Import a file")
        case .voice: workspaceText("Dictate a message")
        case .artifact: workspaceText("Create an artifact")
        }
    }

    var icon: String {
        switch self {
        case .chat: "square.and.pencil"
        case .project: "folder.badge.plus"
        case .photo: "text.viewfinder"
        case .file: "doc.badge.plus"
        case .voice: "waveform"
        case .artifact: "doc.richtext"
        }
    }
}

enum WorkspaceShortcut: String, CaseIterable, Identifiable {
    case code, summarize, translate, project
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .code: workspaceText("Explain code")
        case .summarize: workspaceText("Summarize a page")
        case .translate: workspaceText("Translate")
        case .project: workspaceText("Create a project")
        }
    }

    var icon: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .summarize: "text.alignleft"
        case .translate: "translate"
        case .project: "folder.badge.plus"
        }
    }

    var prompt: LocalizedStringResource {
        switch self {
        case .code: workspaceText("Explain this code step by step:")
        case .summarize: workspaceText("Summarize the main points of this page:")
        case .translate: workspaceText("Translate the following text into ")
        case .project: title
        }
    }
}

struct WorkspaceCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (WorkspaceCreation) -> Void

    var body: some View {
        NavigationStack {
            List(WorkspaceCreation.allCases, id: \.self) { action in
                Button { onSelect(action) } label: {
                    Label { Text(action.title).foregroundStyle(.primary) } icon: { Image(systemName: action.icon) }
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle(Text(workspaceText("Create")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
#endif
