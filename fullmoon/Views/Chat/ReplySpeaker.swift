#if os(iOS)
import AVFAudio
import SwiftUI

extension EnvironmentValues {
    @Entry var replySpeaker: ReplySpeaker?
}

@MainActor @Observable
final class ReplySpeaker {
    private(set) var currentMessageID: UUID?
    private(set) var isDictating = false
    private(set) var previewError: String?

    @ObservationIgnored private var stream: SpokenReply?
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private let output = ReplyAudioOutput()
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    isolated deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        playback?.cancel()
        stream?.continuation.finish()
        output.stop()
    }

    func toggle(messageID: UUID, text: String) {
        if currentMessageID == messageID { stop() } else { read(messageID: messageID, text: text) }
    }

    func read(messageID: UUID, text: String) {
        beginStream(messageID: messageID)
        updateStream(messageID: messageID, text: text, isFinal: true)
    }

    func previewNoctis(text: String, messageID: UUID) {
        previewError = nil
        start(messageID: messageID, voice: .preview, onEnd: { _ in })
        updateStream(messageID: messageID, text: text, isFinal: true)
    }

    func beginStream(messageID: UUID, onEnd: @escaping @MainActor (Bool) -> Void = { _ in }) {
        let useKokoro = UserDefaults.standard.bool(forKey: "noctis.voice.useKokoro")
        start(messageID: messageID, voice: useKokoro ? .noctis : .system, onEnd: onEnd)
    }

    /// Accept cumulative model snapshots. Only committed phrases enter the playback queue.
    func updateStream(messageID: UUID, text: String, isFinal: Bool) {
        guard currentMessageID == messageID, let stream else { return }
        guard let phrases = stream.segmenter.take(from: text, isFinal: isFinal) else { stop(); return }
        for phrase in phrases { stream.continuation.yield(phrase) }
        if isFinal { stream.continuation.finish() }
    }

    func stop() { finish(naturally: false) }

    func setDictating(_ active: Bool) {
        isDictating = active
        if active { stop() }
    }

    private func start(messageID: UUID, voice: SpokenReply.Voice, onEnd: @escaping @MainActor (Bool) -> Void) {
        stop()
        guard !isDictating else { onEnd(false); return }
        let (phrases, continuation) = AsyncStream<String>.makeStream()
        let reply = SpokenReply(voice: voice, continuation: continuation, onEnd: onEnd)
        stream = reply
        currentMessageID = messageID
        playback = Task { [weak self] in
            var played = false
            for await phrase in phrases {
                guard let self, self.stream === reply, !Task.isCancelled else { return }
                guard await play(phrase, for: reply) else {
                    if self.stream === reply { finish(naturally: false) }
                    return
                }
                played = true
            }
            guard let self, self.stream === reply else { return }
            finish(naturally: played)
        }
    }

    private func play(_ phrase: String, for reply: SpokenReply) async -> Bool {
        if reply.voice != .system {
            do {
                let samples = try await KokoroVoiceEngine.shared.synthesize(phrase)
                guard stream === reply, !Task.isCancelled else { return false }
                return try await output.play(samples)
            } catch {
                guard stream === reply, !Task.isCancelled else { return false }
                if reply.voice == .preview {
                    previewError = error.localizedDescription
                    return false
                }
                // Synthesis or playback setup failed before this phrase made any sound.
                // Switch for the rest of this reply, without repeating earlier phrases.
                output.stop()
                reply.voice = .system
            }
        }
        return await output.speak(phrase)
    }

    private func finish(naturally: Bool) {
        guard let previous = stream else { return }
        stream = nil
        currentMessageID = nil
        playback?.cancel()
        playback = nil
        previous.continuation.finish()
        output.stop()
        previous.onEnd(naturally)
    }
}

@MainActor
private final class SpokenReply {
    enum Voice { case system, noctis, preview }

    var voice: Voice
    var segmenter = ReplySpeechPhrases()
    let continuation: AsyncStream<String>.Continuation
    let onEnd: @MainActor (Bool) -> Void

    init(voice: Voice, continuation: AsyncStream<String>.Continuation, onEnd: @escaping @MainActor (Bool) -> Void) {
        self.voice = voice
        self.continuation = continuation
        self.onEnd = onEnd
    }
}
#endif
