// Created by Sébastien DAGUIN

import SwiftUI

struct NoctisToolActivityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tool: NoctisToolActivity
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    toolLabel
                    statusLabel
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    toolLabel
                    Spacer(minLength: 4)
                    statusLabel
                }
            }
            if let input = tool.input {
                Text(input)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let count = tool.resultCount {
                Text("activity.results.count \(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let output = tool.output {
                Text(output)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(tool.sources) { source in
                // Revalidate decoded snapshots too: only ordinary Web links are actionable.
                if let url = NoctisToolActivitySummary.webURL(source.url.absoluteString) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                Text(source.host)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                        .foregroundStyle(tint)
                        .padding(.vertical, 5)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
            }
            Text(tool.name)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .contain)
    }

    private var toolLabel: some View {
        Label(tool.displayName, systemImage: tool.symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusLabel: some View {
        Label(tool.statusTitle, systemImage: tool.statusSymbol)
            .font(.caption2)
            .foregroundStyle(tool.status == .failed ? Color.orange : .secondary)
    }
}

extension NoctisToolActivity {
    var displayName: String {
        switch name {
        case "web_search": String(localized: "activity.tool.web_search")
        case "web_open": String(localized: "activity.tool.web_open")
        case "listFiles": String(localized: "activity.tool.list_files")
        case "readFile": String(localized: "activity.tool.read_file")
        case "searchCode": String(localized: "activity.tool.search_code")
        default: name
        }
    }

    var progressTitle: String {
        switch name {
        case "web_search": String(localized: "activity.progress.web_search")
        case "web_open": String(localized: "activity.progress.web_open")
        default: String(localized: "activity.progress.tool \(displayName)")
        }
    }

    var symbol: String {
        switch name {
        case "web_search": "magnifyingglass"
        case "web_open": "globe"
        case "listFiles": "folder"
        case "readFile": "doc.text"
        case "searchCode": "curlybraces"
        default: "wrench.and.screwdriver"
        }
    }

    var statusTitle: String {
        switch status {
        case .running: String(localized: "activity.tool.running")
        case .completed: String(localized: "activity.tool.completed")
        case .failed: String(localized: "activity.tool.failed")
        case .interrupted: String(localized: "activity.tool.interrupted")
        }
    }

    var statusSymbol: String {
        switch status {
        case .running: "ellipsis.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .interrupted: "pause.circle"
        }
    }
}
