// Created by Sébastien DAGUIN

import Foundation
import Noctis
import SwiftData
@testable import fullmoon

private enum TestFailure: Error { case loading, generation, timeout }

private actor ControlledModel: AIModelService {
    var loads = 0
    var histories: [[AIChatMessage]] = []
    var generations = 0
    var failLoading = false
    var omitReadyPhase = false
    var holdCleanup = false
    var cleaning = false
    private var output: AsyncThrowingStream<String, Error>.Continuation?
    private var cleanup: CheckedContinuation<Void, Never>?

    func load() throws {
        loads += 1
        if failLoading { throw TestFailure.loading }
    }
    func load(progress: @escaping @Sendable (AIModelLoadPhase) -> Void) async throws {
        progress(.loading)
        try await Task.sleep(for: .milliseconds(20))
        try load()
        if !omitReadyPhase { progress(.ready) }
    }
    func resetConversation(history: [AIChatMessage]) { histories.append(history) }
    func cancelGeneration() { output?.finish(throwing: CancellationError()) }
    func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        generations += 1
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        output = pair.continuation
        output?.yield("First")
        return pair.stream
    }
    func withResponse(
        prompt: String, consume: @Sendable (AsyncThrowingStream<String, Error>) async throws -> Void
    ) async throws {
        do {
            try await consume(generate(prompt: prompt))
            try Task.checkCancellation()
        } catch {
            cleaning = true
            if holdCleanup { await withCheckedContinuation { cleanup = $0 } }
            output?.finish()
            output = nil
            cleaning = false
            throw error
        }
        output = nil
    }
    func emit(_ text: String) { output?.yield(text) }
    func end() { output?.finish() }
    func fail() { output?.finish(throwing: TestFailure.generation) }
    func setFailLoading(_ value: Bool) { failLoading = value }
    func setOmitReadyPhase() { omitReadyPhase = true }
    func setHoldCleanup() { holdCleanup = true }
    func releaseCleanup() { holdCleanup = false; cleanup?.resume(); cleanup = nil }
}

@main
struct ChatPerformanceTests {
    static func check(_ condition: Bool, _ message: String = "Test assertion failed") {
        precondition(condition, message)
    }

    @MainActor static func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            if ContinuousClock.now > deadline { throw TestFailure.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor static func main() async throws {
        try await loadingAndRetry()
        try await streamingAndPersistence()
        try await cancellationAndConversationChange()
        try await generationError()
        try await animatedRelay()
        print("PASS: loading/retry, streaming/batching, reuse, cancellation/switch, errors, persistence, animated relay")
    }

    @MainActor static func loadingAndRetry() async throws {
        let model = ControlledModel()
        await model.setFailLoading(true)
        let viewModel = ChatView.ViewModel(makeService: { model })
        check(await viewModel.loadModel() == false)
        check(!viewModel.isConnected && !viewModel.isLoading && viewModel.submissionError != nil)
        await model.setFailLoading(false)
        check(await viewModel.loadModel())
        check(await viewModel.loadModel())
        check(await model.loads == 2, "Connected model must be reused")
        check(viewModel.submissionError == nil && viewModel.loadDuration != nil)
        let unavailable = ChatView.ViewModel(makeService: { throw TestFailure.loading })
        check(await unavailable.loadModel() == false)
        check(!unavailable.isLoading && unavailable.submissionError != nil)
        let noReady = ControlledModel()
        await noReady.setOmitReadyPhase()
        let noReadyViewModel = ChatView.ViewModel(makeService: { noReady })
        check(await noReadyViewModel.loadModel())
        check((noReadyViewModel.loadDuration ?? 0) > 0, "Final loading phase must be counted without a ready callback")
    }

    @MainActor static func streamingAndPersistence() async throws {
        let container = try NoctisPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let model = ControlledModel()
        let viewModel = ChatView.ViewModel(makeService: { model })
        check(await viewModel.loadModel())
        var thread: fullmoon.Thread?
        viewModel.prompt = "Synthetic prompt"
        viewModel.send(to: nil, in: context) { thread = $0 }
        let selected = thread!
        try await waitUntil { selected.sortedMessages.last?.content == "First" }
        viewModel.prompt = "Must wait"
        viewModel.send(to: selected, in: context) { _ in }
        check(selected.messages.count == 2)
        await model.emit(" second")
        await model.emit(" third")
        await model.end()
        try await waitUntil { !viewModel.isSending }
        check(selected.sortedMessages.last?.content == "First second third", "Final batch must be flushed")
        check(viewModel.firstTextDelay != nil && viewModel.generatingMessageID == nil)
        let reader = ModelContext(container)
        let saved = try reader.fetch(FetchDescriptor<fullmoon.Thread>()).first!
        check(saved.sortedMessages.map(\.content) == ["Synthetic prompt", "First second third"])
        check(!saved.sortedMessages.last!.hasError)
    }

    @MainActor static func cancellationAndConversationChange() async throws {
        let container = try NoctisPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let model = ControlledModel()
        await model.setHoldCleanup()
        let viewModel = ChatView.ViewModel(makeService: { model })
        check(await viewModel.loadModel())
        let first = fullmoon.Thread()
        let second = fullmoon.Thread()
        context.insert(first)
        context.insert(second)
        viewModel.prompt = "First conversation"
        viewModel.send(to: first, in: context) { _ in }
        try await waitUntil { first.sortedMessages.last?.content == "First" }
        viewModel.updateThreadSelection(second)
        viewModel.stop() // Same actions as ChatView's selection handler.
        try await waitUntil { await model.cleaning }
        check(viewModel.isSending && viewModel.isStopping, "Must wait for engine cleanup")
        await model.emit(" stale text")
        viewModel.prompt = "Second conversation"
        viewModel.send(to: second, in: context) { _ in }
        check(second.messages.isEmpty, "No overlapping generation during cleanup")
        await model.releaseCleanup()
        try await waitUntil { !viewModel.isSending }
        check(first.sortedMessages.last!.isInterrupted)
        check(first.sortedMessages.last!.content == "First", "Late text after cancellation must be ignored")
        viewModel.send(to: second, in: context) { _ in }
        try await waitUntil { second.sortedMessages.last?.content == "First" }
        await model.end()
        try await waitUntil { !viewModel.isSending }
        check(await model.loads == 1)
        check(await model.histories.count == 2)
        let reader = ModelContext(container)
        let saved = try reader.fetch(FetchDescriptor<fullmoon.Thread>())
        check(saved.first { $0.id == first.id }!.sortedMessages.last!.isInterrupted)
        check(saved.first { $0.id == second.id }!.messages.count == 2)
    }

    @MainActor static func generationError() async throws {
        let container = try NoctisPersistence.makeContainer(inMemory: true)
        let model = ControlledModel()
        let viewModel = ChatView.ViewModel(makeService: { model })
        check(await viewModel.loadModel())
        var thread: fullmoon.Thread?
        viewModel.prompt = "Generation error"
        viewModel.send(to: nil, in: container.mainContext) { thread = $0 }
        try await waitUntil { thread?.sortedMessages.last?.content == "First" }
        await model.emit(" pending")
        await model.fail()
        try await waitUntil { !viewModel.isSending }
        check(thread!.sortedMessages.last!.hasError && viewModel.submissionError != nil)
        check(thread!.sortedMessages.last!.content == "First pending")
        check(viewModel.needsNewSession && viewModel.isConnected)
    }

    @MainActor static func animatedRelay() async throws {
        let relay = AnimatedTextRelay()
        relay.update(with: "Unused Markdown text")
        var idle = relay.stream.makeAsyncIterator()
        check(await idle.next() == nil, "Inactive renderer must not buffer text")
        relay.reset()
        let stream = relay.stream
        relay.update(with: "Salut 👩🏽‍💻")
        relay.update(with: "Salut 👩🏽‍💻 !")
        relay.finish()
        var result = ""
        for await chunk in stream { result += chunk }
        check(result == "Salut 👩🏽‍💻 !", "Animated chunks must preserve Unicode and order")
        relay.update(with: "Ignored after disappearance")
        var finished = relay.stream.makeAsyncIterator()
        check(await finished.next() == nil)
        relay.reset()
        let replay = relay.stream
        relay.update(with: result)
        relay.finish()
        var restored = ""
        for await chunk in replay { restored += chunk }
        check(restored == result, "Reappearing or re-enabled renderer must replay current content")
    }
}
