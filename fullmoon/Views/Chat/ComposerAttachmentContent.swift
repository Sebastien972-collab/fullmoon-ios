import Foundation

struct ComposerAttachmentContent: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let text: String

    private struct Entry: Codable { let name: String; let text: String }
    private static let heading = "\n\n--- Attached texts (JSON) ---\n"

    static func combine(_ prompt: String, with attachments: [Self]) throws -> String {
        guard !attachments.isEmpty else { return prompt }
        let entries = attachments.map { Entry(name: $0.name, text: $0.text) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(entries)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return prompt + heading + json
    }

    static func split(_ content: String) -> (prompt: String, attachments: [Self]) {
        guard let separator = content.range(of: heading, options: .backwards),
              let entries = try? JSONDecoder().decode([Entry].self, from: Data(content[separator.upperBound...].utf8)),
              (1...3).contains(entries.count) else { return (content, []) }
        return (String(content[..<separator.lowerBound]), entries.map { Self(name: $0.name, text: $0.text) })
    }
}
