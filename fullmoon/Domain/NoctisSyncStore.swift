// Created by Sébastien DAGUIN

import Foundation
import SwiftData

@Model
final class NoctisSyncRecord {
    @Attribute(.unique) var key: String
    var document: Data
    var localPayload: Data
    var acknowledged: Data?
    var conflicts: [Data] = []

    init(document: NoctisSyncDocument) throws {
        key = document.id
        self.document = try NoctisSyncDocument.serialize(document)
        localPayload = document.payload
    }
}

@MainActor
final class NoctisSyncStore {
    let context: ModelContext
    private let device: String

    init(context: ModelContext, device: String) {
        self.context = context.container.mainContext
        self.device = device
    }

    func entries(includeProfile: Bool) throws -> [String: NoctisSyncRecord] {
        let records = try context.fetch(FetchDescriptor<NoctisSyncRecord>())
        let included = records.filter { includeProfile || $0.key != "profile" }
        return Dictionary(uniqueKeysWithValues: included.map { ($0.key, $0) })
    }

    func hasLocalChanges(includeProfile: Bool) throws -> Bool {
        let records = try entries(includeProfile: includeProfile)
        var present: Set<String> = []
        for thread in try context.fetch(FetchDescriptor<Thread>()) {
            let key = "conversation-\(thread.id.uuidString)"
            present.insert(key)
            guard let entry = records[key] else { return true }
            var current = snapshot(of: thread)
            let old = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: entry.localPayload)
            current.deletedMessages = Array(Set(old.deletedMessages).union(
                Set(old.messages.map(\.id)).subtracting(current.messages.map(\.id))
            )).sorted { $0.uuidString < $1.uuidString }
            let payloadChanged = try NoctisSyncDocument.serialize(current) != entry.localPayload
            if payloadChanged || NoctisSyncDocument.digest(entry.document) != entry.acknowledged {
                return true
            }
        }
        if includeProfile, let profile = try NoctisUserIdentity.existingProfile(in: context) {
            present.insert("profile")
            let payload = try NoctisSyncDocument.serialize(NoctisProfileSnapshot(profile: profile))
            if records["profile"]?.localPayload != payload { return true }
        }
        for (key, record) in records {
            let document = try JSONDecoder().decode(NoctisSyncDocument.self, from: record.document)
            let removed = !present.contains(key) && !document.deleted
            if removed || NoctisSyncDocument.digest(record.document) != record.acknowledged { return true }
        }
        return false
    }

    func capture(includeProfile: Bool) throws -> [String: NoctisSyncRecord] {
        var records = try entries(includeProfile: includeProfile)
        var present: Set<String> = []
        for thread in try context.fetch(FetchDescriptor<Thread>()) {
            let key = "conversation-\(thread.id.uuidString)"
            present.insert(key)
            let previous = try records[key].map { try JSONDecoder().decode(NoctisSyncDocument.self, from: $0.document) }
            var snapshot = snapshot(of: thread)
            if let previous, !previous.deleted {
                let old = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: previous.payload)
                snapshot.deletedMessages = Array(Set(old.deletedMessages).union(
                    Set(old.messages.map(\.id)).subtracting(snapshot.messages.map(\.id))
                )).sorted { $0.uuidString < $1.uuidString }
            }
            let payload = try NoctisSyncDocument.serialize(snapshot)
            try capture(key: key, kind: .conversation, payload: payload, records: &records)
        }
        if includeProfile, let profile = try NoctisUserIdentity.existingProfile(in: context) {
            present.insert("profile")
            let payload = try NoctisSyncDocument.serialize(NoctisProfileSnapshot(profile: profile))
            try capture(key: "profile", kind: .profile, payload: payload, records: &records)
        }
        for (key, record) in records where !present.contains(key) {
            var document = try JSONDecoder().decode(NoctisSyncDocument.self, from: record.document)
            if !document.deleted {
                document.deleted = true
                document.payload = Data()
                document.profileConflicts = []
                record.conflicts = []
                document.modifiedAt = Date()
                document.author = device
                record.document = try NoctisSyncDocument.serialize(document)
                record.localPayload = Data()
            }
        }
        try context.save()
        return records
    }

    private func capture(
        key: String, kind: NoctisSyncDocument.Kind, payload: Data, records: inout [String: NoctisSyncRecord]
    ) throws {
        if let record = records[key] {
            let previous = try JSONDecoder().decode(NoctisSyncDocument.self, from: record.document)
            let archiveChanged = kind == .profile && previous.profileConflicts != record.conflicts
            if record.localPayload != payload || archiveChanged {
                var document = NoctisSyncDocument(id: key, kind: kind, modifiedAt: Date(), author: device,
                                                  deleted: false, payload: payload)
                if kind == .profile { document.profileConflicts = record.conflicts }
                record.document = try NoctisSyncDocument.serialize(document)
                record.localPayload = payload
            }
        } else {
            let document = NoctisSyncDocument(id: key, kind: kind, modifiedAt: Date(), author: device,
                                              deleted: false, payload: payload)
            let record = try NoctisSyncRecord(document: document)
            context.insert(record)
            records[key] = record
        }
    }

    func apply(_ document: NoctisSyncDocument, conflict: NoctisSyncDocument? = nil) throws {
        try document.validate()
        let records = try entries(includeProfile: true)
        let record: NoctisSyncRecord
        if let existing = records[document.id] { record = existing } else {
            record = try NoctisSyncRecord(document: document)
            context.insert(record)
        }
        if let conflict, !record.conflicts.contains(NoctisSyncDocument.digest(conflict.payload)) {
            record.conflicts.append(NoctisSyncDocument.digest(conflict.payload))
            if conflict.kind == .conversation {
                var copy = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: conflict.payload)
                copy.id = NoctisSyncDocument.stableID(for: try NoctisSyncDocument.serialize(conflict))
                copy.title = "↯ " + (copy.title ?? "")
                // Conflict copies receive distinct message IDs so no relationship is moved
                // out of the original conversation. IDs stay stable across retries/devices.
                copy.messages = copy.messages.map { message in
                    var value = message
                    value.id = NoctisSyncDocument.stableID(for: Data("\(copy.id)-\(message.id)".utf8))
                    return value
                }
                try applyThread(copy)
            }
        }
        if document.kind == .conversation {
            if document.deleted {
                let id = String(document.id.dropFirst("conversation-".count))
                for thread in try context.fetch(FetchDescriptor<Thread>()) where thread.id.uuidString == id {
                    for message in thread.messages { context.delete(message) }
                    context.delete(thread)
                }
            } else {
                let thread = try JSONDecoder().decode(NoctisThreadSnapshot.self, from: document.payload)
                guard document.id == "conversation-\(thread.id.uuidString)" else { throw NoctisSyncError.invalidData }
                try applyThread(thread)
            }
        } else if document.deleted {
            record.conflicts = []
            for profile in try context.fetch(FetchDescriptor<NoctisUserProfile>()) { context.delete(profile) }
        } else {
            record.conflicts = document.profileConflicts
            let snapshot = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: document.payload)
            snapshot.apply(to: try NoctisUserIdentity.getOrCreateProfile(in: context))
        }
        record.document = try NoctisSyncDocument.serialize(document)
        record.localPayload = document.payload
        try context.save()
    }

    func acknowledge(_ documents: [NoctisSyncDocument]) throws {
        let records = try entries(includeProfile: true)
        for document in documents {
            let data = try NoctisSyncDocument.serialize(document)
            records[document.id]?.acknowledged = NoctisSyncDocument.digest(data)
        }
        try context.save()
    }

    func archiveProfile(_ snapshot: NoctisProfileSnapshot) throws {
        guard let record = try entries(includeProfile: true)["profile"] else { return }
        let payload = try NoctisSyncDocument.serialize(snapshot)
        if !record.conflicts.contains(payload) { record.conflicts.append(payload) }
    }

    func clearProfileArchive() throws {
        guard let record = try entries(includeProfile: true)["profile"],
              let profile = try NoctisUserIdentity.existingProfile(in: context) else { return }
        let payload = try NoctisSyncDocument.serialize(NoctisProfileSnapshot(profile: profile))
        record.conflicts = []
        record.localPayload = payload
        record.document = try NoctisSyncDocument.serialize(NoctisSyncDocument(
            id: "profile", kind: .profile, modifiedAt: Date(), author: device, deleted: false, payload: payload
        ))
        try context.save()
    }

    func restoreProfileConflict() throws {
        guard let record = try entries(includeProfile: true)["profile"],
              let data = record.conflicts.last else { return }
        var snapshot = try JSONDecoder().decode(NoctisProfileSnapshot.self, from: data)
        snapshot.personalizationEnabled = false
        let profile = try NoctisUserIdentity.getOrCreateProfile(in: context)
        let previous = try NoctisSyncDocument.serialize(NoctisProfileSnapshot(profile: profile))
        record.conflicts.removeLast()
        if previous != data && !record.conflicts.contains(previous) { record.conflicts.append(previous) }
        snapshot.apply(to: profile)
        try context.save()
    }

    private func snapshot(of thread: Thread) -> NoctisThreadSnapshot {
        NoctisThreadSnapshot(id: thread.id, title: thread.title, timestamp: thread.timestamp,
                            messages: thread.messages.map {
            NoctisMessageSnapshot(id: $0.id, role: $0.role.rawValue, content: $0.content, timestamp: $0.timestamp,
                                 generatingTime: $0.generatingTime,
                                 isInterrupted: $0.isInterrupted, hasError: $0.hasError)
        }.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private func applyThread(_ snapshot: NoctisThreadSnapshot) throws {
        let allMessages = try context.fetch(FetchDescriptor<Message>())
        let byID = Dictionary(uniqueKeysWithValues: allMessages.map { ($0.id, $0) })
        guard snapshot.messages.allSatisfy({ value in
            byID[value.id]?.thread.map { $0.id == snapshot.id } ?? true
        }) else { throw NoctisSyncError.invalidData }
        let threads = try context.fetch(FetchDescriptor<Thread>())
        let thread = threads.first { $0.id == snapshot.id } ?? Thread()
        if thread.modelContext == nil { context.insert(thread) }
        thread.id = snapshot.id
        thread.title = snapshot.title
        thread.timestamp = snapshot.timestamp
        let wanted = Set(snapshot.messages.map(\.id)).subtracting(snapshot.deletedMessages)
        for message in thread.messages where !wanted.contains(message.id) { context.delete(message) }
        for value in snapshot.messages where wanted.contains(value.id) {
            guard let role = Role(rawValue: value.role) else { throw NoctisSyncError.invalidData }
            let message = byID[value.id] ?? Message(role: role, content: value.content)
            guard message.thread == nil || message.thread?.id == thread.id else { throw NoctisSyncError.invalidData }
            if message.modelContext == nil { context.insert(message) }
            message.id = value.id
            message.role = role
            message.content = value.content
            message.timestamp = value.timestamp
            message.generatingTime = value.generatingTime
            message.isInterrupted = value.isInterrupted
            message.hasError = value.hasError
            message.thread = thread
        }
    }
}
