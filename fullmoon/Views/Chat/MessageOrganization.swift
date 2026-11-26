import SwiftUI
import UniformTypeIdentifiers

/// Archive and pin preferences belong to this installation; shared transcripts stay intact.
enum ConversationArchive {
    static let pinsKey = "noctis.history.pinnedMessages"
    static let storageKey = "noctis.history.archivedIDs"

    static func contains(_ id: UUID, in value: String) -> Bool {
        value.split(separator: "\n").contains(Substring(id.uuidString))
    }

    static func removing(_ ids: Set<UUID>, from value: String) -> String {
        let removed = Set(ids.map(\.uuidString))
        return value.split(separator: "\n").filter { !removed.contains(String($0)) }.joined(separator: "\n")
    }

    static func setting(_ id: UUID, included: Bool, in value: String) -> String {
        var entries = Set(value.split(separator: "\n").map(String.init))
        if included {
            entries.insert(id.uuidString)
        } else {
            entries.remove(id.uuidString)
        }
        return entries.sorted().joined(separator: "\n")
    }
}

extension Message {
    var previewText: String {
        guard role == .user else { return content }
        let parts = ComposerAttachmentContent.split(content)
        return ([parts.prompt] + parts.attachments.map(\.name)).joined(separator: " · ")
    }

    var shareableText: String {
        guard role == .user else { return content }
        let parts = ComposerAttachmentContent.split(content)
        guard !parts.attachments.isEmpty else { return content }
        let excerpts = parts.attachments.map { "\($0.name)\n\n\($0.text)" }
        return ([parts.prompt] + excerpts).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

struct ConversationTranscript: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "md") ?? .plainText] }
    let content: String

    init(content: String) {
        self.content = content
    }

    init(_ thread: Thread) {
        let title = thread.title ?? thread.sortedMessages.first.map { String($0.previewText.prefix(70)) }
            ?? String(localized: "chats.default_title")
        let transcript = thread.sortedMessages.map { message in
            let role: String = switch message.role {
            case .user: String(localized: "message.author.user")
            case .assistant: String(localized: "message.author.assistant")
            case .system: String(localized: "System", table: "MessageActions")
            }
            return "## \(role)\n\n\(message.shareableText)"
        }
        content = (["# \(title)"] + transcript).joined(separator: "\n\n")
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        content = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}
