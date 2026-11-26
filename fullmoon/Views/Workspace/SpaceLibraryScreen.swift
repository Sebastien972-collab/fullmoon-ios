#if os(iOS)
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceLibraryScreen: View {
    @Environment(AppManager.self) private var appManager
    @State private var localSection: WorkspaceSection
    private let routedSection: Binding<WorkspaceSection>?
    private let sections: [WorkspaceSection]
    private let onClose: (() -> Void)?
    @State private var items: [URL] = []
    @State private var importKind: WorkspaceImportKind?
    @State private var preview: URL?
    @State private var textPreview: URL?
    @State private var pendingDeletion: [URL] = []
    @State private var selecting = false
    @State private var selected: Set<URL> = []
    @State private var failure: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(section: WorkspaceSection = .files, sections: [WorkspaceSection] = WorkspaceSection.allCases,
         onClose: (() -> Void)? = nil) {
        _localSection = State(initialValue: section)
        routedSection = nil
        self.sections = sections
        self.onClose = onClose
    }

    init(section: Binding<WorkspaceSection>) {
        _localSection = State(initialValue: section.wrappedValue)
        routedSection = section
        sections = WorkspaceSection.allCases
        onClose = nil
    }

    private var section: WorkspaceSection {
        get { routedSection?.wrappedValue ?? localSection }
        nonmutating set {
            if let routedSection { routedSection.wrappedValue = newValue } else { localSection = newValue }
        }
    }

    private var creation: WorkspaceImportKind {
        switch section {
        case .images: .image
        case .artifacts: .artifact
        default: .file
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker
                content
                if selecting { selectionBar }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(appManager.appearance.theme.background)
            .navigationTitle(spaceText("Library"))
            .toolbar { libraryTools }
            .onAppear(perform: reload)
            .onChange(of: section) {
                selecting = false
                selected.removeAll()
                reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: WorkspaceFiles.didChange)) { _ in reload() }
            .quickLookPreview($preview)
            .sheet(item: $importKind, onDismiss: reload) { WorkspaceImportSheet(kind: $0) }
            .sheet(isPresented: Binding(get: { textPreview != nil }, set: { if !$0 { textPreview = nil } })) {
                if let textPreview { SpaceTextPreview(url: textPreview) }
            }
            .confirmationDialog(spaceText("Delete the selected files from Space?"), isPresented: Binding(
                get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }
            ), titleVisibility: .visible) {
                Button(spaceText("Delete"), role: .destructive, action: deleteSelection)
            } message: {
                Text(spaceText("Projects that use these files will lose access to them."))
            }
            .alert(spaceText("Couldn’t open Space"), isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) { Button(spaceText("Close")) { failure = nil } } message: { Text(failure ?? "") }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(sections) { item in
                    Button { section = item } label: {
                        Text(item.title)
                            .font(.subheadline.weight(section == item ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if section == item { Capsule().fill(.primary.opacity(0.09)) }
                            }
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(section == item ? .primary : .secondary)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var content: some View {
        if section == .connections {
            SpaceConnections()
        } else if items.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: section.symbol)
            } actions: {
                Button { importKind = creation } label: { Text(creation.title) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                if section == .images || section == .artifacts {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 230 : 146))],
                              spacing: 16) {
                        ForEach(items, id: \.self) { fileButton($0, card: true) }
                    }
                    .padding(20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(items, id: \.self) { url in
                            fileButton(url, card: false)
                            Divider().accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var emptyTitle: LocalizedStringResource {
        switch section {
        case .images: spaceText("No images yet")
        case .artifacts: spaceText("No artifacts yet")
        case .code: spaceText("No code files yet")
        default: spaceText("No files yet")
        }
    }

    @ToolbarContentBuilder private var libraryTools: some ToolbarContent {
        if let onClose {
            ToolbarItem(placement: .cancellationAction) {
                Button(spaceText("Close"), action: onClose)
            }
        }
        if section == .images && !items.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? spaceText("Done") : spaceText("Select")) {
                    selecting.toggle()
                    selected.removeAll()
                }
            }
        }
        if section != .connections && !items.isEmpty && !selecting {
            ToolbarItem(placement: .primaryAction) {
                Button { importKind = creation } label: { Label(creation.title, systemImage: "plus") }
            }
        }
    }

    private func fileButton(_ url: URL, card: Bool) -> some View {
        Button {
            if selecting {
                if !selected.insert(url).inserted { selected.remove(url) }
            } else {
                open(url)
            }
        } label: {
            SpaceFileLabel(url: url, card: card)
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selected.contains(url) ? "checkmark.circle.fill" : "circle")
                            .symbolRenderingMode(.palette).foregroundStyle(.tint, .background)
                            .font(.title2).padding(8)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected.contains(url) ? .isSelected : [])
        .contextMenu {
            Button(spaceText("Open"), systemImage: "arrow.up.right.square") { open(url) }
            ShareLink(item: url) { Label(spaceText("Share or export"), systemImage: "square.and.arrow.up") }
            Button(spaceText("Delete"), systemImage: "trash", role: .destructive) { pendingDeletion = [url] }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 20) {
            ShareLink(items: items.filter(selected.contains)) {
                Label(spaceText("Share or export"), systemImage: "square.and.arrow.up")
            }
            Spacer()
            Button(spaceText("Delete"), systemImage: "trash", role: .destructive) { pendingDeletion = Array(selected) }
        }
        .labelStyle(.iconOnly)
        .frame(minHeight: 44)
        .disabled(selected.isEmpty)
        .padding(.horizontal, 20)
    }

    private func open(_ url: URL) {
        if WorkspaceFiles.isCode(url) || section == .artifacts { textPreview = url } else { preview = url }
    }

    private func reload() {
        do {
            items = try WorkspaceFiles.items(in: section)
            selected.formIntersection(items)
        } catch { failure = error.localizedDescription }
    }

    private func deleteSelection() {
        do {
            for url in pendingDeletion { try WorkspaceFiles.delete(url) }
        } catch { failure = error.localizedDescription }
        pendingDeletion = []
        selected.removeAll()
        selecting = false
        reload()
    }
}

private struct SpaceConnections: View {
    var body: some View {
        List {
            Section {
                ForEach(["GitHub", "Notion", "Google Drive"], id: \.self) { service in
                    LabeledContent {
                        Text(spaceText("Not connected")).font(.subheadline).foregroundStyle(.secondary)
                    } label: {
                        Text(verbatim: service)
                    }
                }
            } footer: {
                Text(spaceText("Third-party connections are planned for a future version."))
            }
        }
        .listStyle(.insetGrouped)
    }
}
#endif
