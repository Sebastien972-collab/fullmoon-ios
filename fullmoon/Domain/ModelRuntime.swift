// Created by Sébastien DAGUIN
import Foundation

enum ModelRuntime: Equatable, Sendable {
    case automatic
    case foundationModels
    case mlx

    static var initial: Self {
        .mlx
    }

    var title: LocalizedStringResource {
        switch self {
        case .automatic:
            "model.runtime.automatic.title"
        case .foundationModels:
            "model.runtime.foundation_models.title"
        case .mlx:
            #if os(macOS)
            "model.runtime.mlx_macos.title"
            #else
            "model.runtime.mlx.title"
            #endif
        }
    }

    var settingsDescription: LocalizedStringResource {
        #if os(macOS)
        "model.runtime.macos.settings.description"
        #else
        "model.runtime.settings.description"
        #endif
    }
}
