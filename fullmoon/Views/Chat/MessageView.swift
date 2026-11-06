//
//  MessageView.swift
//  fullmoon
//
//  Created by Xavier on 16/12/2024.
//

import AIEffectsKit
import MarkdownUI
import SwiftUI

struct MessageView: View {
    @Environment(AppManager.self) private var appManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    let message: Message
    var isStreaming = false
    var generationPhase: AIPhase? = nil
    var onRegenerate: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onBranch: (() -> Void)? = nil

    @State private var copied = false
    @State private var showDeleteConfirmation = false
    @State private var responseVisible = false
    @State private var markdownContent = MarkdownContent("")
    @State private var effectState = AIState()
    @State private var animatedText = AnimatedTextRelay()
    @State private var animatedTextRun = 0

    private var isUser: Bool {
        message.role == .user
    }

    private var reducesAnimations: Bool {
        reduceMotion || appManager.appearance.reduceAnimations
    }

    private var authorName: LocalizedStringResource {
        isUser ? "message.author.user" : "message.author.assistant"
    }

    var body: some View {
        let appearance = appManager.appearance

        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 32)
            } else if appearance.showAvatars {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Header (Author + Timestamp)
                HStack(spacing: 6) {
                    Text(authorName)
                        .font(.caption.weight(.semibold))
                    if appearance.showTimestamps {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                    }
                    if isStreaming && !isUser {
                        Image(systemName: "ellipsis")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(appManager.appTintColor.getColor())
                            .symbolEffect(.variableColor.iterative, options: .repeating,
                                          isActive: !reducesAnimations)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, appearance.messageStyle == .bubbles ? 4 : 0)

                // Message Body Bubble / Canvas
                messageBody
                    .padding(appearance.messageStyle == .bubbles ? 14 : 4)
                    .background {
                        bubbleBackground
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                    .contextMenu {
                        messageContextMenu
                    }
                    .intelligenceGlow(
                        colors: appearance.intelligenceGlowPalette.colors,
                        lineWidth: appearance.intelligenceGlowLineWidth,
                        cornerRadius: appearance.intelligenceGlowCornerRadius,
                        activeWhen: appearance.aiEffectsEnabled && appearance.intelligenceGlowEnabled
                            && !isUser && isStreaming && (generationPhase?.isActive ?? false)
                    )

                // Status banner if interrupted or errored
                if message.hasError {
                    errorRecoveryBar
                } else if message.isInterrupted && !isStreaming {
                    interruptedBanner
                }

                // Assistant Action Bar (Discreet, appears after completion)
                if !isUser && !isStreaming && !message.hasError {
                    assistantActions
                        .padding(.top, 2)
                        .padding(.leading, appearance.messageStyle == .bubbles ? 4 : 0)
                }
            }

            if !isUser {
                Spacer(minLength: 24)
            }
        }
        .confirmationDialog(
            "message.delete.confirmation.title",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("common.button.delete", role: .destructive) {
                onDelete?()
            }
            Button("common.button.cancel", role: .cancel) {}
        } message: {
            Text("message.delete.confirmation.description")
        }
        .onChange(of: message.content, initial: true) { _, content in
            if !isUser {
                markdownContent = MarkdownContent(content)
                if isStreaming {
                    animatedText.update(with: content)
                }
            }
        }
        .onChange(of: isStreaming, initial: true) { _, streaming in
            if streaming {
                animatedText.reset()
                animatedTextRun += 1
                animatedText.update(with: message.content)
            } else {
                animatedText.finish()
            }
        }
        .onChange(of: generationPhase, initial: true) { _, phase in
            effectState.phase = phase ?? .idle
        }
        .onDisappear {
            animatedText.finish()
            effectState.phase = .idle
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(.quaternary.opacity(0.6))
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(appManager.appTintColor.getColor())
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    // MARK: - Message Content

    @ViewBuilder
    private var messageBody: some View {
        let appearance = appManager.appearance

        VStack(alignment: .leading, spacing: 8) {
            if isUser {
                Text(message.content)
                    .font(.system(size: appearance.fontSize * textScale))
                    .foregroundStyle(userTextColor)
                    .textSelection(.enabled)
            } else if isStreaming && message.content.isEmpty {
                if appearance.aiEffectsEnabled && appearance.thinkingIndicatorEnabled {
                    HStack(spacing: 8) {
                        ThinkingIndicator(
                            dotCount: appearance.thinkingDotCount,
                            dotSize: appearance.thinkingDotSize,
                            spacing: appearance.thinkingSpacing,
                            period: .milliseconds(appearance.thinkingPeriodMilliseconds)
                        )
                        Text("chat.status.thinking").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .aiState(effectState)
                    .padding(.vertical, 4)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("chat.status.thinking").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if isStreaming && appearance.aiEffectsEnabled
                        && appearance.aiTextRenderingMode == .animatedText
                        && appearance.streamEffect != .none && !reducesAnimations {
                StreamText(animatedText.stream, style: appearance.streamTextStyle)
                    .id(animatedTextRun)
                    .font(.system(size: appearance.fontSize * textScale))
                    .textSelection(.enabled)
            } else {
                // MarkdownUI preserves unchanged blocks; keep the same renderer when streaming ends.
                Markdown(markdownContent)
                    .markdownTextStyle {
                        FontSize(appearance.fontSize * textScale)
                    }
                    .markdownBlockStyle(\.codeBlock) { configuration in
                        MessageCodeBlock(configuration: configuration)
                    }
                    .textSelection(.enabled)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                    .opacity(responseVisible || reducesAnimations ? 1 : 0)
                    .animation(reducesAnimations ? nil : .easeOut(duration: 0.18), value: responseVisible)
                    .onAppear { responseVisible = true }
                    .onDisappear { responseVisible = false }
            }
        }
    }

    // MARK: - Bubble Background

    @ViewBuilder
    private var bubbleBackground: some View {
        let appearance = appManager.appearance

        if appearance.messageStyle == .bubbles {
            if isUser {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .fill(appManager.appTintColor.getColor().opacity(userBubbleOpacity))
            } else {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .fill(assistantBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
                    }
            }
        }
    }

    private var userBubbleOpacity: Double {
        switch appManager.appearance.intensity {
        case .subtle: return 0.14
        case .balanced: return 0.22
        case .expressive: return 0.32
        }
    }

    private var assistantBubbleFill: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var userTextColor: Color {
        .primary
    }

    // MARK: - Error & Interrupted States

    @ViewBuilder
    private var errorRecoveryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("message.error.description")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let retryAction = onRetry ?? onRegenerate {
                Button(action: retryAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("common.button.retry")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var interruptedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "stop.circle")
                .font(.caption2)
            Text("message.interrupted.description")
                .font(.caption2)
            Spacer()
            if let onRegenerate {
                Button("message.button.resume", action: onRegenerate)
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Assistant Actions Strip

    @ViewBuilder
    private var assistantActions: some View {
        HStack(spacing: 8) {
            // Copy
            Button {
                copyContent()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    if copied {
                        Text("common.status.copied").font(.caption2)
                    }
                }
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("message.button.copy.accessibility.label")

            // Regenerate
            if let onRegenerate {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("message.button.regenerate.accessibility.label")
            }

            // Share
            ShareLink(item: message.content) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("message.button.share.accessibility.label")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var messageContextMenu: some View {
        Button {
            copyContent()
        } label: {
            Label("message.context_menu.copy", systemImage: "doc.on.doc")
        }

        ShareLink(item: message.content) {
            Label("common.button.share", systemImage: "square.and.arrow.up")
        }

        if isUser {
            if let onEdit {
                Button(action: onEdit) {
                    Label("message.context_menu.edit_prompt", systemImage: "pencil")
                }
            }
            if let onRetry {
                Button(action: onRetry) {
                    Label("message.context_menu.resend", systemImage: "arrow.clockwise")
                }
            }
        } else {
            if let onRegenerate {
                Button(action: onRegenerate) {
                    Label("message.context_menu.regenerate", systemImage: "arrow.clockwise")
                }
            }
            if let onBranch {
                Button(action: onBranch) {
                    Label("message.context_menu.create_variant", systemImage: "arrow.triangle.branch")
                }
            }
        }

        Divider()

        if onDelete != nil {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("common.button.delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func copyContent() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #else
        UIPasteboard.general.string = message.content
        #endif
        appManager.playHaptic()
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var accessibilityDescription: String {
        let author = String(localized: authorName)
        if appManager.appearance.showTimestamps {
            let time = message.timestamp.formatted(date: .omitted, time: .shortened)
            return String(localized: "message.accessibility.with_time \(author) \(time) \(message.content)")
        }
        if isStreaming {
            return String(localized: "message.accessibility.streaming \(author) \(message.content)")
        } else if message.hasError {
            return String(localized: "message.accessibility.error \(author) \(message.content)")
        } else if message.isInterrupted {
            return String(localized: "message.accessibility.interrupted \(author) \(message.content)")
        } else {
            return String(localized: "message.accessibility.default \(author) \(message.content)")
        }
    }
}

private final class AnimatedTextRelay: @unchecked Sendable {
    private(set) var stream: AsyncStream<String>
    private var continuation: AsyncStream<String>.Continuation?
    private var delivered = ""

    init() {
        let pair = AsyncStream<String>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func reset() {
        continuation?.finish()
        let pair = AsyncStream<String>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        delivered = ""
    }

    func update(with content: String) {
        guard content.hasPrefix(delivered) else {
            reset()
            continuation?.yield(content)
            delivered = content
            return
        }
        let suffix = content.dropFirst(delivered.count)
        guard !suffix.isEmpty else { return }
        continuation?.yield(String(suffix))
        delivered = content
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
