// Created by Sébastien DAGUIN

// This unfinished extraction duplicates the implementation that currently lives in
// MessageView.swift. Keep the draft source available without compiling it twice.
#if false

import AIEffectsKit
import MarkdownUI
import SwiftUI

extension MessageView {
    @ViewBuilder
    var messageBody: some View {
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
            } else if usesAnimatedText {
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

    func updateRenderingMode() {
        if usesAnimatedText {
            animatedText.reset()
            animatedTextRun += 1
            animatedText.update(with: message.content)
        } else {
            animatedText.finish()
            if !isUser { markdownContent = MarkdownContent(message.content) }
        }
    }

}

@MainActor
final class RenderingAnimatedTextRelay {
    private(set) var stream = AsyncStream<String> { $0.finish() }
    private var continuation: AsyncStream<String>.Continuation?
    private var delivered = ""

    func reset() {
        continuation?.finish()
        let pair = AsyncStream<String>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        delivered = ""
    }

    func update(with content: String) {
        guard let continuation else { return }
        guard content.hasPrefix(delivered) else {
            reset()
            self.continuation?.yield(content)
            delivered = content
            return
        }
        let suffix = content.dropFirst(delivered.count)
        guard !suffix.isEmpty else { return }
        continuation.yield(String(suffix))
        delivered = content
    }

    func finish() {
        continuation?.finish()
        continuation = nil
        delivered = ""
        stream = AsyncStream { $0.finish() }
    }
}
#endif
