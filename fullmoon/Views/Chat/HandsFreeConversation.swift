import Foundation
import Observation

/// Ties microphone reactivation to the natural end of the reply for this exact voice turn.
@MainActor @Observable
final class HandsFreeConversation {
    enum Phase: Equatable {
        case idle
        case listening
        case waitingForReply(UUID)
    }

    private(set) var phase = Phase.idle
    var isActive: Bool { phase != .idle }

    func start() {
        guard phase == .idle else { return }
        phase = .listening
    }

    func submitted(replyID: UUID) {
        guard phase == .listening else { return }
        phase = .waitingForReply(replyID)
    }

    func replyFinished(_ replyID: UUID) {
        guard phase == .waitingForReply(replyID) else { return }
        phase = .listening
    }

    func end() { phase = .idle }
}

/// Waits for both speech recognition and acoustic activity to settle before ending a turn.
struct SpeechEndpoint {
    enum Event { case utteranceEnded, noSpeech }

    private let start: ContinuousClock.Instant
    private var lastSpeech: ContinuousClock.Instant
    private var hasWords = false
    private var noiseFloor: Float = 0.10

    init(at start: ContinuousClock.Instant) {
        self.start = start
        lastSpeech = start
    }

    mutating func recognizedWords(at now: ContinuousClock.Instant) {
        hasWords = true
        lastSpeech = now
    }

    mutating func observe(level: Float, at now: ContinuousClock.Instant) -> Event? {
        let threshold = max(0.28, min(0.85, noiseFloor + 0.18))
        if level > threshold {
            lastSpeech = now
        }
        // Follow the room level slowly. Short peaks are generally syllables.
        noiseFloor += (level - noiseFloor) * (level > noiseFloor ? 0.015 : 0.08)
        if hasWords, lastSpeech.duration(to: now) >= .milliseconds(1400) { return .utteranceEnded }
        if !hasWords, start.duration(to: now) >= .seconds(18) { return .noSpeech }
        return nil
    }
}
