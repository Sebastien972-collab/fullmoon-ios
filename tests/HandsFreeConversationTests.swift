import Foundation

// Compile this standalone test with HandsFreeConversation.swift.
@main
struct HandsFreeConversationTests {
    @MainActor static func main() {
        let conversation = HandsFreeConversation()
        let first = UUID()
        let second = UUID()

        conversation.start()
        precondition(conversation.phase == .listening)
        conversation.submitted(replyID: first)
        conversation.start()
        conversation.replyFinished(second)
        precondition(conversation.phase == .waitingForReply(first))
        conversation.replyFinished(first)
        precondition(conversation.phase == .listening)

        conversation.submitted(replyID: second)
        conversation.end()
        conversation.replyFinished(second)
        precondition(!conversation.isActive)
        conversation.start()
        conversation.replyFinished(second)
        precondition(conversation.phase == .listening)
        conversation.end()

        let start = ContinuousClock.now
        var endpoint = SpeechEndpoint(at: start)
        precondition(endpoint.observe(level: 0, at: start.advanced(by: .seconds(2))) == nil)
        precondition(endpoint.observe(level: 0, at: start.advanced(by: .seconds(18))) == .noSpeech)
        endpoint = SpeechEndpoint(at: start)
        endpoint.recognizedWords(at: start)
        precondition(endpoint.observe(level: 0.8, at: start.advanced(by: .seconds(1))) == nil)
        precondition(endpoint.observe(level: 0, at: start.advanced(by: .seconds(2))) == nil)
        endpoint.recognizedWords(at: start.advanced(by: .seconds(2)))
        precondition(endpoint.observe(level: 0, at: start.advanced(by: .seconds(3))) == nil)
        precondition(endpoint.observe(level: 0, at: start.advanced(by: .milliseconds(3400))) == .utteranceEnded)
        print("Passed hands-free turn sequencing, stale playback callbacks, speech endpoint and no-input timeout")
    }
}
