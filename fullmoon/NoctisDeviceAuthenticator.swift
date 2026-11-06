// Created by Sébastien DAGUIN

import Foundation
import LocalAuthentication
import Observation

enum NoctisText {
    static func value(_ key: String) -> String { NSLocalizedString(key, comment: "") }
}

enum NoctisUnlockError: Error, Equatable { case unavailable, denied, cancelled }

@MainActor
protocol NoctisAuthenticating {
    var mode: String { get }
    func unlock(reason: String) async throws
}

@MainActor
struct NoctisDeviceAuthenticator: NoctisAuthenticating {
    var mode: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return NoctisText.value("security.unavailable")
        }
        switch context.biometryType {
        case .faceID: return NoctisText.value("security.faceid")
        case .touchID: return NoctisText.value("security.touchid")
        default: return NoctisText.value("security.passcode")
        }
    }

    func unlock(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = NoctisText.value("common.cancel")
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            throw NoctisUnlockError.unavailable
        }
        do {
            let success = try await withTaskCancellationHandler {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            } onCancel: { context.invalidate() }
            try Task.checkCancellation()
            guard success else { throw NoctisUnlockError.denied }
        } catch let error as LAError {
            if [.userCancel, .systemCancel, .appCancel].contains(error.code) {
                throw NoctisUnlockError.cancelled
            }
            throw NoctisUnlockError.denied
        }
    }
}

@Observable
@MainActor
final class NoctisLockController {
    private(set) var enabled: Bool
    private(set) var unlocked: Bool
    private(set) var authenticating = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: any NoctisAuthenticating
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var attempted = false

    var mode: String { authenticator.mode }

    init(defaults: UserDefaults = .standard, authenticator: any NoctisAuthenticating = NoctisDeviceAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        let initiallyEnabled = defaults.bool(forKey: "noctis.lock.enabled")
        enabled = initiallyEnabled
        unlocked = !initiallyEnabled
    }

    func enterBackground() {
        epoch = UUID()
        attempted = false
        if enabled { unlocked = false }
    }

    func unlock(automatically: Bool = false) async {
        guard enabled, !unlocked, !authenticating, !automatically || !attempted else { return }
        attempted = true
        let token = epoch
        authenticating = true
        defer { authenticating = false }
        do {
            try await authenticator.unlock(reason: NoctisText.value("security.unlock.reason"))
            guard token == epoch else { return }
            unlocked = true
            errorMessage = nil
        } catch {
            guard token == epoch else { return }
            errorMessage = error is CancellationError || (error as? NoctisUnlockError) == .cancelled
                ? nil : NoctisText.value("security.authentication.failed")
        }
    }

    func setEnabled(_ value: Bool) async {
        guard value != enabled, !authenticating else { return }
        authenticating = true
        let token = epoch
        defer { authenticating = false }
        do {
            try await authenticator.unlock(reason: NoctisText.value("security.change.reason"))
            guard token == epoch else { return }
            defaults.set(value, forKey: "noctis.lock.enabled")
            enabled = value
            unlocked = true
            attempted = true
            errorMessage = nil
        } catch {
            errorMessage = error is CancellationError || (error as? NoctisUnlockError) == .cancelled
                ? nil : NoctisText.value("security.authentication.failed")
        }
    }
}
