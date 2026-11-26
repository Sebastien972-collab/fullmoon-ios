#if os(iOS)
import SwiftUI

struct WorkspaceHome: View {
    let threads: [Thread]
    let generatingID: UUID?
    let open: (Thread) -> Void
    let showHistory: () -> Void
    let useShortcut: (WorkspaceShortcut) -> Void
    @State private var exploring = false
    @State private var pendingShortcut: WorkspaceShortcut?
    @AppStorage("noctis.home.pinnedShortcuts") private var pinList = "code,summarize,translate"
    @Environment(AppManager.self) private var manager

    private var pinned: [WorkspaceShortcut] {
        Array(pinList.split(separator: ",").compactMap { WorkspaceShortcut(rawValue: String($0)) }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let last = threads.first {
                    resumeCard(last)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        LunarIllustration()
                            .frame(width: 112, height: 76)
                            .accessibilityHidden(true)
                        Text(workspaceText("What’s on your mind?"))
                            .font(.largeTitle.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                }
                shortcuts
                if threads.count > 1 { recent }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .refreshable { showHistory() }
        .background(manager.appearance.theme.background)
        .navigationTitle("Noctis")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showHistory) { Label(workspaceText("History"), systemImage: "clock.arrow.circlepath") }
            }
        }
        .sheet(isPresented: $exploring, onDismiss: finishExploring) {
            NavigationStack {
                List(WorkspaceShortcut.allCases) { shortcut in
                    HStack {
                        Button {
                            pendingShortcut = shortcut
                            exploring = false
                        } label: {
                            Label(shortcut.title, systemImage: shortcut.icon)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        pinButton(shortcut)
                    }
                }
                .navigationTitle(Text(workspaceText("Explore")))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.button.close", systemImage: "xmark") { exploring = false }
                    }
                }
            }
            .noctisAppLock()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func finishExploring() {
        guard let shortcut = pendingShortcut else { return }
        pendingShortcut = nil
        useShortcut(shortcut)
    }

    private func resumeCard(_ thread: Thread) -> some View {
        Button { open(thread) } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label {
                        Text(workspaceText("Resume"))
                    } icon: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.body.weight(.medium))
                        .padding(10)
                        .background(.background, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(title(thread)).font(.title2.weight(.semibold)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let generatingID, thread.messages.contains(where: { $0.id == generatingID }) {
                    Label(workspaceText("Reply in progress"), systemImage: "waveform").font(.caption)
                } else {
                    Text(Self.activity(thread), style: .relative).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .foregroundStyle(.primary)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(workspaceText("Shortcuts")).font(.headline)
                Spacer()
                Button { exploring = true } label: {
                    Label(workspaceText("Explore"), systemImage: "safari")
                        .font(.subheadline).frame(minHeight: 44)
                }
            }
            if !pinned.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(pinned) { shortcut in
                            Button { useShortcut(shortcut) } label: {
                                Label(shortcut.title, systemImage: shortcut.icon)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(workspaceText("Unpin"), systemImage: "pin.slash") { remove(shortcut) }
                                ForEach(WorkspaceShortcut.allCases.filter { !pinned.contains($0) }) { next in
                                    Button { replace(shortcut, with: next) } label: {
                                        Label {
                                            Text(workspaceText("Replace with \(String(localized: next.title))"))
                                        } icon: { Image(systemName: next.icon) }
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func pinButton(_ item: WorkspaceShortcut) -> some View {
        if pinned.contains(item) {
            Button(workspaceText("Unpin"), systemImage: "pin.fill") { remove(item) }
                .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
        } else if pinned.count < 3 {
            Button(workspaceText("Pin"), systemImage: "pin") { write(pinned + [item]) }
                .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
        } else {
            Menu {
                ForEach(pinned) { old in
                    Button { replace(old, with: item) } label: {
                        Text(workspaceText("Replace \(String(localized: old.title))"))
                    }
                }
            } label: {
                Image(systemName: "pin").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text(workspaceText("Replace a pinned shortcut")))
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspaceText("Recent conversations")).font(.headline).padding(.bottom, 6)
            ForEach(Array(threads.dropFirst().prefix(3))) { thread in
                Button { open(thread) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left").foregroundStyle(.secondary)
                        Text(title(thread)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12).frame(minHeight: 48).contentShape(.rect)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func remove(_ item: WorkspaceShortcut) { write(pinned.filter { $0 != item }) }
    private func replace(_ item: WorkspaceShortcut, with next: WorkspaceShortcut) {
        write(pinned.map { $0 == item ? next : $0 })
    }

    private func write(_ items: [WorkspaceShortcut]) { pinList = items.map(\.rawValue).joined(separator: ",") }

    static func activity(_ thread: Thread) -> Date {
        thread.messages.lazy.map(\.timestamp).max() ?? thread.timestamp
    }

    private func title(_ thread: Thread) -> String {
        thread.title ?? thread.sortedMessages.first.map { String($0.content.prefix(100)) }
            ?? String(localized: "chats.default_title")
    }
}

/// A crescent and its orbit, drawn at the current display scale.
private struct LunarIllustration: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.46, y: size.height * 0.48)
            let radius = size.height * 0.32
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.drawLayer { moon in
                moon.clip(to: Path(ellipseIn: disc))
                moon.fill(Path(ellipseIn: disc), with: .foreground)
                moon.blendMode = .destinationOut
                moon.fill(Path(ellipseIn: disc.offsetBy(dx: radius * 0.45, dy: -radius * 0.32)), with: .color(.black))
            }
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(-18))
            let orbit = CGRect(x: -radius * 2, y: -radius * 0.45, width: radius * 4, height: radius * 0.9)
            context.stroke(Path(ellipseIn: orbit), with: .color(.secondary.opacity(0.55)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: orbit.maxX - 3, y: -3, width: 6, height: 6)), with: .foreground)
        }
    }
}
#endif
