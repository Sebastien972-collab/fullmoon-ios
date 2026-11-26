import Foundation

/// A presentation snapshot of a conversation owned and stored by the host.
public struct NoctisConversationSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let preview: String
    public let searchText: String

    public init(id: UUID, title: String, preview: String, searchText: String? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.searchText = searchText ?? "\(title)\n\(preview)"
    }
}
