import SwiftUI

/// The lunar mark used on the welcome and onboarding screens.
public struct NoctisEmblem: View {
    private let tint: Color

    public init(tint: Color) {
        self.tint = tint
    }

    public var body: some View {
        NoctisIcon(.moon, size: 46)
            .foregroundStyle(tint)
            .frame(width: 84, height: 84)
            .background(tint.opacity(0.10), in: Circle())
            .overlay { Circle().strokeBorder(tint.opacity(0.24), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}
