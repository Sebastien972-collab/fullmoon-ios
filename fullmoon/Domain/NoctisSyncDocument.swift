// Created by Sébastien DAGUIN

import CryptoKit
import Foundation

struct NoctisProfileSnapshot: Codable, Equatable, Sendable {
    var displayName = ""
    var givenName = ""
    var familyName = ""
    var preferredName = ""
    var preferredLanguage = "fr"
    var profession = ""
    var personalInstructions = ""
    var personalInformation = ""
    var personalizationEnabled = false
    var allowName = false
    var allowLanguage = false
    var allowProfession = false
    var allowInstructions = false
    var allowPersonalInformation = false

    @MainActor init(profile: NoctisUserProfile) {
        displayName = profile.displayName
        givenName = profile.givenName
        familyName = profile.familyName
        preferredName = profile.preferredName
        preferredLanguage = profile.preferredLanguage
        profession = profile.profession
        personalInstructions = profile.personalInstructions
        personalInformation = profile.personalInformation
        personalizationEnabled = profile.personalizationEnabled
        allowName = profile.allowName
        allowLanguage = profile.allowLanguage
        allowProfession = profile.allowProfession
        allowInstructions = profile.allowInstructions
        allowPersonalInformation = profile.allowPersonalInformation
    }

    init() {}

    @MainActor func apply(to profile: NoctisUserProfile) {
        profile.displayName = displayName
        profile.givenName = givenName
        profile.familyName = familyName
        profile.preferredName = preferredName
        profile.preferredLanguage = preferredLanguage
        profile.profession = profession
        profile.personalInstructions = personalInstructions
        profile.personalInformation = personalInformation
        profile.personalizationEnabled = personalizationEnabled
        profile.allowName = allowName
        profile.allowLanguage = allowLanguage
        profile.allowProfession = allowProfession
        profile.allowInstructions = allowInstructions
        profile.allowPersonalInformation = allowPersonalInformation
        profile.updatedAt = Date()
    }
}

struct NoctisMessageSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var generatingTime: TimeInterval?
    var isInterrupted: Bool
    var hasError: Bool
}

struct NoctisThreadSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var title: String?
    var timestamp: Date
    var messages: [NoctisMessageSnapshot]
    var deletedMessages: [UUID] = []

    func merged(with other: Self, preferSelf: Bool) -> Self {
        var result = preferSelf ? self : other
        result.deletedMessages = Array(Set(deletedMessages + other.deletedMessages))
            .sorted { $0.uuidString < $1.uuidString }
        let first = preferSelf ? other : self
        let last = preferSelf ? self : other
        var messages = Dictionary(uniqueKeysWithValues: first.messages.map { ($0.id, $0) })
        for message in last.messages { messages[message.id] = message }
        result.messages = messages.values.filter { !result.deletedMessages.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return result
    }

    func conflicts(with other: Self) -> Bool {
        let values = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        return title != other.title || other.messages.contains { message in
            values[message.id].map { $0 != message } ?? false
        }
    }
}

struct NoctisSyncDocument: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case conversation, profile }
    var id: String
    var kind: Kind
    var modifiedAt: Date
    var author: String
    var deleted: Bool
    var payload: Data
    var profileConflicts: [Data] = []

    static func serialize<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    func validate() throws {
        guard !deleted || (payload.isEmpty && profileConflicts.isEmpty) else { throw NoctisSyncError.invalidData }
        if kind == .profile {
            guard id == "profile" else { throw NoctisSyncError.invalidData }
            if !deleted { _ = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: payload) }
            for value in profileConflicts { _ = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: value) }
        } else {
            guard profileConflicts.isEmpty else { throw NoctisSyncError.invalidData }
            guard id.hasPrefix("conversation-"), UUID(uuidString: String(id.dropFirst(13))) != nil else {
                throw NoctisSyncError.invalidData
            }
            if !deleted {
                let thread = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: payload)
                guard id == "conversation-\(thread.id.uuidString)",
                      Set(thread.messages.map(\.id)).count == thread.messages.count,
                      thread.messages.allSatisfy({ ["user", "assistant", "system"].contains($0.role) }) else {
                    throw NoctisSyncError.invalidData
                }
            }
        }
    }

    func isPreferred(to other: Self) -> Bool {
        if modifiedAt != other.modifiedAt { return modifiedAt > other.modifiedAt }
        if author != other.author { return author > other.author }
        return payload.lexicographicallyPrecedes(other.payload)
    }

    static func stableID(for data: Data) -> UUID {
        let bytes = Array(SHA256.hash(data: data).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    static func accountFingerprint(_ account: String) -> String {
        SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct NoctisSyncResolution: Sendable {
    var document: NoctisSyncDocument
    var conflict: NoctisSyncDocument?

    static func resolve(local: NoctisSyncDocument, remote: NoctisSyncDocument) throws -> Self {
        try local.validate()
        try remote.validate()
        guard local.id == remote.id, local.kind == remote.kind else { throw NoctisSyncError.invalidData }
        // Tombstones dominate edits, preventing a disconnected device from resurrecting deletions.
        if local.deleted || remote.deleted {
            let deleted = local.deleted && remote.deleted
                ? (local.isPreferred(to: remote) ? local : remote) : (local.deleted ? local : remote)
            return Self(document: deleted)
        }
        let preferLocal = local.isPreferred(to: remote)
        var winner = preferLocal ? local : remote
        let loser = preferLocal ? remote : local
        if local.kind == .conversation {
            let lhs = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: local.payload)
            let rhs = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: remote.payload)
            guard lhs.id == rhs.id else { throw NoctisSyncError.invalidData }
            winner.payload = try NoctisSyncDocument.serialize(lhs.merged(with: rhs, preferSelf: preferLocal))
            return Self(document: winner, conflict: lhs.conflicts(with: rhs) ? loser : nil)
        }
        let lhs = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: local.payload)
        let rhs = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: remote.payload)
        var profile = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: winner.payload)
        // Concurrent revocations dominate grants, even when device clocks differ.
        profile.personalizationEnabled = lhs.personalizationEnabled && rhs.personalizationEnabled
        profile.allowName = lhs.allowName && rhs.allowName
        profile.allowLanguage = lhs.allowLanguage && rhs.allowLanguage
        profile.allowProfession = lhs.allowProfession && rhs.allowProfession
        profile.allowInstructions = lhs.allowInstructions && rhs.allowInstructions
        profile.allowPersonalInformation = lhs.allowPersonalInformation && rhs.allowPersonalInformation
        winner.payload = try NoctisSyncDocument.serialize(profile)
        let previous = local.payload == remote.payload ? [] : [loser.payload]
        let archive = local.profileConflicts + remote.profileConflicts + previous
        winner.profileConflicts = Array(Set(archive)).sorted { $0.lexicographicallyPrecedes($1) }
        return Self(document: winner)
    }
}

enum NoctisSyncError: Error, Equatable {
    case unavailable, accountChanged, remoteErased, offline, invalidData, conflict, storage
    var message: String {
        switch self {
        case .unavailable: NoctisText.value("cloud.unavailable")
        case .accountChanged: NoctisText.value("cloud.account.changed")
        case .remoteErased: NoctisText.value("cloud.remote.erased")
        case .offline: NoctisText.value("cloud.offline")
        case .invalidData: NoctisText.value("cloud.invalid.data")
        case .conflict: NoctisText.value("cloud.conflict.retry")
        case .storage: NoctisText.value("cloud.storage.error")
        }
    }
}
