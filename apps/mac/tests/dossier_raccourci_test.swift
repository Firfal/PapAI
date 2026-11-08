import AppKit
import Foundation

@main
struct DossierRaccourciTest {
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
        struct Cas: Decodable { var name: String; var valid: Bool }
        let chemin = CommandLine.arguments.dropFirst().first ?? "../../tests/subfolder_cases.json"
        let cas = try JSONDecoder().decode([Cas].self, from: Data(contentsOf: URL(fileURLWithPath: chemin)))
        for exemple in cas {
            verifier((SousDossier.valider(exemple.name) != nil) == exemple.valid,
                     "règle partagée : \(exemple.name.debugDescription)")
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
        verifier(DossierRaccourci.cible(dans: racine, sousDossier: "X.app") == nil, "automatisme .app refusé")
        verifier(DossierRaccourci.cible(dans: racine, sousDossier: "Photos de famille") == normal.resolvingSymlinksInPath(),
                 "automatisme simple accepté")
        verifier(DossierRaccourci.cible(dans: racine, sousDossier: "") == racine.resolvingSymlinksInPath(),
                 "automatisme racine accepté")
        let ailleurs = racine.appendingPathComponent("Applications")
        try fm.createSymbolicLink(at: ailleurs, withDestinationURL: URL(fileURLWithPath: "/Applications"))
        verifier(DossierRaccourci.cible(dans: racine, sousDossier: "Applications") == nil,
                 "lien vers Applications hors du dossier connu refusé")
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

        print("\(total) contrôles raccourcis passés, 0 échec(s)")
    }
}
