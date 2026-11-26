#if os(iOS)
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct SpaceFileLabel: View {
    @Environment(AppManager.self) private var appManager
    let url: URL
    let card: Bool
    @State private var thumbnail: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if card {
                VStack(alignment: .leading, spacing: 8) {
                    appManager.appearance.theme.surface
                        .aspectRatio(1.45, contentMode: .fit)
                        .overlay {
                            if let thumbnail {
                                Image(uiImage: thumbnail).resizable().scaledToFill()
                            } else {
                                Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 20))
                        .accessibilityHidden(true)
                    title
                }
                .task(id: url) {
                    thumbnail = nil
                    let request = QLThumbnailGenerator.Request(
                        fileAt: url, size: CGSize(width: 220, height: 150), scale: displayScale,
                        representationTypes: .thumbnail
                    )
                    let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                    if !Task.isCancelled { thumbnail = result?.uiImage }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 48)
                        .background(.quaternary, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    title
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        if WorkspaceFiles.isCode(url) { return "curlybraces" }
        if WorkspaceFiles.isImage(url) { return "photo" }
        return "doc.text"
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: url.lastPathComponent)
                .font(.body.weight(.medium)).lineLimit(2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { typeLabel; dateLabel }
                VStack(alignment: .leading, spacing: 2) { typeLabel; dateLabel }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeLabel: some View {
        Text(verbatim: url.pathExtension.isEmpty
             ? WorkspaceFiles.type(of: url).localizedDescription ?? ""
             : url.pathExtension.uppercased())
    }

    @ViewBuilder private var dateLabel: some View {
        if let date = WorkspaceFiles.modificationDate(of: url) {
            Text(date, format: .dateTime.day().month(.abbreviated).year())
        }
    }
}

struct SpaceTextPreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var source: String?
    @State private var display = AttributedString()
    @State private var failure: String?
    @State private var truncated = false
    @State private var copied = false
    @State private var original: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    ContentUnavailableView {
                        Label(spaceText("Preview unavailable"), systemImage: "doc.questionmark")
                    } description: { Text(failure) } actions: {
                        Button(spaceText("Open original")) { original = url }
                    }
                } else if source != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if truncated {
                                Button(spaceText("Preview shortened · Open original")) { original = url }
                                    .font(.footnote)
                            }
                            Text(display)
                                .font(WorkspaceFiles.isCode(url) ? .system(.body, design: .monospaced) : .body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(20)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(spaceText("Close")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let source {
                            Button(copied ? spaceText("Copied") : spaceText("Copy preview"),
                                   systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = source
                                copied = true
                            }
                        }
                        ShareLink(item: url) { Label(spaceText("Share or export"), systemImage: "square.and.arrow.up") }
                    } label: {
                        Label(spaceText("File actions"), systemImage: "ellipsis.circle")
                    }
                }
            }
            .quickLookPreview($original)
            .task(id: url) {
                let file = url
                do {
                    let preview = try await Task.detached(priority: .userInitiated) {
                        try Self.read(file)
                    }.value
                    if !Task.isCancelled {
                        source = preview.source
                        display = preview.display
                        truncated = preview.truncated
                    }
                } catch { failure = error.localizedDescription }
            }
        }
    }

    private struct PreviewText {
        let source: String
        let display: AttributedString
        let truncated: Bool
    }

    private nonisolated static func read(_ url: URL) throws -> PreviewText {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 64 * 1024
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        var bytes = data.prefix(limit)
        if data.count > limit {
            // A UTF-8 scalar may extend past the preview boundary.
            while bytes.count >= limit - 3 && String(bytes: bytes, encoding: .utf8) == nil { bytes = bytes.dropLast() }
        }
        guard let source = String(bytes: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if !WorkspaceFiles.isCode(url) {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let markdown = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
            return PreviewText(source: source, display: markdown, truncated: data.count > limit)
        }
        let styled = NSMutableAttributedString(string: source)
        if let tokens {
            for match in tokens.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let color: UIColor
                if match.range(at: 1).location != NSNotFound {
                    color = .secondaryLabel
                } else if match.range(at: 2).location != NSNotFound {
                    color = .systemBrown
                } else {
                    color = .systemIndigo
                }
                styled.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        let highlighted = try AttributedString(styled, including: \.uiKit)
        return PreviewText(source: source, display: highlighted, truncated: data.count > limit)
    }

    private nonisolated static let tokens = try? NSRegularExpression(pattern:
        #"(//[^\n]*|/\*[\s\S]*?\*/)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|"#
        + #"\b(func|let|var|class|struct|if|else|return|for|while|import|def|const|function|true|false|null|nil)\b"#
    )
}

struct WorkspaceItemPicker: View {
    let section: WorkspaceSection
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [URL] = []
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List(items, id: \.self) { url in
                Button {
                    dismiss()
                    onPick(url)
                } label: { SpaceFileLabel(url: url, card: false) }
                .buttonStyle(.plain)
            }
            .overlay {
                if let failure {
                    ContentUnavailableView(spaceText("Couldn’t open Space"), systemImage: "exclamationmark.circle",
                                           description: Text(failure))
                } else if items.isEmpty {
                    ContentUnavailableView(spaceText("No items available"), systemImage: section.symbol)
                }
            }
            .navigationTitle(section.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(spaceText("Cancel")) { dismiss() } } }
            .onAppear {
                do {
                    items = try WorkspaceFiles.items(in: section)
                } catch { failure = error.localizedDescription }
            }
        }
    }
}
#endif
