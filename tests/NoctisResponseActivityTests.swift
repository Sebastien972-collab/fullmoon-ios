// Created by Sébastien DAGUIN

import Foundation
import Noctis

@main
struct NoctisResponseActivityTests {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    static func check(
        _ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        precondition(condition, message, file: file, line: line)
    }

    static func main() throws {
        initialAndInterleavedEvents()
        toolIdentityAndDuplicates()
        completionWithoutStart()
        terminalStates()
        restoredRunningActivity()
        try boundedActivity()
        try webSourceSummaries()
        try encoding()
        print("Response activity: ordering, lifecycle, bounds, source summaries and persistence tests passed")
    }

    static func initialAndInterleavedEvents() {
        var activity = NoctisResponseActivity(startedAt: start)
        check(activity.phase == .thinking && !activity.hasDetails, "A new response has no invented details")
        check(activity.reasoning.isEmpty && activity.tools.isEmpty, "Reasoning and tools require actual events")
        activity.observe(.textDelta("Visible answer"), at: start.addingTimeInterval(1))
        check(activity.phase == .responding && activity.reasoning.isEmpty, "Answer text is never reasoning")
        activity.observe(.reasoningDelta(""), at: start.addingTimeInterval(2))
        check(activity.phase == .responding, "An empty reasoning event must not reset the visible phase")
        activity.observe(.reasoningDelta("Compare the sources. "), at: start.addingTimeInterval(3))
        activity.observe(.reasoningDelta("Check their dates."), at: start.addingTimeInterval(4))
        check(activity.reasoning == "Compare the sources. Check their dates.", "Reasoning fragments preserve order")
        activity.observe(.toolStarted(id: "search-1", name: "web_search", arguments: #"{"query":"Swift release"}"#))
        activity.observe(.textDelta("Searching…"))
        check(activity.phase == .usingTools, "A text fragment must not hide a running tool")
        activity.observe(.reasoningDelta(" Verify the result."))
        check(activity.phase == .usingTools, "Reasoning must not hide a running tool")
        activity.observe(.toolCompleted(id: "search-1", name: "web_search", result: #"{"results":[]}"#, isError: false))
        check(activity.phase == .thinking && activity.activeTool == nil, "Tool completion returns to processing")
        activity.observe(.textDelta("Final answer"))
        check(activity.phase == .responding, "Subsequent answer text resumes the response phase")
        check(!activity.reasoning.contains("Visible answer") && !activity.reasoning.contains("Final answer"),
              "The reflection panel must remain separate from the answer")
    }

    static func toolIdentityAndDuplicates() {
        var activity = NoctisResponseActivity(startedAt: start)
        activity.observe(.toolStarted(id: "first", name: "web_search", arguments: #"{"query":"first query"}"#), at: start)
        activity.observe(.toolStarted(id: "second", name: "web_search", arguments: #"{"query":"second query"}"#),
                         at: start.addingTimeInterval(1))
        activity.observe(.toolStarted(id: "first", name: "web_open", arguments: #"{"url":"https://example.com"}"#))
        check(activity.tools.count == 2 && activity.tools[0].input == "first query", "Duplicate starts keep the original call")
        activity.observe(.toolCompleted(id: "second", name: "web_search", result: #"{"results":[]}"#, isError: true),
                         at: start.addingTimeInterval(2))
        check(activity.tools[1].status == .failed && activity.tools[0].status == .running,
              "A completion must match its call ID, including tools with the same name")
        check(activity.activeTool?.id == "first" && activity.phase == .usingTools, "Other calls can still be running")
        activity.observe(.toolCompleted(id: "first", name: "web_search", result: #"{"results":[]}"#, isError: false),
                         at: start.addingTimeInterval(3))
        check(activity.tools[0].status == .completed && activity.tools[0].resultCount == 0,
              "A successful empty search is distinct from a failed search")
        let finishedTool = activity.tools[1]
        activity.observe(.toolCompleted(id: "second", name: "web_search", result: "replacement", isError: false))
        activity.observe(.toolStarted(id: "second", name: "web_search", arguments: #"{"query":"replacement"}"#))
        check(activity.tools[1] == finishedTool, "Duplicate events must not reopen or rewrite a settled tool")
    }

    static func completionWithoutStart() {
        var activity = NoctisResponseActivity(startedAt: start)
        activity.observe(.toolCompleted(id: "completed-only", name: "web_open",
                                       result: #"{"title":"Official docs","url":"https://example.com/docs"}"#,
                                       isError: false), at: start.addingTimeInterval(2))
        check(activity.tools.count == 1 && activity.tools[0].status == .completed,
              "Providers that only emit completion still expose the actual tool result")
        check(activity.tools[0].input == nil, "Missing tool input must not be fabricated")
        check(activity.tools[0].output == "Official docs" && activity.tools[0].sources.count == 1,
              "A completed page open retains its public title and source")
    }

    static func terminalStates() {
        for outcome in [NoctisResponseActivity.Phase.completed, .interrupted, .failed] {
            var activity = NoctisResponseActivity(startedAt: start)
            activity.observe(.toolStarted(id: "unfinished", name: "web_search", arguments: "{}"), at: start)
            activity.finish(outcome, at: start.addingTimeInterval(10))
            check(activity.phase == outcome && activity.endedAt == start.addingTimeInterval(10),
                  "The terminal response outcome and elapsed time must remain stable")
            check(activity.tools[0].status == .interrupted && activity.activeTool == nil,
                  "A missing tool completion must never be reported as success")
            let settled = activity
            activity.observe(.reasoningDelta("Too late"))
            activity.observe(.toolCompleted(id: "unfinished", name: "web_search", result: "{}", isError: false))
            activity.observe(.textDelta("Too late"))
            activity.finish(.failed)
            check(activity == settled, "Late events and repeated finalization must not mutate a finished response")
        }
        var invalidOutcome = NoctisResponseActivity(startedAt: start)
        invalidOutcome.finish(.thinking, at: start)
        check(invalidOutcome.phase == .interrupted, "Finalization cannot leave an active phase")
    }

    static func restoredRunningActivity() {
        var activity = NoctisResponseActivity(startedAt: start)
        activity.observe(.toolStarted(id: "pending", name: "web_search", arguments: "{}"),
                         at: start.addingTimeInterval(2))
        check(activity.settledForDisplay(isStreaming: true) == activity, "An active response keeps its running state")
        let recovered = activity.settledForDisplay(isStreaming: false)
        check(recovered.phase == .interrupted && recovered.endedAt == activity.updatedAt,
              "A restored unfinished response must not display an endless spinner")
        check(recovered.tools[0].status == .interrupted && activity.phase == .usingTools,
              "Recovery is a display projection and must not mutate the persisted source")
    }

    static func boundedActivity() throws {
        var activity = NoctisResponseActivity(startedAt: start)
        activity.observe(.reasoningDelta(String(repeating: "a", count: NoctisResponseActivity.reasoningLimit + 32)))
        activity.observe(.reasoningDelta("More"))
        check(activity.reasoning.count == NoctisResponseActivity.reasoningLimit && activity.reasoningTruncated,
              "Long reflection must stop growing at the declared display limit")
        for index in 0..<(NoctisResponseActivity.toolLimit + 4) {
            activity.observe(.toolStarted(id: "tool-\(index)", name: "web_search",
                                          arguments: #"{"query":"test"}"#), at: start)
        }
        check(activity.tools.count == NoctisResponseActivity.toolLimit && activity.omittedToolCount == 4,
              "Tool history must be bounded and count omitted calls")
        activity.finish(.interrupted, at: start.addingTimeInterval(1))
        check(NoctisResponseActivity.decode(activity.encoded()) == activity, "Bounded traces must round-trip")
        let longInput = String(repeating: "q", count: 900)
        let arguments = try json(["query": longInput])
        check(NoctisToolActivitySummary.input(name: "web_search", arguments: arguments)?.count == 500,
              "Tool input summaries must be bounded")
        check(NoctisToolActivitySummary.input(name: "unknown", arguments: arguments) == nil,
              "Unknown tool arguments must not be persisted as raw payloads")
        check(NoctisToolActivitySummary.input(name: "web_search", arguments: String(repeating: "x", count: 262_145)) == nil,
              "Oversized tool payloads must be rejected before parsing")
    }

    static func webSourceSummaries() throws {
        let forbidden = ["javascript:alert(1)", "data:text/plain,secret", "file:///tmp/private", "oreus://callback",
                         "https://user:password@example.com/path", "https:///", String(repeating: "x", count: 2_049)]
        for value in forbidden {
            check(NoctisToolActivitySummary.webURL(value) == nil, "Invalid or credential-bearing source: \(value.prefix(60))")
        }
        let signed = NoctisToolActivitySummary.webURL("https://example.com/page?token=secret&view=full#private")
        check(signed?.absoluteString == "https://example.com/page", "Credentials and fragments must not be persisted in sources")
        let safe = NoctisToolActivitySummary.webURL("https://example.com/search?q=Swift#details")
        check(safe?.absoluteString == "https://example.com/search?q=Swift", "Ordinary useful query parameters should survive")
        let results: [[String: Any]] = [
            ["url": "https://example.com/one#first", "title": " First\u{0000} source "],
            ["url": "https://example.com/one#duplicate", "title": "Duplicate"],
            ["url": "file:///tmp/private", "title": "Rejected"],
            ["url": "https://user:secret@example.com", "title": "Rejected credentials"]
        ] + (0..<30).map { ["url": "https://example.com/page-\($0)", "title": "Source \($0)"] }
        let summary = NoctisToolActivitySummary.result(name: "web_search", result: try json(["results": results]), isError: false)
        check(summary.count == results.count && summary.sources.count == 8, "Count all results but keep only a bounded source list")
        check(summary.sources[0].title == "First source" && summary.sources[0].url.fragment == nil,
              "Source labels must strip controls and source URLs must strip fragments")
        check(Set(summary.sources.map(\.id)).count == summary.sources.count, "Sources must be deduplicated")
        let error = NoctisToolActivitySummary.result(name: "web_open", result: #"{"error":"password=secret"}"#, isError: true)
        check(error.text == nil && error.sources.isEmpty, "Raw failure payloads must not leak into stored summaries")
        let unknown = NoctisToolActivitySummary.result(name: "readFile", result: "Private file contents", isError: false)
        check(unknown.text == nil && unknown.sources.isEmpty, "The panel must not archive raw file bodies")
    }

    static func encoding() throws {
        var activity = NoctisResponseActivity(startedAt: start)
        activity.observe(.reasoningDelta("Actual model reflection"), at: start.addingTimeInterval(1))
        activity.observe(.toolStarted(id: "one", name: "web_search", arguments: #"{"query":"Swift"}"#), at: start)
        activity.observe(.toolCompleted(id: "one", name: "web_search",
                                       result: #"{"results":[{"url":"https://swift.org","title":"Swift"}]}"#,
                                       isError: false), at: start.addingTimeInterval(2))
        activity.finish(.completed, at: start.addingTimeInterval(3))
        let data = try JSONEncoder().encode(activity)
        check(NoctisResponseActivity.decode(data) == activity, "Activity JSON must preserve outcomes, dates and sources")
        check(NoctisResponseActivity.decode(nil) == nil, "Legacy messages have no invented activity")
        check(NoctisResponseActivity.decode(Data("invalid".utf8)) == nil, "Corrupt activity must not break the conversation")
        check(NoctisResponseActivity.decode(Data(repeating: 0, count: 2_000_001)) == nil,
              "Oversized activity snapshots must be rejected")
    }

    static func json(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
