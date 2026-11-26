//
//  MessageComponents.swift
//  fullmoon
//
//  Created by Xavier on 16/12/2024.
//  Extracted from MessageView.swift.
//

import NoctisChatUI
import SwiftUI

struct MessageAvatar: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary.opacity(0.6))
            NoctisIcon(.moon, size: 17)
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct MessageBubbleBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let isUser: Bool
    let usesChatGPTLayout: Bool
    let appearance: ChatAppearance
    let tint: Color

    var body: some View {
        if usesChatGPTLayout {
            if isUser {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(appearance.theme.surface)
            }
        } else if appearance.messageStyle == .bubbles {
            if isUser {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .fill(tint.opacity(userBubbleOpacity))
            } else {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .fill(appearance.theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5)
                    }
            }
        }
    }

    private var userBubbleOpacity: Double {
        switch appearance.intensity {
        case .subtle: return 0.14
        case .balanced: return 0.22
        case .expressive: return 0.32
        }
    }

}

struct MessageErrorRecoveryBar: View {
    let retryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("message.error.description")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let retryAction {
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
}

struct MessageInterruptedBanner: View {
    let onRegenerate: (() -> Void)?

    var body: some View {
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
}

struct MessageAssistantActions: View {
    #if os(iOS)
    @Environment(\.replySpeaker) private var speaker
    #endif
    let content: String
    let spokenReplyID: UUID?
    let copied: Bool
    let targetSize: CGFloat
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Copy
            Button {
                onCopy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    if copied {
                        Text("common.status.copied").font(.caption2)
                    }
                }
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(minWidth: targetSize, minHeight: targetSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("message.button.copy.accessibility.label")

            #if os(iOS)
            if let speaker, let spokenReplyID, content.contains(where: { !$0.isWhitespace }) {
                let isReading = speaker.currentMessageID == spokenReplyID
                Button {
                    speaker.toggle(messageID: spokenReplyID, text: content)
                } label: {
                    Image(systemName: isReading ? "stop.fill" : "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(isReading ? Color.accentColor : Color.secondary)
                        .frame(minWidth: targetSize, minHeight: targetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(speaker.isDictating)
                .accessibilityLabel(isReading
                    ? Text("Stop reading", tableName: "MessageActions")
                    : Text("Read aloud", tableName: "MessageActions"))
            }
            #endif

            // Regenerate
            if let onRegenerate {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: targetSize, minHeight: targetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("message.button.regenerate.accessibility.label")
            }

            // Share
            ShareLink(item: content) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: targetSize, minHeight: targetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("message.button.share.accessibility.label")
        }
        .padding(.horizontal, 4)
    }
}

struct MessageContextMenu: View {
    let content: String
    let isUser: Bool
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?
    let onRetry: (() -> Void)?
    let onEdit: (() -> Void)?
    let onBranch: (() -> Void)?
    let onRequestDelete: (() -> Void)?

    var body: some View {
        Button {
            onCopy()
        } label: {
            Label("message.context_menu.copy", systemImage: "doc.on.doc")
        }

        ShareLink(item: content) {
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

        if let onRequestDelete {
            Button(role: .destructive, action: onRequestDelete) {
                Label("common.button.delete", systemImage: "trash")
            }
        }
    }
}
