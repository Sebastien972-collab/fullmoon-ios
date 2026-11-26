#if os(iOS)
import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers

/// Device-local organization of the existing chat threads and workspace files.
struct WorkspaceProject: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    var title: String
    var goal: String
    var instructions: String
    var updated = Date()
    var threads: Set<UUID> = []
    var files: [String] = []
    var artifacts: [String] = []
    var tasks: [ProjectTask] = []
}

struct ProjectTask: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var isComplete = false
}

@MainActor
@Observable
final class ProjectsLibrary {
    static let shared = ProjectsLibrary()
    private(set) var projects: [WorkspaceProject] = []
    private(set) var readError: Error?
    private let storageURL: URL

    private init() {
        storageURL = URL.applicationSupportDirectory
            .appending(path: "NoctisProjects", directoryHint: .isDirectory)
            .appending(path: "projects.plist")
        reload()
    }

    func reload() {
        do {
            projects = try PropertyListDecoder().decode([WorkspaceProject].self, from: Data(contentsOf: storageURL))
            readError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            projects = []
            readError = nil
        } catch {
            readError = error
        }
    }

    private func write(_ next: [WorkspaceProject]) throws {
        if let readError { throw readError }
        var folder = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var options = URLResourceValues()
        options.isExcludedFromBackup = true
        try folder.setResourceValues(options)
        let data = try PropertyListEncoder().encode(next)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        projects = next
    }

    var recentProjects: [(id: String, title: String)] {
        projects.sorted { $0.updated > $1.updated }.prefix(3).map { ($0.id, $0.title) }
    }

    func project(_ id: String) -> WorkspaceProject? {
        projects.first { $0.id == id }
    }

    func projectID(for threadID: UUID) -> String? {
        projects.first { $0.threads.contains(threadID) }?.id
    }

    func title(for id: String) -> String? { project(id)?.title }

    @discardableResult
    func create(title: String, goal: String, instructions: String, files: [String]) throws -> String {
        var project = WorkspaceProject(title: title, goal: goal, instructions: instructions)
        project.files = files
        try write(projects + [project])
        return project.id
    }

    func change(_ id: String, _ edit: (inout WorkspaceProject) -> Void) throws {
        var next = projects
        guard let index = next.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        edit(&next[index])
        next[index].updated = .now
        try write(next)
    }

    func remove(_ id: String) throws {
        try write(projects.filter { $0.id != id })
    }

    func link(threadID: UUID, to id: String) throws {
        if projectID(for: threadID) == id { return }
        var next = projects
        guard let index = next.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        for other in next.indices where next[other].threads.remove(threadID) != nil {
            next[other].updated = .now
        }
        next[index].threads.insert(threadID)
        next[index].updated = .now
        try write(next)
    }

    func context(for threadID: UUID) async -> String {
        guard let project = projects.first(where: { $0.threads.contains(threadID) }) else { return "" }
        let reading = Task.detached(priority: .userInitiated) { Self.contextSnapshot(project) }
        return await withTaskCancellationHandler {
            await reading.value
        } onCancel: {
            reading.cancel()
        }
    }

    nonisolated private static func contextSnapshot(_ project: WorkspaceProject) -> String {
        var payload = [
            "project": String(project.title.prefix(200)),
            "objective": String(project.goal.prefix(1500)),
            "preferences": String(project.instructions.prefix(2500))
        ]
        var remaining = 4800
        for (index, path) in project.files.enumerated() {
            guard !Task.isCancelled else { return "" }
            guard remaining > 0 else { break }
            guard let url = WorkspaceFiles.resolve(relativePath: path),
                  let excerpt = Self.excerpt(from: url, limit: min(1600, remaining)), !excerpt.isEmpty else { continue }
            payload["file \(index + 1): \(url.lastPathComponent)"] = excerpt
            remaining -= excerpt.count
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func excerpt(from url: URL, limit: Int) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  bytes <= 2_000_000, let pdf = PDFDocument(url: url) else { return nil }
            var excerpt = ""
            for page in 0..<min(3, pdf.pageCount) where excerpt.count < limit {
                if let text = pdf.page(at: page)?.string {
                    excerpt += String(text.prefix(limit - excerpt.count)) + "\n"
                }
            }
            return String(excerpt.prefix(limit))
        }
        let type = WorkspaceFiles.type(of: url)
        let textExtensions = ["txt", "md", "markdown", "log", "csv", "tsv", "toml", "ini", "conf"]
        guard WorkspaceFiles.isCode(url) || type.conforms(to: .text) || type.conforms(to: .json)
                || textExtensions.contains(url.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit * 4) else { return nil }
        // A bounded read can end inside a UTF-8 scalar. Trim only its partial suffix.
        for trim in 0...min(3, data.count) {
            if let value = String(bytes: data.dropLast(trim), encoding: .utf8) {
                return String(value.prefix(limit))
            }
        }
        return nil
    }
}
#endif
