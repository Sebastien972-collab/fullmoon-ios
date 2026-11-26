#if os(iOS)
import SwiftUI

@MainActor
enum NoctisStyle {
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let separator = Color(uiColor: .separator)
}

/// Keeps the upstream glass control treatment with an opaque accessibility fallback.
@MainActor
struct NoctisGlassSurface<Surface: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(NoctisStyle.surface, in: shape)
                .overlay { shape.stroke(NoctisStyle.separator, lineWidth: 0.5) }
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

@MainActor
struct NoctisToolbarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
                .modifier(NoctisGlassSurface(shape: Circle()))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
#endif
