#if os(iOS)
import SwiftUI

@MainActor
struct NoctisConversationList: View {
    @Binding var search: String
    let conversations: [NoctisConversationSummary]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onClose: (() -> Void)?

    private var filteredConversations: [NoctisConversationSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { $0.searchText.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Noctis")
                    .font(.title2.weight(.semibold))
                Spacer()
                if let onClose {
                    NoctisToolbarButton(
                        symbol: "xmark",
                        label: NoctisStrings.text("history.close"),
                        action: onClose
                    )
                    .accessibilityIdentifier("noctis.sidebar.close")
                }
            }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            searchField.padding(.horizontal, 12)
            Text(NoctisStrings.text("history.title"))
                .font(.headline)
                .padding(.horizontal, 16)
            history
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NoctisStyle.canvas)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(NoctisStrings.text("history.search"), text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("noctis.history.search")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NoctisStrings.text("history.clearSearch"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, search.isEmpty ? 12 : 0)
        .frame(minHeight: 44)
        .background(NoctisStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if filteredConversations.isEmpty {
                    Text(NoctisStrings.text(conversations.isEmpty ? "history.empty" : "history.noResults"))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
                ForEach(filteredConversations) { conversation in
                    conversationRow(conversation)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func conversationRow(_ conversation: NoctisConversationSummary) -> some View {
        HStack(spacing: 0) {
            Button {
                onSelect(conversation.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle(conversation))
                        .font(.body.weight(selectedID == conversation.id ? .semibold : .regular))
                        .lineLimit(2)
                    if !conversation.preview.isEmpty {
                        Text(conversation.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedID == conversation.id ? .isSelected : [])
            .accessibilityIdentifier("noctis.conversation.\(conversation.id.uuidString)")
            deleteMenu(conversation)
        }
        .background(
            selectedID == conversation.id ? Color.accentColor.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func deleteMenu(_ conversation: NoctisConversationSummary) -> some View {
        Menu {
            Button(NoctisStrings.text("history.delete"), systemImage: "trash", role: .destructive) {
                onDelete(conversation.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(NoctisStrings.text("history.actions"))
        .accessibilityValue(displayTitle(conversation))
    }

    private func displayTitle(_ conversation: NoctisConversationSummary) -> String {
        conversation.title.isEmpty ? NoctisStrings.text("conversation.untitled") : conversation.title
    }
}
#endif
