#if os(iOS)
import SwiftUI

@MainActor
struct NoctisConversationList: View {
    @Environment(\.noctisPalette) private var palette
    @Binding var search: String
    let conversations: [NoctisConversationSummary]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onSettings: () -> Void
    let onLibrary: (() -> Void)?
    let onClose: (() -> Void)?

    private var filteredConversations: [NoctisConversationSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { $0.searchText.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            history
            Divider()
            drawerLink("settings.open", icon: .settings, action: onSettings)
                .accessibilityIdentifier("noctis.settings")
                .keyboardShortcut(",", modifiers: .command)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }

    private var header: some View {
        HStack(spacing: 10) {
            NoctisIcon(.moon, size: 28)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Noctis")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let onClose {
                NoctisToolbarButton(
                    icon: .back,
                    label: NoctisStrings.text("history.close"),
                    action: onClose
                )
                .accessibilityIdentifier("noctis.sidebar.close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func drawerLink(_ key: String, icon: NoctisIcon.Glyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(NoctisStrings.text(key))
                    .font(.body.weight(.medium))
            } icon: {
                NoctisIcon(icon)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            NoctisIcon(.search, size: 18)
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
                    NoctisIcon(.close, size: 18)
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
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                searchField.padding(.horizontal, 4)
                if let onLibrary {
                    drawerLink("library.title", icon: .library, action: onLibrary)
                        .accessibilityIdentifier("noctis.library")
                        .padding(.horizontal, 4)
                }
                Text(NoctisStrings.text("history.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, 12)
                    .padding(.top, 12)
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
            selectedID == conversation.id ? palette.accent.opacity(0.12) : .clear,
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
