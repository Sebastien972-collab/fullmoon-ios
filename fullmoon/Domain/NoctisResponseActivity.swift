// Created by Sébastien DAGUIN

import Foundation
import Noctis

/// Presentation history for one answer. It is never replayed as model context.
struct NoctisResponseActivity: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case thinking, usingTools, responding, completed, interrupted, failed

        var isActive: Bool {
            self == .thinking || self == .usingTools || self == .responding
        }
    }

    static let reasoningLimit = 32_768
    static let toolLimit = 64

    var startedAt: Date
    private(set) var updatedAt: Date
    private(set) var endedAt: Date?
    private(set) var phase = Phase.thinking
    private(set) var reasoning = ""
    private(set) var reasoningTruncated = false
    private(set) var tools: [NoctisToolActivity] = []
    private(set) var omittedToolCount = 0

    init(startedAt: Date = .now) {
        self.startedAt = startedAt
        updatedAt = startedAt
    }

    var hasDetails: Bool { !reasoning.isEmpty || !tools.isEmpty }
    var activeTool: NoctisToolActivity? { tools.last { $0.status == .running } }

    mutating func observe(_ event: AIResponseEvent, at date: Date = .now) {
        guard endedAt == nil else { return }
        updatedAt = date
        switch event {
        case .textDelta(let text):
            guard !text.isEmpty else { return }
            phase = activeTool == nil ? .responding : .usingTools
        case .reasoningDelta(let text):
            guard !text.isEmpty else { return }
            let remaining = Self.reasoningLimit - reasoning.count
            reasoning.append(contentsOf: text.prefix(max(0, remaining)))
            reasoningTruncated = reasoningTruncated || text.count > remaining
            phase = activeTool == nil ? .thinking : .usingTools
        case let .toolStarted(id, name, arguments):
            startTool(id: id, name: name, arguments: arguments, at: date)
        case let .toolCompleted(id, name, result, isError):
            completeTool(id: id, name: name, result: result, isError: isError, at: date)
        }
    }

    mutating func finish(_ outcome: Phase, at date: Date = .now) {
        guard endedAt == nil else { return }
        phase = outcome.isActive ? .interrupted : outcome
        endedAt = date
        updatedAt = date
        // A cancelled or failed turn can leave tools without a terminal event.
        for index in tools.indices where tools[index].status == .running {
            tools[index].status = .interrupted
            tools[index].endedAt = date
        }
    }

    func settledForDisplay(isStreaming: Bool) -> Self {
        guard !isStreaming, endedAt == nil else { return self }
        var settled = self
        settled.finish(.interrupted, at: updatedAt)
        return settled
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> Self? {
        guard let data, data.count <= 2_000_000 else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    private mutating func startTool(id: String, name: String, arguments: String, at date: Date) {
        guard !tools.contains(where: { $0.id == id }) else { return }
        guard tools.count < Self.toolLimit else {
            omittedToolCount += 1
            phase = .usingTools
            return
        }
        tools.append(NoctisToolActivity(
            id: id, name: String(name.prefix(80)),
            input: NoctisToolActivitySummary.input(name: name, arguments: arguments),
            startedAt: date
        ))
        phase = .usingTools
    }

    private mutating func completeTool(id: String, name: String, result: String, isError: Bool, at date: Date) {
        // Some providers report only completion. Keep that evidence without inventing an input.
        if !tools.contains(where: { $0.id == id }) {
            guard tools.count < Self.toolLimit else { return }
            tools.append(NoctisToolActivity(id: id, name: String(name.prefix(80)), startedAt: date))
        }
        guard let index = tools.firstIndex(where: { $0.id == id }), tools[index].status == .running else { return }
        let summary = NoctisToolActivitySummary.result(name: name, result: result, isError: isError)
        tools[index].status = isError ? .failed : .completed
        tools[index].endedAt = date
        tools[index].output = summary.text
        tools[index].resultCount = summary.count
        tools[index].sources = summary.sources
        phase = activeTool == nil ? .thinking : .usingTools
    }
}

struct NoctisToolActivity: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case running, completed, failed, interrupted }

    var id: String
    var name: String
    var input: String?
    var output: String?
    var resultCount: Int?
    var sources: [NoctisActivitySource] = []
    var startedAt: Date
    var endedAt: Date?
    var status = Status.running
}

struct NoctisActivitySource: Codable, Equatable, Identifiable, Sendable {
    var url: URL
    var title: String

    var id: String { url.absoluteString }
    var host: String { url.host() ?? url.absoluteString }
}
