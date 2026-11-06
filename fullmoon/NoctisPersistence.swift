// Created by Sébastien DAGUIN

import Foundation
import SwiftData

@MainActor
enum NoctisPersistence {
    static let schema = Schema([Thread.self, Message.self, NoctisUserProfile.self, NoctisSyncRecord.self])
    static let store: Result<ModelContainer, Error> = Result { try makeContainer() }

    static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        // Preserve SwiftData's existing default store URL. Never reset a failed store.
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if !inMemory {
            #if os(iOS) || os(visionOS)
            let directory = configuration.url.deletingLastPathComponent()
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path
            )
            var backup = URLResourceValues()
            backup.isExcludedFromBackup = true
            var path = directory
            try path.setResourceValues(backup)
            #endif
            for path in [configuration.url.path, configuration.url.path + "-wal", configuration.url.path + "-shm"]
            where FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                #if os(iOS) || os(visionOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
                #endif
            }
        }
        return container
    }
}
