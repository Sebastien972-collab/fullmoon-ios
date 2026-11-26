#if DEBUG
import Noctis
import SwiftUI

/// Explicit fixture data for Xcode previews and optional simulator interface captures.
/// These samples never load a model, run a tool, or write conversation data.
enum NoctisActivityPreviewScenario: String {
    case thinking, searching, completed, failed, interrupted

    var isStreaming: Bool { self == .thinking || self == .searching }
}

struct NoctisActivityPreviewScreen: View {
    let scenario: NoctisActivityPreviewScenario
    let reduceMotion: Bool
    let animate: Bool
    private let activity: NoctisResponseActivity

    init(
        scenario: NoctisActivityPreviewScenario = .searching,
        reduceMotion: Bool = false,
        animate: Bool = true
    ) {
        self.scenario = scenario
        self.reduceMotion = reduceMotion
        self.animate = animate
        activity = NoctisActivityPreviewFixtures.make(scenario)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(verbatim: "Comment rendre l’animation de Noctis plus accessible ?")
                        .font(.body)
                        .padding(14)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    NoctisActivityView(
                        activity: activity,
                        isStreaming: scenario.isStreaming,
                        tint: .indigo,
                        reduceMotion: reduceMotion,
                        animate: animate,
                        initiallyExpanded: true
                    )

                    if scenario == .completed {
                        Text(verbatim: "L’indicateur accompagne les étapes de la réponse. "
                             + "Lorsque les animations sont réduites, il conserve une forme fixe et lisible.")
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Noctis")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .environment(\.locale, Locale(identifier: "fr"))
    }
}

private enum NoctisActivityPreviewFixtures {
    static func make(_ scenario: NoctisActivityPreviewScenario, now: Date = .now) -> NoctisResponseActivity {
        let start = now.addingTimeInterval(-12)
        var activity = NoctisResponseActivity(startedAt: start)
        activity.observe(.reasoningDelta(
            "Je consulte les recommandations d’accessibilité et les API d’animation SwiftUI. "
                + "Je vais vérifier le comportement attendu lorsque les animations sont réduites."
        ), at: start.addingTimeInterval(0.2))
        guard scenario != .thinking else { return activity }

        activity.observe(.toolStarted(
            id: "preview-search", name: "web_search",
            arguments: #"{"query":"SwiftUI animation accessibility Reduce Motion"}"#
        ), at: start.addingTimeInterval(1))
        if scenario == .failed {
            activity.observe(.toolCompleted(
                id: "preview-search", name: "web_search",
                result: #"{"error":"Preview search failure"}"#, isError: true
            ), at: start.addingTimeInterval(3))
            activity.finish(.failed, at: start.addingTimeInterval(3))
            return activity
        }

        activity.observe(.toolCompleted(
            id: "preview-search", name: "web_search", result: searchResults, isError: false
        ), at: start.addingTimeInterval(4))
        activity.observe(.toolStarted(
            id: "preview-open", name: "web_open",
            arguments: #"{"url":"https://developer.apple.com/documentation/swiftui/timelineview"}"#
        ), at: start.addingTimeInterval(5))
        if scenario == .interrupted {
            activity.finish(.interrupted, at: start.addingTimeInterval(7))
        } else if scenario == .completed {
            complete(&activity, start: start)
        }
        return activity
    }

    private static func complete(_ activity: inout NoctisResponseActivity, start: Date) {
        activity.observe(.toolCompleted(
            id: "preview-open", name: "web_open", result: openedPage, isError: false
        ), at: start.addingTimeInterval(8))
        activity.observe(.textDelta("L’indicateur accompagne les étapes de la réponse."),
                         at: start.addingTimeInterval(9))
        activity.finish(.completed, at: start.addingTimeInterval(12))
    }

    private static let searchResults = #"""
    {"results":[
      {"title":"accessibilityReduceMotion",
       "url":"https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion"},
      {"title":"TimelineView",
       "url":"https://developer.apple.com/documentation/swiftui/timelineview"}
    ]}
    """#

    private static let openedPage = #"""
    {"title":"TimelineView","url":"https://developer.apple.com/documentation/swiftui/timelineview"}
    """#
}

#Preview("Activity · Live research") {
    NoctisActivityPreviewScreen(scenario: .searching)
        .preferredColorScheme(.light)
}

#Preview("Activity · Completed") {
    NoctisActivityPreviewScreen(scenario: .completed)
}

#Preview("Activity · Failed") {
    NoctisActivityPreviewScreen(scenario: .failed)
}

#Preview("Activity · Interrupted") {
    NoctisActivityPreviewScreen(scenario: .interrupted)
}

#Preview("Activity · Dark, reduced motion") {
    NoctisActivityPreviewScreen(scenario: .searching, reduceMotion: true)
        .preferredColorScheme(.dark)
}

#Preview("Activity · Accessibility text") {
    NoctisActivityPreviewScreen(scenario: .thinking, reduceMotion: true)
        .dynamicTypeSize(.accessibility3)
}
#endif
