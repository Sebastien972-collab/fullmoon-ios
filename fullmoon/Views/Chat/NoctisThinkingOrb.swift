import SwiftUI

/// A decorative, theme-aware activity light. Its clock only runs while visible and active.
struct NoctisThinkingOrb: View {
    let tint: Color
    var isAnimating = true
    var reduceMotion = false
    var isWorking = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    @State private var isVisible = false
    @State private var accumulatedTime: TimeInterval = 0
    @State private var animationStarted: Date?

    private var shouldAnimate: Bool {
        isVisible && isAnimating && !reduceMotion && !systemReduceMotion && scenePhase == .active
    }

    private var usesSolidAppearance: Bool {
        reduceTransparency || contrast == .increased
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { context in
            let time = elapsed(at: context.date)
            let breath = sin(time * 1.9)

            ZStack {
                if !usesSolidAppearance {
                    halo(breath: breath)
                }

                sphere(time: time)
                    .scaleEffect(1 + breath * (isWorking ? 0.045 : 0.025))

                orbit(time: time)

                Circle()
                    .fill(usesSolidAppearance ? Color.primary : tint)
                    .frame(width: isWorking ? 3 : 2.4, height: isWorking ? 3 : 2.4)
                    .offset(x: cos(time * 1.25) * 15, y: sin(time * 1.25) * 10)
            }
            .frame(width: 34, height: 34)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            updateClock(isRunning: false)
        }
        .onChange(of: shouldAnimate, initial: true) { _, isRunning in
            updateClock(isRunning: isRunning)
        }
    }

    private func halo(breath: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [tint.opacity(isWorking ? 0.30 : 0.20), tint.opacity(0)],
                center: .center,
                startRadius: 6,
                endRadius: 17
            ))
            .scaleEffect(1 + breath * 0.06)
    }

    private func sphere(time: TimeInterval) -> some View {
        Circle()
            .fill(colorScheme == .dark ? Color.black : Color.white)
            .overlay {
                Circle().fill(sphereGradient(time: time))
            }
            .overlay {
                Circle().strokeBorder(
                    usesSolidAppearance ? Color.primary : tint.opacity(0.45),
                    lineWidth: usesSolidAppearance ? 1.2 : 0.6
                )
            }
            .overlay {
                Circle()
                    .trim(from: 0.54, to: 0.82)
                    .stroke(
                        Color.white.opacity(usesSolidAppearance ? 1 : 0.75),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                    )
                    .padding(3)
                    .rotationEffect(.degrees(sin(time * 0.55) * 18))
            }
            .frame(width: 22, height: 22)
    }

    private func sphereGradient(time: TimeInterval) -> RadialGradient {
        let highlight = usesSolidAppearance ? Color.white : Color.white.opacity(0.94)
        return RadialGradient(
            colors: [highlight, tint, tint.opacity(usesSolidAppearance ? 1 : 0.36)],
            center: UnitPoint(x: 0.30 + sin(time * 0.6) * 0.07, y: 0.26 + cos(time * 0.5) * 0.04),
            startRadius: 0,
            endRadius: 24
        )
    }

    private func orbit(time: TimeInterval) -> some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(
                    orbitGradient,
                    style: StrokeStyle(lineWidth: usesSolidAppearance ? 1.4 : 1, lineCap: .round)
                )
                .frame(width: 31, height: 31)
                .scaleEffect(x: 1, y: 0.65)
                .rotationEffect(.degrees(time * 29 - 35))

            Circle()
                .trim(from: 0.06, to: 0.30)
                .stroke(
                    usesSolidAppearance ? Color.primary : tint.opacity(isWorking ? 0.82 : 0.46),
                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
                )
                .frame(width: 33, height: 33)
                .rotationEffect(.degrees(-time * 41 + 70))
        }
    }

    private var orbitGradient: AngularGradient {
        let colors: [Color] = usesSolidAppearance
            ? [.primary, tint, .primary]
            : [tint.opacity(0.12), tint, tint.opacity(0.70), tint.opacity(0.08)]
        return AngularGradient(colors: colors, center: .center)
    }

    private func elapsed(at date: Date) -> TimeInterval {
        accumulatedTime + (animationStarted.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    private func updateClock(isRunning: Bool) {
        if isRunning {
            if animationStarted == nil { animationStarted = .now }
        } else if let started = animationStarted {
            accumulatedTime += max(0, Date.now.timeIntervalSince(started))
            animationStarted = nil
        }
    }
}

#Preview("Activity · Light") {
    HStack(spacing: 32) {
        NoctisThinkingOrb(tint: .indigo)
        NoctisThinkingOrb(tint: .teal, isWorking: true)
        NoctisThinkingOrb(tint: .orange, reduceMotion: true)
    }
    .padding(32)
    .preferredColorScheme(.light)
}

#Preview("Activity · Dark") {
    HStack(spacing: 32) {
        NoctisThinkingOrb(tint: .purple)
        NoctisThinkingOrb(tint: .cyan, isWorking: true)
        NoctisThinkingOrb(tint: .orange, reduceMotion: true)
    }
    .padding(32)
    .preferredColorScheme(.dark)
}
