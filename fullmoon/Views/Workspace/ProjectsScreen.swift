#if os(iOS)
import SwiftData
import SwiftUI

enum ProjectText {
    static func label(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Projects")
    }
}

struct ProjectsScreen: View {
    @State private var library = ProjectsLibrary.shared
    @Query(sort: \Thread.timestamp, order: .reverse) private var threads: [Thread]
    @State private var showCreate = false
    @State private var path: [String] = []
    @Binding var projectToOpen: String?
    let onVisibleProjectChange: (String?) -> Void
    let onContinue: (Thread?, String) -> Void

    init(projectToOpen: Binding<String?> = .constant(nil),
         onVisibleProjectChange: @escaping (String?) -> Void = { _ in },
         onContinue: @escaping (Thread?, String) -> Void) {
        _projectToOpen = projectToOpen
        self.onVisibleProjectChange = onVisibleProjectChange
        self.onContinue = onContinue
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = library.readError {
                    ContentUnavailableView {
                        Label(ProjectText.label("Projects unavailable"), systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button(ProjectText.label("Try again")) { library.reload() }
                    }
                } else if library.projects.isEmpty {
                    ContentUnavailableView {
                        Label(ProjectText.label("Your projects"), systemImage: "folder")
                    } description: {
                        Text(ProjectText.label("Keep an ongoing conversation, its instructions and files together."))
                    } actions: {
                        Button(ProjectText.label("Create a project")) { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(projectRows) { row in
                                NavigationLink(value: row.id) { ProjectCard(row: row) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: 760)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(ProjectText.label("Projects"))
            .toolbar {
                if !library.projects.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showCreate = true } label: {
                            Label(ProjectText.label("Create a project"), systemImage: "plus")
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                ProjectDetailScreen(id: id, onContinue: onContinue)
            }
            .sheet(isPresented: $showCreate) {
                ProjectCreationSheet(onCreated: { path = [$0] })
            }
        }
        .onAppear(perform: openRequestedProject)
        .onChange(of: projectToOpen) { openRequestedProject() }
        .onChange(of: path.last, initial: true) { _, id in onVisibleProjectChange(id) }
    }

    private func openRequestedProject() {
        guard let id = projectToOpen else { return }
        projectToOpen = nil
        if library.project(id) != nil { path = [id] }
    }

    private var projectRows: [ProjectRow] {
        let linkedIDs = library.projects.reduce(into: Set<UUID>()) { $0.formUnion($1.threads) }
        let linked = threads.lazy.filter { linkedIDs.contains($0.id) }
        let activity = Dictionary(uniqueKeysWithValues: linked.map { ($0.id, $0.projectLastActivity) })
        return library.projects.map { project in
            let dates = project.threads.compactMap { activity[$0] }
            return ProjectRow(project: project, count: dates.count,
                              latest: max(project.updated, dates.max() ?? .distantPast))
        }
        .sorted { $0.latest > $1.latest }
    }
}

private struct ProjectRow: Identifiable {
    let project: WorkspaceProject
    let count: Int
    let latest: Date
    var id: String { project.id }
}

private struct ProjectCard: View {
    let row: ProjectRow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.tint)
                    .font(.title2.weight(.medium))
                Spacer()
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
            Text(row.project.title).font(.title3.weight(.semibold)).lineLimit(2)
            if !row.project.goal.isEmpty {
                Text(row.project.goal).foregroundStyle(.secondary).lineLimit(2)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    countLabel
                    Text("·").accessibilityHidden(true)
                    dateLabel
                }
                VStack(alignment: .leading) {
                    countLabel
                    dateLabel
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .contentShape(.rect(cornerRadius: 24))
    }

    private var countLabel: some View {
        Label {
            Text(row.count.formatted())
        } icon: {
            Image(systemName: "bubble.left.and.bubble.right")
        }
        .accessibilityLabel(ProjectText.label("Conversations") + " " + row.count.formatted())
    }

    private var dateLabel: some View {
        Text(row.latest, format: .dateTime.day().month().year())
    }
}

extension Thread {
    var projectLastActivity: Date { messages.lazy.map(\.timestamp).max() ?? timestamp }

    var projectDisplayTitle: String {
        title ?? sortedMessages.first(where: { $0.role == .user })?.content ?? String(localized: "chats.default_title")
    }
}
#endif
