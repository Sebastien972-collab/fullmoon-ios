// Created by Sébastien DAGUIN
import Foundation

enum ModelRuntime: Equatable, Sendable {
    case automatic
    case foundationModels
    case mlx

    static var initial: Self {
        #if os(iOS)
        .automatic
        #else
        .mlx
        #endif
    }

    var title: LocalizedStringResource {
        switch self {
        case .automatic:
            "model.runtime.automatic.title"
        case .foundationModels:
            "model.runtime.foundation_models.title"
        case .mlx:
            #if os(iOS)
            "model.runtime.mlx_ios.title"
            #else
            "model.runtime.mlx.title"
            #endif
        }
    }
}
