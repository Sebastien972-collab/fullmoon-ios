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
            "model.runtime.mlx.title"
        }
    }
}
