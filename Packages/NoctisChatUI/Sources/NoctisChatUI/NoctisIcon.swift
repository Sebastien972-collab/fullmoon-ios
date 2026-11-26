import SwiftUI

/// Template icons from Tabler Icons v3.34.1. Label the enclosing control for VoiceOver.
public struct NoctisIcon: View {
    public enum Glyph: String, Sendable {
        case moon = "moon-stars"
        case menu = "menu-2"
        case newConversation = "edit"
        case settings, search
        case back = "chevron-left"
        case close = "x"
        case plus, microphone
        case send = "arrow-up"
        case stop = "player-stop-filled"
        case folder
        case library = "books"
    }

    private let glyph: Glyph
    private let size: CGFloat

    public init(_ glyph: Glyph, size: CGFloat = 22) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        Image(decorative: "tabler-\(glyph.rawValue)", bundle: .module)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .flipsForRightToLeftLayoutDirection(glyph == .back)
            .accessibilityHidden(true)
    }
}
