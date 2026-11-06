//
//  ChatView+MessageActions.swift
//  fullmoon
//
//  Created by Sébastien DAGUIN
//

import Noctis
import SwiftData
import SwiftUI

extension ChatView.ViewModel {
    // MARK: - In-Place Regeneration & Retrying

    /// Regenerate an assistant message in place within the current conversation
    func regenerate(_ message: Message, in thread: Thread, context: ModelContext) {
        guard !isSending, isConnected else { return }
        let sorted = thread.sortedMessages
        guard let index = sorted.firstIndex(where: { $0.id == message.id }) else { return }

        let userMessage: Message
        let historyMessages: [Message]

        if message.role == .assistant {
            guard let userIndex = sorted[..<index].lastIndex(where: { $0.role == .user }) else { return }
            userMessage = sorted[userIndex]
            historyMessages = Array(sorted[..<userIndex])
        } else {
            userMessage = message
            historyMessages = Array(sorted[..<index])
        }

        let history = historyMessages.map { msg in
            let role: AIChatMessage.Role = switch msg.role {
            case .user: .user
            case .assistant: .assistant
            case .system: .system
            }
            return AIChatMessage(role: role, content: msg.content)
        }

        let targetResponse: Message
        if message.role == .assistant {
            targetResponse = message
        } else if index + 1 < sorted.count, sorted[index + 1].role == .assistant {
            targetResponse = sorted[index + 1]
        } else {
            targetResponse = Message(role: .assistant, content: "")
            context.insert(targetResponse)
            thread.messages.append(targetResponse)
        }
        targetResponse.content = ""
        targetResponse.isInterrupted = false
        targetResponse.hasError = false
        targetResponse.timestamp = Date()

        do {
            try context.save()
        } catch {
            submissionError = error.localizedDescription
            return
        }

        needsNewSession = true
        submissionError = nil
        startGeneration(
            text: userMessage.content,
            thread: thread,
            history: history,
            response: targetResponse,
            context: context
        )
    }

    /// Create a branch in a separate conversation from a given message
    func createBranch(from message: Message, in thread: Thread, context: ModelContext, select: (Thread) -> Void) {
        guard !isSending, isConnected,
              let index = thread.sortedMessages.firstIndex(where: { $0.id == message.id }),
              let userIndex = thread.sortedMessages[..<index].lastIndex(where: { $0.role == .user }) else { return }
        let messages = thread.sortedMessages
        let branch = Thread()
        branch.title = String(
            localized: "chat.branch.title \(String(messages[userIndex].content.prefix(60)))"
        )
        context.insert(branch)
        for original in messages[..<userIndex] {
            let copy = Message(role: original.role, content: original.content)
            context.insert(copy)
            branch.messages.append(copy)
        }
        let draft = prompt
        prompt = messages[userIndex].content
        needsNewSession = true
        send(to: branch, in: context, select: select)
        prompt = draft
    }

    // MARK: - Edit & Delete Messages

    /// Puts the user message content back into the prompt and cleans up the subsequent exchange for re-submission
    func editUserMessage(_ message: Message, in thread: Thread, context: ModelContext) {
        guard message.role == .user else { return }
        if isSending { stop() }
        prompt = message.content

        let sorted = thread.sortedMessages
        if let userIndex = sorted.firstIndex(where: { $0.id == message.id }) {
            // Remove following assistant message if present
            if userIndex + 1 < sorted.count && sorted[userIndex + 1].role == .assistant {
                let assistantMsg = sorted[userIndex + 1]
                if let aIndex = thread.messages.firstIndex(where: { $0.id == assistantMsg.id }) {
                    thread.messages.remove(at: aIndex)
                }
                context.delete(assistantMsg)
            }
            if let uIndex = thread.messages.firstIndex(where: { $0.id == message.id }) {
                thread.messages.remove(at: uIndex)
            }
            context.delete(message)
        }
        needsNewSession = true
        do {
            try context.save()
        } catch {
            submissionError = error.localizedDescription
        }
    }

    /// Deletes a single message
    func deleteMessage(_ message: Message, in thread: Thread, context: ModelContext) {
        if generatingMessageID == message.id {
            stop()
        }
        if let index = thread.messages.firstIndex(where: { $0.id == message.id }) {
            thread.messages.remove(at: index)
        }
        context.delete(message)
        needsNewSession = true
        do {
            try context.save()
        } catch {
            submissionError = error.localizedDescription
        }
    }
}
