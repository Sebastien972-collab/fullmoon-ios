#if os(iOS)
import SwiftUI

struct NoctisPalette {
    var canvas = Color(uiColor: .systemBackground)
    var surface = Color(uiColor: .secondarySystemBackground)
    var accent = Color.accentColor
}

extension EnvironmentValues {
    @Entry var noctisPalette = NoctisPalette()
}

public extension View {
    func noctisChatPalette(canvas: Color, surface: Color, accent: Color) -> some View {
        environment(\.noctisPalette, NoctisPalette(canvas: canvas, surface: surface, accent: accent))
    }
}

/// Keeps the upstream glass control treatment with an opaque accessibility fallback.
@MainActor
struct NoctisGlassSurface<Surface: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.noctisPalette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: Surface

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(palette.surface, in: shape)
                .overlay { shape.stroke(Color(uiColor: .separator), lineWidth: 0.5) }
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

@MainActor
struct NoctisToolbarButton: View {
    let icon: NoctisIcon.Glyph
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NoctisIcon(icon)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
                .modifier(NoctisGlassSurface(shape: Circle()))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
#endif
