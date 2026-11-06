//
//  ModelStatus.swift
//  fullmoon
//
//  Created by Sébastien DAGUIN
//

enum ModelStatus: Equatable {
    case notLoaded
    case downloading
    case loading
    case ready
    case failed(String)

    init(isConnected: Bool, isLoading: Bool, isDownloading: Bool, error: String?) {
        if isLoading {
            self = isDownloading ? .downloading : .loading
        } else if isConnected {
            self = .ready
        } else if let error {
            self = .failed(error)
        } else {
            self = .notLoaded
        }
    }

    var title: String {
        switch self {
        case .notLoaded: "Non chargé"
        case .downloading: "Téléchargement en cours"
        case .loading: "Chargement en cours"
        case .ready: "Prêt"
        case .failed: "Erreur"
        }
    }

    var isBusy: Bool {
        self == .downloading || self == .loading
    }

    var canLoad: Bool {
        switch self {
        case .notLoaded, .failed: true
        case .downloading, .loading, .ready: false
        }
    }
}
