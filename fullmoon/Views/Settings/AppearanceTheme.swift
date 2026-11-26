import SwiftUI

enum AppearanceMode: String, CaseIterable, Codable {
    case system, light, dark

    var title: LocalizedStringResource {
        switch self {
        case .system: "appearance.theme.system"
        case .light: "appearance.theme.light"
        case .dark: "appearance.theme.dark"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppearanceTheme: String, CaseIterable, Codable {
    case noctis, catppuccin, rosePine, everforest

    var name: String {
        switch self {
        case .noctis: "Noctis"
        case .catppuccin: "Catppuccin"
        case .rosePine: "Rosé Pine"
        case .everforest: "Everforest"
        }
    }

    private var colors: ThemeColors {
        switch self {
        case .noctis:
            ThemeColors(
                background: .init(light: 0xF6F7FB, dark: 0x000000),
                surface: .init(light: 0xE8EBF3, dark: 0x191C29),
                accent: .init(light: 0x3D518A, dark: 0xB2C3FF)
            )
        case .catppuccin:
            ThemeColors(
                background: .init(light: 0xEFF1F5, dark: 0x1E1E2E),
                surface: .init(light: 0xE6E9EF, dark: 0x313244),
                accent: .init(light: 0x8131E5, dark: 0xCBA6F7)
            )
        case .rosePine:
            ThemeColors(
                background: .init(light: 0xFAF4ED, dark: 0x191724),
                surface: .init(light: 0xFFFAF3, dark: 0x26233A),
                accent: .init(light: 0x9B4D64, dark: 0xEBBCBA)
            )
        case .everforest:
            ThemeColors(
                background: .init(light: 0xFDF6E3, dark: 0x2D353B),
                surface: .init(light: 0xF4F0D9, dark: 0x343F44),
                accent: .init(light: 0x607024, dark: 0xA7C080)
            )
        }
    }

    var background: Color { Color(colors.background) }
    var surface: Color { Color(colors.surface) }
    var accent: Color { Color(colors.accent) }

    /// Before palettes and modes were independent, both were stored in a French theme name.
    static func decodeSelection(_ storedTheme: String?) -> (theme: Self, mode: AppearanceMode) {
        switch storedTheme {
        case "Clair": (.noctis, .light)
        case "Sombre", "Noir profond": (.noctis, .dark)
        case "Crépuscule": (.rosePine, .dark)
        case "Forêt": (.everforest, .light)
        default: (storedTheme.flatMap(Self.init(rawValue:)) ?? .noctis, .system)
        }
    }
}

private struct ThemeColors {
    let background: ThemeColorPair
    let surface: ThemeColorPair
    let accent: ThemeColorPair
}

private struct ThemeColorPair: ShapeStyle, Hashable {
    let light: UInt32
    let dark: UInt32

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let rgb = environment.colorScheme == .dark ? dark : light
        return Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        ).resolve(in: environment)
    }
}

struct ContrastingSymbolColor: ShapeStyle {
    let background: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        let color = background.resolve(in: environment)
        let luminance = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return luminance > 0.179 ? .black : .white
    }
}
