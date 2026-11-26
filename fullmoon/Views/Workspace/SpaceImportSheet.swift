#if os(iOS)
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: WorkspaceImportKind
    var onImport: ((URL) -> Void)?
    @State private var title = ""
    @State private var content = ""
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        Group {
            if busy {
                ProgressView(spaceText("Saving to your Space…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure {
                ContentUnavailableView {
                    Label(spaceText("Couldn’t save the item"), systemImage: "exclamationmark.circle")
                } description: {
                    Text(failure)
                } actions: {
                    Button(spaceText("Try again")) { self.failure = nil }
                    Button(spaceText("Close")) { dismiss() }
                }
            } else {
                switch kind {
                case .file:
                    SpaceDocumentPicker { source in
                        guard let source else { dismiss(); return }
                        busy = true
                        Task {
                            do {
                                finish(try await WorkspaceFiles.importFile(from: source))
                            } catch { report(error) }
                        }
                    }
                    .ignoresSafeArea()
                case .image:
                    SpacePhotoPicker(onCancel: { dismiss() }, onStart: { busy = true }, onResult: { result in
                        switch result {
                        case .success(let url): finish(url)
                        case .failure(let error): report(error)
                        }
                    })
                    .ignoresSafeArea()
                case .artifact:
                    editor
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private var editor: some View {
        NavigationStack {
            Form {
                TextField(spaceText("Title"), text: $title)
                Section(spaceText("Markdown")) {
                    TextEditor(text: $content)
                        .accessibilityLabel(spaceText("Artifact content"))
                        .font(.body)
                        .frame(minHeight: 180)
                }
            }
            .modifier(ThemedForm())
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(spaceText("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(spaceText("Create")) {
                        do {
                            finish(try WorkspaceFiles.createArtifact(title: title, body: content))
                        } catch { report(error) }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func finish(_ url: URL) {
        dismiss()
        onImport?(url)
    }

    private func report(_ error: Error) {
        busy = false
        failure = error.localizedDescription
    }
}

private struct SpaceDocumentPicker: UIViewControllerRepresentable {
    let onResult: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onResult: (URL?) -> Void
        init(onResult: @escaping (URL?) -> Void) { self.onResult = onResult }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onResult(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onResult(urls.first)
        }
    }
}

private struct SpacePhotoPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onStart: () -> Void
    let onResult: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SpacePhotoPicker
        init(parent: SpacePhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { parent.onCancel(); return }
            guard let imageType = provider.registeredTypeIdentifiers.compactMap({ UTType($0) })
                .first(where: { $0.conforms(to: .image) }) else {
                parent.onResult(.failure(CocoaError(.fileReadUnknown)))
                return
            }

            var name = provider.suggestedName ?? String(localized: "Photo", table: "Space")
            if URL(fileURLWithPath: name).pathExtension.isEmpty, let suffix = imageType.preferredFilenameExtension {
                name += "." + suffix
            }
            let fileName = name
            let deliver = parent.onResult
            parent.onStart()
            provider.loadFileRepresentation(forTypeIdentifier: imageType.identifier) { url, error in
                let result: Result<URL, Error> = Result {
                    if let error { throw error }
                    guard let url else { throw CocoaError(.fileReadUnknown) }
                    return try WorkspaceFiles.importPhoto(from: url, named: fileName)
                }
                Task { @MainActor in deliver(result) }
            }
        }
    }
}
#endif
