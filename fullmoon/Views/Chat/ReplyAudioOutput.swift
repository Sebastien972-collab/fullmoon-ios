#if os(iOS)
import AVFAudio

/// Only one clip is in flight. Completion means the last sample has reached the output device.
@MainActor
final class ReplyAudioOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private var delegate: ReplyUtteranceDelegate?
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var ownsAudioSession = false
    private var completion: CheckedContinuation<Bool, Never>?
    private var activeClip: UUID?

    init() {
        synthesizer.usesApplicationAudioSession = false
    }

    func speak(_ text: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        let id = UUID()
        delegate = ReplyUtteranceDelegate(utterance: utterance) { [weak self] natural in
            self?.complete(id: id, naturally: natural)
        }
        synthesizer.delegate = delegate
        return await withCheckedContinuation { continuation in
            completion = continuation
            activeClip = id
            synthesizer.speak(utterance)
        }
    }

    func play(_ samples: [Float]) async throws -> Bool {
        guard !Task.isCancelled else { return false }
        guard let count = UInt32(exactly: samples.count), count > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channels = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
        buffer.frameLength = count
        samples.withUnsafeBufferPointer { source in
            if let address = source.baseAddress { channels[0].update(from: address, count: source.count) }
        }
        let player = try preparePlayer(format: format)
        let id = UUID()
        return await withCheckedContinuation { continuation in
            completion = continuation
            activeClip = id
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.complete(id: id, naturally: true) }
            }
            player.play()
        }
    }

    func stop() {
        let pending = completion
        activeClip = nil
        completion = nil
        synthesizer.delegate = nil
        delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
        pending?.resume(returning: false)
    }

    private func preparePlayer(format: AVAudioFormat) throws -> AVAudioPlayerNode {
        if let node, engine?.isRunning == true { return node }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        ownsAudioSession = true
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.node = node
        return node
    }

    private func complete(id: UUID, naturally: Bool) {
        guard activeClip == id else { return }
        activeClip = nil
        let pending = completion
        completion = nil
        pending?.resume(returning: naturally)
    }
}

private final class ReplyUtteranceDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let utteranceID: ObjectIdentifier
    private let callback: @MainActor @Sendable (Bool) -> Void

    init(utterance: AVSpeechUtterance, callback: @escaping @MainActor @Sendable (Bool) -> Void) {
        utteranceID = ObjectIdentifier(utterance)
        self.callback = callback
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        complete(utterance, naturally: true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        complete(utterance, naturally: false)
    }

    private func complete(_ utterance: AVSpeechUtterance, naturally: Bool) {
        guard ObjectIdentifier(utterance) == utteranceID else { return }
        Task { @MainActor in callback(naturally) }
    }
}
#endif
