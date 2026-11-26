#if os(iOS)
import Foundation
import SwiftUI
import UniformTypeIdentifiers

func spaceText(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, table: "Space")
}

enum WorkspaceSection: CaseIterable, Identifiable {
    case files, images, artifacts, code, connections
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .files: spaceText("Files")
        case .images: spaceText("Images")
        case .artifacts: spaceText("Artifacts")
        case .code: spaceText("Code")
        case .connections: spaceText("Connections")
        }
    }

    var symbol: String {
        switch self {
        case .files: "doc"
        case .images: "photo.on.rectangle"
        case .artifacts: "doc.richtext"
        case .code: "curlybraces"
        case .connections: "link"
        }
    }
}

enum WorkspaceImportKind: Identifiable {
    case file, image, artifact
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .file: spaceText("Import a file")
        case .image: spaceText("Import a photo")
        case .artifact: spaceText("Create an artifact")
        }
    }
}

/// Only relative names are stored by callers. The app container can move between launches.
enum WorkspaceFiles {
    static let didChange = Notification.Name("NoctisWorkspaceFilesDidChange")
    private static let manager = FileManager.default
    private static let root = URL.applicationSupportDirectory.resolvingSymlinksInPath()
        .appending(path: "NoctisWorkspace", directoryHint: .isDirectory)
    private static let imports = "Files"
    private static let artifacts = "Artifacts"
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "webp", "avif", "dng"
    ]
    private static let codeExtensions: Set<String> = [
        "c", "cpp", "cs", "css", "go", "h", "hpp", "html", "java", "js", "json", "jsx", "kt", "kts",
        "m", "mm", "py", "rb", "rs", "sh", "sql", "swift", "ts", "tsx", "xml", "yaml", "yml", "zsh"
    ]

    static func type(of url: URL) -> UTType {
        UTType(filenameExtension: url.pathExtension) ?? .data
    }

    static func isImage(_ url: URL) -> Bool {
        type(of: url).conforms(to: .image) || imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isCode(_ url: URL) -> Bool {
        codeExtensions.contains(url.pathExtension.lowercased()) || type(of: url).conforms(to: .sourceCode)
    }

    static func relativePath(for url: URL) -> String? {
        let container = url.resolvingSymlinksInPath().deletingLastPathComponent()
        let directory = container.deletingLastPathComponent().standardizedFileURL
        let parent = directory.deletingLastPathComponent().standardizedFileURL
        guard UUID(uuidString: container.lastPathComponent) != nil,
              [imports, artifacts].contains(directory.lastPathComponent),
              parent.path == root.resolvingSymlinksInPath().standardizedFileURL.path
        else { return nil }
        return [directory.lastPathComponent, container.lastPathComponent, url.lastPathComponent].joined(separator: "/")
    }

    static func resolve(relativePath: String) -> URL? {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, [imports, artifacts].contains(parts[0]),
              UUID(uuidString: parts[1]) != nil, !parts[2].isEmpty, !parts[2].hasPrefix(".") else { return nil }
        let url = parts.reduce(root) { $0.appending(component: $1) }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return url
    }

    static func items(in section: WorkspaceSection) throws -> [URL] {
        guard section != .connections else { return [] }
        let directory = root.appending(component: section == .artifacts ? artifacts : imports)
        guard manager.fileExists(atPath: directory.path) else { return [] }
        let containers = try manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls = try containers.filter { UUID(uuidString: $0.lastPathComponent) != nil }.flatMap {
            try manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        }
        return urls.filter {
            guard (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            switch section {
            case .images: return isImage($0)
            case .code: return isCode($0)
            default: return true
            }
        }.sorted { lhs, rhs in
            let left = modificationDate(of: lhs) ?? .distantPast
            let right = modificationDate(of: rhs) ?? .distantPast
            return left == right ? lhs.path < rhs.path : left > right
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func importFile(from source: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { try copyFile(from: source) }.value
    }

    /// Photos hands us a private temporary copy valid only inside its completion handler.
    static func importPhoto(from source: URL, named name: String) throws -> URL {
        try copyRegularFile(from: source, named: name)
    }

    private static func copyFile(from source: URL) throws -> URL {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let temporaryPath = manager.temporaryDirectory.standardizedFileURL.path + "/"
        if source.standardizedFileURL.path.hasPrefix(temporaryPath) {
            return try copyRegularFile(from: source, named: source.lastPathComponent)
        }
        var coordinationError: NSError?
        var outcome: Result<URL, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { localURL in
            outcome = Result { try copyRegularFile(from: localURL, named: source.lastPathComponent) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        return try outcome.get()
    }

    private static func copyRegularFile(from url: URL, named name: String) throws -> URL {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return try store(name: name, in: imports) { try manager.copyItem(at: url, to: $0) }
    }

    static func createArtifact(title: String, body: String) throws -> URL {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.lowercased().hasSuffix(".md") { name += ".md" }
        return try store(name: name, in: artifacts) { try Data(body.utf8).write(to: $0, options: .atomic) }
    }

    private static func store(name: String, in folder: String, write: (URL) throws -> Void) throws -> URL {
        let directory = root.appending(component: folder, directoryHint: .isDirectory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let itemID = UUID().uuidString
        let staging = directory.appending(component: "." + itemID, directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let components = name.components(separatedBy: unsafe).filter { !$0.isEmpty }
        let cleaned = components.joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.newlines))
        guard !cleaned.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        try write(staging.appending(component: cleaned))
        let container = directory.appending(component: itemID, directoryHint: .isDirectory)
        try manager.moveItem(at: staging, to: container)
        let destination = container.appending(component: cleaned)
        notify()
        return destination
    }

    static func delete(_ url: URL) throws {
        guard let path = relativePath(for: url), let stored = resolve(relativePath: path) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try manager.removeItem(at: stored.deletingLastPathComponent())
        notify()
    }

    private static func notify() {
        Task { @MainActor in NotificationCenter.default.post(name: didChange, object: nil) }
    }
}
#endif
