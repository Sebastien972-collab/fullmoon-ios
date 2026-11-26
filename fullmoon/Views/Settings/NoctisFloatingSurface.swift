import SwiftUI

enum NoctisGlassStyle: CaseIterable {
    case standard, tinted, opaque

    var title: LocalizedStringResource {
        switch self {
        case .standard: LocalizedStringResource("Clear", table: "Settings")
        case .tinted: LocalizedStringResource("Tinted", table: "Settings")
        case .opaque: LocalizedStringResource("Reduced transparency", table: "Settings")
        }
    }
}

struct NoctisFloatingSurface: View {
    let cornerRadius: CGFloat
    var style: NoctisGlassStyle = .standard
    @Environment(AppManager.self) private var manager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || contrast == .increased || style == .opaque {
            shape.fill(manager.appearance.theme.surface)
                .overlay { shape.strokeBorder(.secondary.opacity(0.45), lineWidth: 1) }
        } else if #available(iOS 26, macOS 26, visionOS 26, *) {
            let tint = manager.resolvedAccent.opacity(0.16)
            Color.clear.glassEffect(style == .tinted ? .regular.tint(tint) : .regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay {
                    if style == .tinted {
                        shape.fill(manager.resolvedAccent.opacity(0.12))
                    }
                }
        }
    }
}
