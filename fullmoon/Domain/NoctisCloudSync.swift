// Created by Sébastien DAGUIN

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class NoctisCloudSync {
    enum State: Equatable {
        case disabled, pending, unavailable, syncing, synchronized, offline, failed(String)
        var title: String {
            switch self {
            case .disabled: NoctisText.value("cloud.disabled")
            case .pending: NoctisText.value("cloud.pending")
            case .unavailable: NoctisText.value("cloud.unavailable")
            case .syncing: NoctisText.value("cloud.syncing")
            case .synchronized: NoctisText.value("cloud.synchronized")
            case .offline: NoctisText.value("cloud.offline")
            case .failed(let message): message
            }
        }
    }

    private(set) var enabled: Bool
    private(set) var state: State = .disabled
    private(set) var lastSuccess: Date?
    private(set) var isWorking = false
    private(set) var completed = 0
    private(set) var total = 0
    private var generatingClients: Set<UUID> = []
    var isGenerating: Bool { !generatingClients.isEmpty }

    func setGenerating(_ value: Bool, client: UUID) {
        if value { generatingClients.insert(client) } else { generatingClients.remove(client) }
        refreshStatus()
    }

    func refreshStatus() {
        guard enabled, !isWorking, let store else { return }
        do {
            let dirty = try store.hasLocalChanges(includeProfile: includeProfile)
            if isGenerating || dirty { state = .pending }
        } catch { state = .failed(NoctisSyncError.storage.message) }
    }
    var includeProfile: Bool {
        didSet { defaults.set(includeProfile, forKey: "noctis.cloud.profile") }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeTransport: @Sendable () -> any NoctisCloudTransport
    @ObservationIgnored private var transport: (any NoctisCloudTransport)?
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var store: NoctisSyncStore?
    @ObservationIgnored private let device: String

    init(defaults: UserDefaults = .standard,
         makeTransport: @escaping @Sendable () -> any NoctisCloudTransport = { NoctisCloudKitTransport() }) {
        self.defaults = defaults
        self.makeTransport = makeTransport
        enabled = defaults.bool(forKey: "noctis.cloud.enabled")
        includeProfile = defaults.bool(forKey: "noctis.cloud.profile")
        lastSuccess = defaults.object(forKey: "noctis.cloud.lastSuccess") as? Date
        device = defaults.string(forKey: "noctis.cloud.device") ?? UUID().uuidString
        defaults.set(device, forKey: "noctis.cloud.device")
        if enabled { state = .pending }
    }

    func configure(context: ModelContext) {
        if store == nil { store = NoctisSyncStore(context: context, device: device) }
    }

    func checkAvailability() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let cloud = transport ?? makeTransport()
        transport = cloud
        do {
            let account = try await cloud.account()
            if let bound = defaults.string(forKey: "noctis.cloud.account"), bound != account {
                throw NoctisSyncError.accountChanged
            }
            return true
        } catch {
            state = error as? NoctisSyncError == .unavailable ? .unavailable
                : .failed((error as? NoctisSyncError ?? .storage).message)
            return false
        }
    }

    func enable() async {
        guard !isWorking else { return }
        isWorking = true
        let token = session
        let cloud = transport ?? makeTransport()
        transport = cloud
        do {
            let account = try await cloud.account()
            guard session == token else { isWorking = false; return }
            if let bound = defaults.string(forKey: "noctis.cloud.account"), bound != account {
                throw NoctisSyncError.accountChanged
            }
            defaults.set(account, forKey: "noctis.cloud.account")
            try await cloud.open(session: token, account: account)
            let generation = try await cloud.generation(session: token)
            guard session == token else { isWorking = false; return }
            defaults.set(generation, forKey: "noctis.cloud.generation")
            enabled = true
            defaults.set(true, forKey: "noctis.cloud.enabled")
            isWorking = false
            await synchronize()
        } catch {
            isWorking = false
            state = error as? NoctisSyncError == .unavailable ? .unavailable
                : .failed((error as? NoctisSyncError ?? .storage).message)
        }
    }

    func disable() async {
        enabled = false
        defaults.set(false, forKey: "noctis.cloud.enabled")
        session = UUID()
        await transport?.close()
        state = .disabled
    }

    func pause() async {
        session = UUID()
        await transport?.close()
        if enabled { state = .pending }
    }

    func synchronize() async {
        guard enabled, !isWorking, !isGenerating, let store else { return }
        isWorking = true
        state = .syncing
        completed = 0
        total = 0
        let token = session
        let cloud = transport ?? makeTransport()
        transport = cloud
        defer { isWorking = false }
        do {
            let account = try await cloud.account()
            try requireActive(token)
            if let bound = defaults.string(forKey: "noctis.cloud.account"), bound != account {
                throw NoctisSyncError.accountChanged
            }
            defaults.set(account, forKey: "noctis.cloud.account")
            try await cloud.open(session: token, account: account)
            let generation = try await cloud.generation(session: token)
            if let previous = defaults.string(forKey: "noctis.cloud.generation"), generation != previous {
                throw NoctisSyncError.remoteErased
            }
            defaults.set(generation, forKey: "noctis.cloud.generation")
            for attempt in 0..<3 {
                do {
                    try await exchange(store: store, cloud: cloud, token: token)
                    break
                } catch NoctisSyncError.conflict where attempt < 2 {
                    continue
                }
            }
            try requireActive(token)
            guard try await cloud.account() == account else { throw NoctisSyncError.accountChanged }
            try requireActive(token)
            lastSuccess = Date()
            defaults.set(lastSuccess, forKey: "noctis.cloud.lastSuccess")
            let dirty = try store.hasLocalChanges(includeProfile: includeProfile)
            state = isGenerating || dirty ? .pending : .synchronized
        } catch { await handle(error, token: token) }
    }

    private func handle(_ error: Error, token: UUID) async {
        guard token == session, enabled else { return }
        switch error {
        case is CancellationError: state = .pending
        case NoctisSyncError.accountChanged, NoctisSyncError.remoteErased:
            await disable()
            state = .failed((error as? NoctisSyncError ?? .accountChanged).message)
        case NoctisSyncError.offline: state = .offline
        case NoctisSyncError.unavailable: state = .unavailable
        default: state = .failed((error as? NoctisSyncError ?? .storage).message)
        }
    }

    private func requireActive(_ token: UUID) throws {
        try Task.checkCancellation()
        guard enabled, session == token else { throw CancellationError() }
    }

    private func exchange(store: NoctisSyncStore, cloud: any NoctisCloudTransport, token: UUID) async throws {
        let remote = try await cloud.fetch(session: token).filter { includeProfile || $0.kind != .profile }
        try requireActive(token)
        guard !isGenerating else { throw CancellationError() }
        for document in remote { try document.validate() }
        var local = try store.capture(includeProfile: includeProfile)
        var outgoing: [NoctisSyncDocument] = []
        var accepted: [NoctisSyncDocument] = []
        total = Set(local.keys).union(remote.map(\.id)).count
        for server in remote {
            let entry = local.removeValue(forKey: server.id)
            let desired: NoctisSyncDocument
            var conflict: NoctisSyncDocument?
            if let entry {
                let current = try JSONDecoder().decode(NoctisSyncDocument.self, from: entry.document)
                let serverData = try NoctisSyncDocument.serialize(server)
                if NoctisSyncDocument.digest(entry.document) == entry.acknowledged {
                    desired = server
                } else if NoctisSyncDocument.digest(serverData) == entry.acknowledged {
                    desired = current
                } else {
                    let resolution = try NoctisSyncResolution.resolve(local: current, remote: server)
                    desired = resolution.document
                    conflict = resolution.conflict
                }
            } else { desired = server }
            try store.apply(desired, conflict: conflict)
            if desired != server { outgoing.append(desired) }
            accepted.append(desired)
            completed += 1
        }
        for entry in local.values {
            let document = try JSONDecoder().decode(NoctisSyncDocument.self, from: entry.document)
            outgoing.append(document)
            accepted.append(document)
            completed += 1
        }
        // A concurrent edit can create a preserved conflict conversation locally.
        // Include those copies in this same successful exchange.
        let acceptedIDs = Set(accepted.map(\.id))
        for (key, entry) in try store.capture(includeProfile: includeProfile) where !acceptedIDs.contains(key) {
            let document = try JSONDecoder().decode(NoctisSyncDocument.self, from: entry.document)
            outgoing.append(document)
            accepted.append(document)
        }
        total = accepted.count
        completed = total
        try requireActive(token)
        try await cloud.save(outgoing, session: token)
        try requireActive(token)
        try store.acknowledge(accepted)
    }

    func eraseRemote() async {
        guard !isWorking else { return }
        await disable()
        isWorking = true
        let token = session
        let cloud = transport ?? makeTransport()
        transport = cloud
        defer { isWorking = false }
        do {
            let account = try await cloud.account()
            if let bound = defaults.string(forKey: "noctis.cloud.account"), bound != account {
                throw NoctisSyncError.accountChanged
            }
            try await cloud.open(session: token, account: account)
            try await cloud.erase(session: token)
            await cloud.close()
            lastSuccess = nil
            defaults.removeObject(forKey: "noctis.cloud.lastSuccess")
            state = .disabled
        } catch { state = .failed((error as? NoctisSyncError ?? .storage).message) }
    }
}
