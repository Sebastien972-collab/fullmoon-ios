//
//  ModelStatusTests.swift
//  fullmoon
//
//  Created by Sébastien DAGUIN
//

@main
struct ModelStatusTests {
    static func main() {
        let initial = ModelStatus(isConnected: false, isLoading: false, isDownloading: false, error: nil)
        assert(initial == .notLoaded, "Un cache non vérifié ne doit pas être présenté comme absent")
        assert(initial.canLoad)
        assert(initial.title == "Non chargé")

        let downloading = ModelStatus(isConnected: false, isLoading: true, isDownloading: true, error: nil)
        assert(downloading == .downloading)
        assert(downloading.isBusy && !downloading.canLoad)
        let loading = ModelStatus(isConnected: false, isLoading: true, isDownloading: false, error: nil)
        assert(loading == .loading, "La fin du téléchargement ne signifie pas que le modèle est prêt")
        assert(loading.isBusy && !loading.canLoad)

        let ready = ModelStatus(isConnected: true, isLoading: false, isDownloading: true, error: nil)
        assert(ready == .ready, "Une ancienne phase de téléchargement ne doit pas masquer le succès")
        assert(!ready.isBusy && !ready.canLoad)
        assert(ready.title == "Prêt")

        let failed = ModelStatus(isConnected: false, isLoading: false, isDownloading: true, error: "Hors ligne")
        assert(failed == .failed("Hors ligne"), "Une ancienne phase ne doit pas masquer l'erreur")
        assert(!failed.isBusy && failed.canLoad)
        assert(failed.title == "Erreur")
        let retry = ModelStatus(isConnected: false, isLoading: true, isDownloading: false, error: "Hors ligne")
        assert(retry == .loading, "La reprise doit présenter la nouvelle tentative")
        let connected = ModelStatus(isConnected: true, isLoading: false, isDownloading: false, error: "Ancienne erreur")
        assert(connected == .ready, "Une erreur de conversation ne doit pas déconnecter le modèle")
        print("Model status tests passed")
    }
}
