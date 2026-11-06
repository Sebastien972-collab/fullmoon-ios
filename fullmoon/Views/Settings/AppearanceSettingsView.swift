import AIEffectsKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppManager.self) private var appManager
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        @Bindable var manager = appManager
        Form {
            Section("appearance.section.theme") {
                Picker("appearance.picker.theme", selection: $manager.appearance.theme) {
                    ForEach(AppearanceTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("appearance.picker.accent", selection: $manager.appTintColor) {
                    ForEach(AppTintColor.allCases, id: \.self) { color in
                        Label(color.title, systemImage: "circle.fill").foregroundStyle(color.getColor()).tag(color)
                    }
                }
            }
            Section("appearance.section.conversations") {
                LabeledContent("appearance.text_size.label", value: "\(Int(manager.appearance.fontSize)) pt")
                Slider(value: $manager.appearance.fontSize, in: 13...24, step: 1) { Text("appearance.text_size.label") }
                Picker("appearance.picker.density", selection: $manager.appearance.density) {
                    ForEach(ChatDensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("appearance.picker.messages", selection: $manager.appearance.messageStyle) {
                    ForEach(MessageStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("appearance.picker.reading_width", selection: $manager.appearance.contentWidth) {
                    Text("appearance.reading_width.narrow").tag(640.0)
                    Text("appearance.reading_width.standard").tag(800.0)
                    Text("appearance.reading_width.wide").tag(1040.0)
                }
                Toggle("appearance.toggle.avatars", isOn: $manager.appearance.showAvatars)
                Toggle("appearance.toggle.timestamps", isOn: $manager.appearance.showTimestamps)
            }
            Section("appearance.section.visual_effects") {
                Toggle("appearance.toggle.liquid_glass", isOn: $manager.appearance.useGlass)
                Picker("appearance.picker.intensity", selection: $manager.appearance.intensity) {
                    ForEach(VisualIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("appearance.toggle.reduce_animations", isOn: $manager.appearance.reduceAnimations)
                Text("appearance.accessibility.description")
                    .font(.caption).foregroundStyle(.secondary)
            }
            AIEffectsSettingsSection(appearance: $manager.appearance)
            Section("appearance.section.ai_preview") {
                AIEffectsPreview(appearance: manager.appearance, fontSize: manager.appearance.fontSize * textScale)
            }
            Section("appearance.section.typography") {
                Picker("appearance.picker.font", selection: $manager.appFontDesign) {
                    ForEach(AppFontDesign.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("appearance.picker.font_width", selection: $manager.appFontWidth) {
                    ForEach(AppFontWidth.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(manager.appFontDesign != .standard)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("appearance.navigation.title")
    }
}

private struct AIEffectsSettingsSection: View {
    @Binding var appearance: ChatAppearance

    var body: some View {
        Section("appearance.section.ai_effects") {
            Toggle("appearance.toggle.ai_effects", isOn: $appearance.aiEffectsEnabled)
            if appearance.aiEffectsEnabled {
                Picker("appearance.picker.response_rendering", selection: $appearance.aiTextRenderingMode) {
                    ForEach(AITextRenderingMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("appearance.picker.text_animation", selection: $appearance.streamEffect) {
                    ForEach(AIStreamEffect.allCases) { Text($0.title).tag($0) }
                }
                Text(appearance.streamEffect.detail).font(.caption).foregroundStyle(.secondary)
                StreamEffectControls(appearance: $appearance)
                Toggle("appearance.toggle.thinking_indicator", isOn: $appearance.thinkingIndicatorEnabled)
                if appearance.thinkingIndicatorEnabled {
                    Stepper("appearance.thinking_indicator.dots \(appearance.thinkingDotCount)",
                                value: $appearance.thinkingDotCount, in: 2...6)
                    ValueSlider(title: "appearance.control.size",
                                value: $appearance.thinkingDotSize,
                                range: 3...12, step: 1, suffix: " pt")
                    ValueSlider(title: "appearance.control.spacing",
                                value: $appearance.thinkingSpacing,
                                range: 1...12, step: 1, suffix: " pt")
                    ValueSlider(title: "appearance.control.period",
                                value: $appearance.thinkingPeriodMilliseconds,
                                range: 500...2_500, step: 100, suffix: " ms")
                }
                Toggle("appearance.toggle.intelligence_glow", isOn: $appearance.intelligenceGlowEnabled)
                if appearance.intelligenceGlowEnabled {
                    Picker("appearance.picker.palette", selection: $appearance.intelligenceGlowPalette) {
                        ForEach(IntelligenceGlowPalette.allCases) { Text($0.title).tag($0) }
                    }
                    ValueSlider(title: "appearance.control.thickness",
                                value: $appearance.intelligenceGlowLineWidth,
                                range: 0.5...5, step: 0.5, suffix: " pt")
                    ValueSlider(title: "appearance.control.radius",
                                value: $appearance.intelligenceGlowCornerRadius,
                                range: 4...36, step: 1, suffix: " pt")
                    Text("appearance.intelligence_glow.description")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("appearance.button.reset_effects", role: .destructive) { appearance.resetEffects() }
        }
    }
}

private struct StreamEffectControls: View {
    @Binding var appearance: ChatAppearance
    var body: some View {
        switch appearance.streamEffect {
        case .none:
            EmptyView()
        case .trailingShimmer:
            Stepper("appearance.shimmer.window \(appearance.shimmerWindow)",
                        value: $appearance.shimmerWindow, in: 2...30)
            ValueSlider(title: "appearance.control.intensity",
                        value: $appearance.shimmerStrength,
                        range: 0.1...1, step: 0.05)
            ValueSlider(title: "appearance.control.period",
                        value: $appearance.shimmerPeriodMilliseconds,
                        range: 400...3_000, step: 100, suffix: " ms")
        case .typewriter:
            Toggle("appearance.toggle.typewriter_caret", isOn: $appearance.typewriterCaret)
        case .scramble:
            ValueSlider(title: "appearance.control.interval",
                        value: $appearance.scrambleIntervalMilliseconds,
                        range: 15...150, step: 5, suffix: " ms")
            ValueSlider(title: "appearance.control.probability",
                        value: $appearance.scrambleProbability,
                        range: 0.1...1, step: 0.05)
        default:
            ValueSlider(title: appearance.streamEffect == .skeleton
                        ? "appearance.control.stabilization" : "appearance.control.duration",
                        value: $appearance.effectDurationMilliseconds, range: 100...1_500, step: 20, suffix: " ms")
        }
    }
}

private struct ValueSlider: View {
    let title: LocalizedStringResource
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var suffix = ""

    var body: some View {
        LabeledContent(title, value: "\(Int(value))\(suffix)")
        Slider(value: $value, in: range, step: step) { Text(title) }
    }
}

private struct AIEffectsPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let appearance: ChatAppearance
    let fontSize: Double
    @State private var state = AIState()
    @State private var phase = AIPhase.idle
    @State private var run = 0
    private var sample: String { String(localized: "appearance.preview.sample") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appearance.aiEffectsEnabled && appearance.thinkingIndicatorEnabled && phase == .thinking {
                ThinkingIndicator(dotCount: appearance.thinkingDotCount, dotSize: appearance.thinkingDotSize,
                                  spacing: appearance.thinkingSpacing, period: .milliseconds(appearance.thinkingPeriodMilliseconds))
                    .aiState(state)
            }
            previewText
                .font(.system(size: fontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(reduceTransparency ? 0.35 : 0.18),
                            in: RoundedRectangle(cornerRadius: appearance.intelligenceGlowCornerRadius))
                .intelligenceGlow(colors: appearance.intelligenceGlowPalette.colors,
                                  lineWidth: appearance.intelligenceGlowLineWidth,
                                  cornerRadius: appearance.intelligenceGlowCornerRadius,
                                  activeWhen: appearance.aiEffectsEnabled && appearance.intelligenceGlowEnabled && phase.isActive)
            HStack {
                Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("appearance.preview.button.replay") { run += 1 }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .task(id: run) { await simulate() }
        .onDisappear { state.phase = .idle; phase = .idle }
    }

    @ViewBuilder private var previewText: some View {
        if phase == .thinking {
            Text("chat.status.thinking").foregroundStyle(.secondary)
        } else if appearance.aiEffectsEnabled && appearance.aiTextRenderingMode == .animatedText
                    && appearance.streamEffect != .none && !reduceMotion {
            StreamText.typing(sample, interval: .milliseconds(24), style: appearance.streamTextStyle).id(run)
        } else {
            Text(sample)
        }
    }
    private var phaseLabel: LocalizedStringResource {
        switch phase {
        case .idle, .listening: "appearance.preview.phase.ready"
        case .thinking: "appearance.preview.phase.thinking"
        case .streaming: "appearance.preview.phase.generating"
        case .done: "appearance.preview.phase.done"
        case .error: "appearance.preview.phase.error"
        }
    }
    private func simulate() async {
        phase = .thinking; state.phase = .thinking
        do {
            try await Task.sleep(for: .milliseconds(750))
            try Task.checkCancellation()
            phase = .streaming; state.phase = .streaming
            try await Task.sleep(for: reduceMotion ? .milliseconds(150) : .milliseconds(1_700))
            try Task.checkCancellation()
            phase = .done; state.phase = .done
        } catch { phase = .idle; state.phase = .idle }
    }
}

#Preview {
    NavigationStack { AppearanceSettingsView() }.environment(AppManager())
}
