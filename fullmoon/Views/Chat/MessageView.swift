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
    var usesChatGPTLayout = false

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
            } else if appearance.showAvatars && !usesChatGPTLayout {
                MessageAvatar(tint: appManager.appTintColor.getColor())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Header (Author + Timestamp)
                if !usesChatGPTLayout || appearance.showTimestamps {
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
                }

                // Message Body Bubble / Canvas
                messageBody
                    .padding(messagePadding)
                    .background {
                        MessageBubbleBackground(
                            isUser: isUser,
                            usesChatGPTLayout: usesChatGPTLayout,
                            appearance: appearance,
                            tint: appManager.appTintColor.getColor()
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                    .contextMenu {
                        MessageContextMenu(
                            content: message.content,
                            isUser: isUser,
                            onCopy: copyContent,
                            onRegenerate: onRegenerate,
                            onRetry: onRetry,
                            onEdit: onEdit,
                            onBranch: onBranch,
                            onRequestDelete: onDelete.map { _ in { showDeleteConfirmation = true } }
                        )
                    }
                    .intelligenceGlow(
                        colors: appearance.intelligenceGlowPalette.colors,
                        lineWidth: appearance.intelligenceGlowLineWidth,
                        cornerRadius: appearance.intelligenceGlowCornerRadius,
                        activeWhen: !usesChatGPTLayout
                            && appearance.aiEffectsEnabled && appearance.intelligenceGlowEnabled
                            && !isUser && isStreaming && (generationPhase?.isActive ?? false)
                    )

                // Status banner if interrupted or errored
                if message.hasError {
                    MessageErrorRecoveryBar(retryAction: onRetry ?? onRegenerate)
                } else if message.isInterrupted && !isStreaming {
                    MessageInterruptedBanner(onRegenerate: onRegenerate)
                }

                // Assistant Action Bar (Discreet, appears after completion)
                if !isUser && !isStreaming && !message.hasError {
                    MessageAssistantActions(
                        content: message.content,
                        copied: copied,
                        targetSize: actionTargetSize,
                        onCopy: copyContent,
                        onRegenerate: onRegenerate
                    )
                        .padding(.top, 2)
                        .padding(.leading, appearance.messageStyle == .bubbles ? 4 : 0)
                }
            }

            if !isUser && !usesChatGPTLayout {
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

    private var messagePadding: CGFloat {
        if usesChatGPTLayout { return isUser ? 14 : 0 }
        return appManager.appearance.messageStyle == .bubbles ? 14 : 4
    }

    private var userTextColor: Color {
        .primary
    }

    // MARK: - Helpers

    private var actionTargetSize: CGFloat { usesChatGPTLayout ? 44 : 32 }

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
