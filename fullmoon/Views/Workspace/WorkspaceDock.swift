#if os(iOS)
import SwiftUI

struct WorkspaceDock<RecentMenu: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(AppManager.self) private var manager
    @Binding var selection: WorkspaceTab
    let onCreate: () -> Void
    @ViewBuilder let recentMenu: (WorkspaceTab) -> RecentMenu

    var body: some View {
        HStack(spacing: 2) {
            tab(.home)
            tab(.projects)
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ContrastingSymbolColor(background: manager.appTintColor.getColor()))
                    .frame(width: 44, height: 44)
                    .background(manager.appTintColor.getColor(), in: Circle())
            }
            .accessibilityLabel(Text(workspaceText("Create")))
            .padding(.horizontal, 4)
            tab(.space)
            tab(.settings)
        }
        .buttonStyle(.plain)
        .padding(4)
        .background { NoctisFloatingSurface(cornerRadius: 32) }
        .frame(maxWidth: 490)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(workspaceText("Tabs")))
        .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            var direction = value.translation.width < 0 ? 1 : -1
            if layoutDirection == .rightToLeft { direction *= -1 }
            if let next = WorkspaceTab(rawValue: selection.rawValue + direction) { selection = next }
        })
    }

    private func tab(_ item: WorkspaceTab) -> some View {
        let active = selection == item
        return Button { selection = item } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .symbolVariant(active ? .fill : .none)
                    .font(.body.weight(active ? .semibold : .regular))
                if !typeSize.isAccessibilitySize {
                    Text(item.title).font(.caption2.weight(active ? .semibold : .regular)).lineLimit(1)
                }
            }
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if active { Capsule().fill(.secondary.opacity(0.13)) }
            }
            .contentShape(.rect)
        }
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .accessibilityIdentifier("workspace.tab.\(item)")
        .contextMenu { recentMenu(item) }
    }
}
#endif
