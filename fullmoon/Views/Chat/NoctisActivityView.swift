// Created by Sébastien DAGUIN

import SwiftUI

/// The live status stays compact; the user can inspect the actual model/tool events.
struct NoctisActivityView: View {
    let activity: NoctisResponseActivity
    let isStreaming: Bool
    let tint: Color
    var reduceMotion = false
    var animate = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isExpanded = false

    init(
        activity: NoctisResponseActivity, isStreaming: Bool, tint: Color,
        reduceMotion: Bool = false, animate: Bool = true, initiallyExpanded: Bool = false
    ) {
        self.activity = activity
        self.isStreaming = isStreaming
        self.tint = tint
        self.reduceMotion = reduceMotion
        self.animate = animate
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var snapshot: NoctisResponseActivity { activity.settledForDisplay(isStreaming: isStreaming) }
    private var isActive: Bool { isStreaming && snapshot.phase.isActive }
    private var reducesAnimations: Bool { reduceMotion || systemReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.hasDetails {
                Button {
                    withAnimation(reducesAnimations ? nil : .easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded
                    ? String(localized: "activity.expanded") : String(localized: "activity.collapsed"))
                .accessibilityHint(Text(isExpanded
                    ? LocalizedStringKey("activity.hide_details") : LocalizedStringKey("activity.show_details")))
            } else {
                header
            }

            if isExpanded && snapshot.hasDetails {
                details
                    .padding(.leading, 17)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(tint.opacity(0.25))
                            .frame(width: 2)
                            .padding(.leading, 1)
                    }
                    .transition(.opacity)
            } else if isActive, let preview = previewText {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if isActive {
                NoctisThinkingOrb(
                    tint: tint, isAnimating: animate, reduceMotion: reducesAnimations,
                    isWorking: snapshot.activeTool != nil
                )
            } else {
                Image(systemName: terminalSymbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(snapshot.phase == .failed ? Color.orange : tint)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isActive && !snapshot.tools.isEmpty {
                    Text("activity.tools.count \(snapshot.tools.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            NoctisActivityElapsed(startedAt: snapshot.startedAt, endedAt: snapshot.endedAt)
                .foregroundStyle(.secondary)
            if snapshot.hasDetails {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !snapshot.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("activity.reasoning.title", systemImage: "sparkle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(snapshot.reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if snapshot.reasoningTruncated {
                        Text("activity.reasoning.truncated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(snapshot.tools) { tool in
                NoctisToolActivityRow(tool: tool, tint: tint)
            }
            if snapshot.omittedToolCount > 0 {
                Text("activity.tools.more \(snapshot.omittedToolCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch snapshot.phase {
        case .thinking: String(localized: "activity.phase.thinking")
        case .usingTools: snapshot.activeTool?.progressTitle ?? String(localized: "activity.phase.tools")
        case .responding: String(localized: "activity.phase.responding")
        case .completed: String(localized: "activity.phase.completed")
        case .interrupted: String(localized: "activity.phase.interrupted")
        case .failed: String(localized: "activity.phase.failed")
        }
    }

    private var terminalSymbol: String {
        switch snapshot.phase {
        case .interrupted: "pause.circle"
        case .failed: "exclamationmark.circle"
        default: "checkmark.circle"
        }
    }

    private var previewText: String? {
        if let input = snapshot.activeTool?.input { return input }
        guard snapshot.phase == .thinking, !snapshot.reasoning.isEmpty else { return nil }
        return String(snapshot.reasoning.suffix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NoctisActivityElapsed: View {
    let startedAt: Date
    let endedAt: Date?

    var body: some View {
        Group {
            if let endedAt {
                Text(elapsed(to: endedAt))
            } else {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(elapsed(to: context.date))
                }
            }
        }
        .font(.caption.monospacedDigit())
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func elapsed(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
