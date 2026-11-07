import AppKit
import Foundation

@main
struct HomeShortcutsTest {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let racine = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: racine, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: racine) }
        var total = 0
        func verifier(_ condition: Bool, _ nom: String) {
            precondition(condition, nom)
            total += 1
            print("  OK      \(nom)")
        }
        func dossier(_ nom: String) throws -> URL {
            let url = racine.appendingPathComponent(nom)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let normal = try dossier("Photos de famille")
        verifier(DossierRaccourci.valider(normal) == normal.resolvingSymlinksInPath(), "dossier normal accepté")
        let app = try dossier("X.app")
        verifier(DossierRaccourci.valider(app) == nil, "X.app refusé")
        let commande = racine.appendingPathComponent("X.command")
        try Data().write(to: commande)
        verifier(DossierRaccourci.valider(commande) == nil, "fichier X.command refusé")
        let panneau = try dossier("X.prefPane")
        verifier(DossierRaccourci.valider(panneau) == nil, "dossier .prefPane refusé")
        let lien = racine.appendingPathComponent("Lien")
        try fm.createSymbolicLink(at: lien, withDestinationURL: app)
        verifier(DossierRaccourci.valider(lien) == nil, "lien symbolique vers .app refusé")
        let fichier = racine.appendingPathComponent("ordinaire.txt")
        try Data().write(to: fichier)
        verifier(DossierRaccourci.valider(fichier) == nil, "fichier ordinaire refusé")
        verifier(DossierRaccourci.valider(racine.appendingPathComponent("absent")) == nil, "chemin absent refusé")
        verifier(DossierRaccourci.valider(URL(string: "https://example.com")!) == nil, "URL distante refusée")
        for ext in ["tool", "workflow", "pkg", "mpkg", "action", "bundle", "plugin", "kext", "appex", "saver", "qlgenerator", "mdimporter", "scpt", "terminal", "APP"] {
            let url = try dossier("X.\(ext)")
            verifier(DossierRaccourci.valider(url) == nil, "extension .\(ext) refusée")
        }
        let lienNormal = racine.appendingPathComponent("Lien normal")
        try fm.createSymbolicLink(at: lienNormal, withDestinationURL: normal)
        verifier(DossierRaccourci.valider(lienNormal) == normal.resolvingSymlinksInPath(), "lien vers un dossier normal résolu")

        let domaine = "test.raccourcis.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domaine)!
        defer { defaults.removePersistentDomain(forName: domaine) }
        let favoris = HomeShortcuts(defaults: defaults, demo: false)
        verifier(favoris.ajoutes.isEmpty, "stockage vide accepté")
        verifier(!favoris.ajouterDossier(lien), "ajout dangereux refusé")
        verifier(!favoris.ajouterAlbum(" \n "), "album vide refusé")
        verifier(favoris.ajouterDossier(normal), "ajout d'un dossier validé")
        verifier(favoris.ajouterAlbum("Petits-enfants"), "ajout explicite d'un album")
        let relu = HomeShortcuts(defaults: defaults, demo: false)
        verifier(relu.ajoutes == favoris.ajoutes, "stockage JSON relu")
        relu.retirer(relu.ajoutes[0])
        verifier(HomeShortcuts(defaults: defaults, demo: false).ajoutes.count == 1, "retrait enregistré")
        verifier(HomeShortcuts.echapperAlbum("a\"\\\n\r\t") == "a\\\"\\\\\\n\\r\\t", "nom d'album échappé")
        defaults.set(Data("JSON invalide".utf8), forKey: "raccourcisAccueil.v1")
        verifier(HomeShortcuts(defaults: defaults, demo: false).ajoutes.isEmpty, "JSON invalide ignoré")
        let demo = HomeShortcuts(defaults: defaults, demo: true)
        verifier(demo.tuiles.count == 7, "démo fixe indépendante du stockage")
        let album = demo.tuiles.first { $0.ajoutee }!
        demo.retirer(album)
        verifier(!demo.tuiles.contains(album), "retrait en démo sans stockage")
        print("\(total) contrôles raccourcis passés, 0 échec(s)")
    }
}
