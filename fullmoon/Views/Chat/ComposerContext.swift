#if os(iOS)
import NoctisChatUI
import SwiftUI

enum ComposerAction { case voice, handsFree, photo, camera, file, context }

enum ChatInputOrigin { case keyboard, dictation, handsFree }

struct ComposerDraftKey: Equatable {
    let location: ComposerDrafts.Location
    let text: String
}

extension EnvironmentValues {
    @Entry var handsFreeConversation: HandsFreeConversation?
    @Entry var composerRequest: Binding<ComposerAction?>?
    @Entry var composerProjectTitle: String?
    @Entry var composerThreadID: UUID?
    @Entry var composerDrafts: ComposerDrafts?
    @Entry var composerIsWorkspaceDraft = false
}

final class ComposerDrafts {
    enum Location: Hashable { case workspace, thread(UUID), newThread(project: String?) }
    struct Draft {
        var attachments: [ComposerAttachmentContent]
        var style: ComposerStyle
    }
    var values: [Location: Draft] = [:]
}

enum ComposerStyle: CaseIterable {
    case standard, concise, steps

    var label: String {
        switch self {
        case .standard: composerCopy("Automatic")
        case .concise: composerCopy("Concise")
        case .steps: composerCopy("Step by step")
        }
    }

    var instruction: String? {
        switch self {
        case .standard: nil
        case .concise: composerCopy("Give a concise answer.")
        case .steps: composerCopy("Explain your answer step by step.")
        }
    }
}

struct ComposerActionsMenu: View {
    let canStartConversation: Bool
    let present: (ComposerAction) -> Void

    var body: some View {
        Menu {
            Button { present(.file) } label: { Label(composerCopy("Attach a document"), systemImage: "doc") }
            Button { present(.photo) } label: { Label(composerCopy("Read text from a photo"), systemImage: "photo") }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { present(.camera) } label: { Label(composerCopy("Scan with camera"), systemImage: "camera") }
            }
            Section {
                Button { present(.context) } label: {
                    Label(composerCopy("Conversation context"), systemImage: "slider.horizontal.3")
                }
                Button { present(.handsFree) } label: {
                    Label(composerCopy("Hands-free conversation"), systemImage: "waveform.circle")
                }
                .disabled(!canStartConversation)
                Button { present(.voice) } label: { Label(composerCopy("Voice input"), systemImage: "mic") }
            }
        } label: {
            NoctisIcon(.plus, size: 20).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(composerCopy("Attach or dictate"))
    }
}

struct ComposerContextPanel: View {
    let modelName: String
    let projectTitle: String?
    let attachments: [ComposerAttachmentContent]
    @Binding var style: ComposerStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(composerCopy("Context")) {
                    LabeledContent(composerCopy("Model"), value: modelName)
                    if let projectTitle { LabeledContent(composerCopy("Project"), value: projectTitle) }
                    Picker(composerCopy("Answer style"), selection: $style) {
                        ForEach(ComposerStyle.allCases, id: \.self) { style in Text(verbatim: style.label).tag(style) }
                    }
                }
                Section {
                    if attachments.isEmpty {
                        Text(composerCopy("No attachments")).foregroundStyle(.secondary)
                    } else {
                        ForEach(attachments) { item in
                            DisclosureGroup(item.name) {
                                Text(verbatim: item.text).font(.footnote).textSelection(.enabled)
                            }
                        }
                    }
                } header: { Text(composerCopy("Attachments")) } footer: {
                    Text(composerCopy("Noctis reads the text extracted on this device from your images and documents."))
                }
            }
            .modifier(ThemedForm())
            .navigationTitle(composerCopy("Conversation context"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(composerCopy("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#endif
