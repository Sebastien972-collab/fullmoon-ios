// Created by Sébastien DAGUIN

import Foundation
import Noctis
import SwiftData

@MainActor
final class NoctisIdentitySession {
    private var threadID: UUID?
    private var personalContext = ""

    func changed(thread: UUID, in context: ModelContext) throws -> Bool {
        try threadID != thread || personalContext != NoctisUserIdentity.promptContext(in: context)
    }

    func reset(_ service: any AIModelService, history: [AIChatMessage], in context: ModelContext) async throws {
        let personal = try NoctisUserIdentity.promptContext(in: context)
        let contextualHistory = personal.isEmpty ? history : [.init(role: .system, content: personal)] + history
        try await service.resetConversation(history: contextualHistory)
        // Retain the exact context sent, even if the profile changes during the await.
        personalContext = personal
    }

    func confirm(thread: UUID) { threadID = thread }
}
