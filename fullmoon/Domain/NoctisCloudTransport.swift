// Created by Sébastien DAGUIN

import CloudKit
import Foundation

protocol NoctisCloudTransport: Sendable {
    func account() async throws -> String
    func open(session: UUID, account: String) async throws
    func generation(session: UUID) async throws -> String
    func fetch(session: UUID) async throws -> [NoctisSyncDocument]
    func save(_ documents: [NoctisSyncDocument], session: UUID) async throws
    func erase(session: UUID) async throws
    func close() async
}

actor NoctisCloudKitTransport: NoctisCloudTransport {
    static let containerIdentifier = "iCloud.com.sebastiendaguin.NoctisAi"
    private let container: CKContainer
    private let zone = CKRecordZone.ID(zoneName: "NoctisIdentity-v1", ownerName: CKCurrentUserDefaultName)
    private let controlZone = CKRecordZone.ID(zoneName: "NoctisControl-v1", ownerName: CKCurrentUserDefaultName)
    private var expectedGeneration: String?
    private var session: UUID?
    private var expectedAccount: String?
    private var records: [String: CKRecord] = [:]

    init() { container = CKContainer(identifier: Self.containerIdentifier) }

    func account() async throws -> String {
        do {
            guard try await container.accountStatus() == .available else { throw NoctisSyncError.unavailable }
            return NoctisSyncDocument.accountFingerprint(try await container.userRecordID().recordName)
        } catch { throw Self.mapped(error) }
    }

    func open(session: UUID, account: String) async throws {
        self.session = session
        expectedAccount = account
        expectedGeneration = nil
        do {
            try await check(session)
            _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: controlZone))
            try await check(session)
            _ = try await resetRecord(session: session)
            try await check(session)
            _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zone))
            try await check(session)
        } catch { throw Self.mapped(error) }
    }

    private func check(_ token: UUID) async throws {
        try Task.checkCancellation()
        guard session == token else { throw CancellationError() }
        guard try await account() == expectedAccount else { throw NoctisSyncError.accountChanged }
        guard session == token else { throw CancellationError() }
        if let expectedGeneration,
           try await resetRecord(session: token)["generation"] as? String != expectedGeneration {
            throw NoctisSyncError.remoteErased
        }
        guard session == token else { throw CancellationError() }
    }

    private func resetRecord(session token: UUID) async throws -> CKRecord {
        try Task.checkCancellation()
        guard session == token else { throw CancellationError() }
        let id = CKRecord.ID(recordName: "reset", zoneID: controlZone)
        do { return try await container.privateCloudDatabase.record(for: id) } catch let error as CKError
        where error.code == .unknownItem {
            guard session == token else { throw CancellationError() }
            let record = CKRecord(recordType: "NoctisControl", recordID: id)
            record["generation"] = UUID().uuidString as CKRecordValue
            do { return try await container.privateCloudDatabase.save(record) } catch let error as CKError
            where error.code == .serverRecordChanged {
                guard session == token else { throw CancellationError() }
                return try await container.privateCloudDatabase.record(for: id)
            }
        }
    }

    func generation(session token: UUID) async throws -> String {
        try await check(token)
        guard let value = try await resetRecord(session: token)["generation"] as? String else {
            throw NoctisSyncError.invalidData
        }
        expectedGeneration = value
        return value
    }

    func fetch(session token: UUID) async throws -> [NoctisSyncDocument] {
        do {
            records = [:]
            var tokenValue: CKServerChangeToken?
            var documents: [String: NoctisSyncDocument] = [:]
            var more = true
            while more {
                try await check(token)
                let page = try await container.privateCloudDatabase.recordZoneChanges(
                    inZoneWith: zone, since: tokenValue, resultsLimit: 100
                )
                try await check(token)
                for result in page.modificationResultsByID.values {
                    let record = try result.get().record
                    guard record.recordType == "NoctisDocument",
                          let asset = record["document"] as? CKAsset, let url = asset.fileURL else {
                        throw NoctisSyncError.invalidData
                    }
                    let document = try JSONDecoder().decode(NoctisSyncDocument.self, from: Data(contentsOf: url))
                    try document.validate()
                    guard document.id == record.recordID.recordName else { throw NoctisSyncError.invalidData }
                    records[document.id] = record
                    documents[document.id] = document
                }
                tokenValue = page.changeToken
                more = page.moreComing
            }
            return documents.values.sorted { $0.id < $1.id }
        } catch { throw Self.mapped(error) }
    }

    func save(_ documents: [NoctisSyncDocument], session token: UUID) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for start in stride(from: 0, to: documents.count, by: 50) {
                try await check(token)
                var batch: [CKRecord] = []
                for document in documents[start..<min(start + 50, documents.count)] {
                    try document.validate()
                    let url = directory.appendingPathComponent(UUID().uuidString)
                    let data = try NoctisSyncDocument.serialize(document)
                    #if os(iOS) || os(visionOS)
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    #else
                    try data.write(to: url, options: .atomic)
                    #endif
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    let record = records[document.id] ?? CKRecord(
                        recordType: "NoctisDocument", recordID: CKRecord.ID(recordName: document.id, zoneID: zone)
                    )
                    record["document"] = CKAsset(fileURL: url)
                    batch.append(record)
                }
                let results = try await container.privateCloudDatabase.modifyRecords(
                    saving: batch, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true
                )
                try await check(token)
                guard results.saveResults.count == batch.count else { throw NoctisSyncError.storage }
                for (id, result) in results.saveResults { records[id.recordName] = try result.get() }
            }
        } catch { throw Self.mapped(error) }
    }

    func erase(session token: UUID) async throws {
        do {
            try await check(token)
            let reset = try await resetRecord(session: token)
            try await check(token)
            reset["generation"] = UUID().uuidString as CKRecordValue
            _ = try await container.privateCloudDatabase.save(reset)
            expectedGeneration = nil
            try await check(token)
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: zone)
            try await check(token)
            records = [:]
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return
        } catch { throw Self.mapped(error) }
    }

    func close() {
        session = nil
        expectedAccount = nil
        expectedGeneration = nil
        records = [:]
    }

    private static func mapped(_ error: Error) -> Error {
        guard let cloud = error as? CKError else { return error }
        switch cloud.code {
        case .networkUnavailable, .networkFailure: return NoctisSyncError.offline
        case .serverRecordChanged, .batchRequestFailed: return NoctisSyncError.conflict
        case .notAuthenticated, .badContainer, .missingEntitlement, .permissionFailure:
            return NoctisSyncError.unavailable
        case .partialFailure:
            if cloud.partialErrorsByItemID?.values.contains(where: {
                ($0 as? CKError)?.code == .serverRecordChanged
            }) == true { return NoctisSyncError.conflict }
            return NoctisSyncError.storage
        default: return NoctisSyncError.storage
        }
    }
}
