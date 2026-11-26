#if os(iOS)
import Foundation
import Observation

@MainActor @Observable
final class NoctisVoiceModel {
    enum State: Equatable {
        case notInstalled, downloading(Double?), ready, failed(String)
    }

    static let shared = NoctisVoiceModel()
    nonisolated static let downloadSize: Int64 = 84_000_000
    nonisolated static var installedDirectory: URL? { KokoroVoicePack.installedDirectory }

    private(set) var state: State
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?

    private init() {
        state = Self.installedDirectory == nil ? .notInstalled : .ready
        KokoroVoicePack.discardAbandonedStaging()
    }

    func download() {
        guard task == nil else { return }
        guard Self.installedDirectory == nil else {
            state = .ready
            return
        }
        let id = UUID()
        requestID = id
        state = .downloading(nil)
        task = Task {
            do {
                let staged = try await KokoroVoicePack.stage(id: id) { fraction in
                    Task { @MainActor in
                        if self.requestID == id, case .downloading(let previous) = self.state,
                           fraction > (previous ?? -1) { self.state = .downloading(fraction) }
                    }
                }
                defer { try? FileManager.default.removeItem(at: staged) }
                try Task.checkCancellation()
                guard requestID == id else { return }
                try KokoroVoicePack.install(staged)
                state = .ready
            } catch {
                guard requestID == id else { return }
                state = .failed(error.localizedDescription)
            }
            if requestID == id {
                requestID = nil
                task = nil
            }
        }
    }

    func cancelDownload() {
        requestID = nil
        task?.cancel()
        task = nil
        state = Self.installedDirectory == nil ? .notInstalled : .ready
    }
}
#endif
