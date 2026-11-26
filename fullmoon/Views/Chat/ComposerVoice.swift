#if os(iOS)
import Accelerate
import AVFAudio
import Speech
import SwiftUI

@MainActor @Observable
final class ComposerDictation {
    enum Phase { case idle, authorizing, listening, finishing }

    private(set) var phase = Phase.idle
    private(set) var transcript = ""
    private(set) var levels = Array(repeating: CGFloat.zero, count: 15)
    private(set) var error: String?
    private(set) var completion = UUID()

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var hasSession = false

    @ObservationIgnored private var endpoint: SpeechEndpoint?

    func start(finishAfterSilence: Bool = false) {
        guard phase == .idle else { return }
        let token = generation
        phase = .authorizing
        error = nil
        transcript = ""
        levels = Array(repeating: 0, count: levels.count)
        pending = Task {
            guard generation == token, !Task.isCancelled else { return }
            guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.supportsOnDeviceRecognition else {
                complete(error: composerCopy("On-device dictation is unavailable for this language."))
                return
            }
            let authorization = await Self.speechAuthorization()
            guard generation == token, !Task.isCancelled else { return }
            guard authorization == .authorized else {
                complete(error: composerCopy("Allow speech recognition in Settings to use dictation."))
                return
            }
            let permitted = await AVAudioApplication.requestRecordPermission()
            guard generation == token, !Task.isCancelled else { return }
            guard permitted else {
                complete(error: composerCopy("Allow microphone access in Settings to use dictation."))
                return
            }
            do {
                try beginRecognition(using: recognizer, token: token, finishAfterSilence: finishAfterSilence)
            } catch {
                complete(error: error.localizedDescription)
            }
        }
    }

    nonisolated private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func beginRecognition(using recognizer: SFSpeechRecognizer, token: UUID, finishAfterSilence: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        hasSession = true
        let engine = AVAudioEngine()
        self.engine = engine
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            complete(error: composerCopy("No microphone is available."))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let tap = Self.audioTap(request: request) { [weak self] level in
            Task { @MainActor in
                guard let self, self.generation == token, self.phase == .listening else { return }
                self.levels.removeFirst()
                self.levels.append(CGFloat(level))
                self.detectEndOfTurn(level: level)
            }
        }
        node.installTap(onBus: 0, bufferSize: 2_048, format: format, block: tap)
        hasTap = true
        engine.prepare()
        try engine.start()
        endpoint = finishAfterSilence ? SpeechEndpoint(at: .now) : nil
        phase = .listening
        recognizer.queue = .main
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let words, !words.isEmpty, self.transcript != words {
                    self.transcript = words
                    self.endpoint?.recognizedWords(at: .now)
                }
                if finished || failure != nil { self.complete(error: failure) }
            }
        }
    }

    private func detectEndOfTurn(level: Float) {
        switch endpoint?.observe(level: level, at: .now) {
        case .utteranceEnded: finish()
        case .noSpeech: complete(error: composerCopy("No speech detected. Voice conversation ended."))
        case nil: break
        }
    }

    // Only the scalar level leaves the real-time audio callback.
    nonisolated private static func audioTap(
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
            let decibels = 20 * log10(max(rms, 0.0001))
            onLevel(max(0, min(1, (decibels + 55) / 50)))
        }
    }

    /// Close the audio stream and let Speech flush the last words before sending.
    func finish() {
        guard phase == .listening else { return }
        phase = .finishing
        stopCapture()
        let token = generation
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, generation == token else { return }
            complete()
        }
    }

    /// Invalidate callbacks and outstanding permission requests before releasing audio resources.
    func cancel() { complete() }

    private func complete(error: String? = nil) {
        endpoint = nil
        generation = UUID()
        pending?.cancel()
        pending = nil
        stopCapture()
        recognition?.cancel()
        recognition = nil
        self.error = error
        phase = .idle
        completion = generation
    }

    private func stopCapture() {
        if let engine {
            if engine.isRunning { engine.stop() }
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
            self.engine = nil
        }
        request?.endAudio()
        request = nil
        if hasSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasSession = false
        }
    }
}

struct ComposerListeningIndicator: View {
    let voice: ComposerDictation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppManager.self) private var appManager

    private var statusText: String {
        switch voice.phase {
        case .authorizing: composerCopy("Preparing microphone…")
        case .finishing: composerCopy("Finishing dictation…")
        default: composerCopy("Listening…")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if reduceMotion || appManager.appearance.reduceAnimations || voice.phase != .listening {
                Text(verbatim: statusText)
                    .font(.caption.weight(.medium))
            } else {
                HStack(spacing: 3) {
                    ForEach(voice.levels.indices, id: \.self) { index in
                        Capsule().frame(width: 3, height: 3 + 15 * voice.levels[index])
                    }
                }
                .frame(height: 18)
                .foregroundStyle(.tint)
            }
            if !voice.transcript.isEmpty {
                Text(verbatim: voice.transcript)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
        .accessibilityValue(Text(verbatim: voice.transcript))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
