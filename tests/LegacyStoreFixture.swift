// Created by Sébastien DAGUIN

import Foundation
import SwiftData

enum Role: String, Codable { case assistant, user, system }

@Model final class Thread {
    @Attribute(.unique) var id: UUID
    var title: String?
    var timestamp: Date
    @Relationship var messages: [Message] = []
    init() { id = UUID(); timestamp = Date() }
}

@Model final class Message {
    @Attribute(.unique) var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var generatingTime: TimeInterval?
    var isInterrupted: Bool = false
    var hasError: Bool = false
    @Relationship(inverse: \Thread.messages) var thread: Thread?
    init(role: Role, content: String) {
        id = UUID(); self.role = role; self.content = content; timestamp = Date()
    }
}

@Model final class NoctisUserProfile {
    var identifier: UUID = UUID()
    var displayName: String = ""
    var preferredName: String = ""
    var preferredLanguage: String = "fr"
    var personalInstructions: String = ""
    var updatedAt: Date = Date()
    init() {}
}

@main struct LegacyStoreFixture {
    @MainActor static func main() throws {
        let schema = Schema([Thread.self, Message.self, NoctisUserProfile.self])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]),
                                               cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let thread = Thread()
        thread.title = "Legacy conversation"
        context.insert(thread)
        for (role, text) in [(Role.user, "Legacy question"), (.assistant, "Legacy answer")] {
            let message = Message(role: role, content: text)
            context.insert(message)
            message.thread = thread
        }
        let profile = NoctisUserProfile()
        profile.displayName = "Legacy test profile"
        context.insert(profile)
        try context.save()
        print("Legacy store fixture created")
    }
}
