import AppKit
import Observation
import UniformTypeIdentifiers

enum DossierRaccourci {
    private static let interdites: Set<String> = [
        "app", "command", "tool", "prefpane", "workflow", "pkg", "mpkg", "action", "bundle", "plugin",
        "kext", "appex", "saver", "qlgenerator", "mdimporter", "scpt", "terminal"
    ]

    static func valider(_ url: URL) -> URL? {
        guard url.isFileURL, !interdites.contains(url.pathExtension.lowercased()) else { return nil }
        let cible = url.resolvingSymlinksInPath().standardizedFileURL
        guard !interdites.contains(cible.pathExtension.lowercased()),
              let valeurs = try? cible.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isApplicationKey]),
              valeurs.isDirectory == true, valeurs.isPackage == false, valeurs.isApplication == false
        else { return nil }
        return cible
    }
}

@MainActor @Observable
final class HomeShortcuts {
    enum Cible: Codable, Equatable {
        case application(String), dossier(String), album(String), message
    }

    struct Tuile: Identifiable, Codable, Equatable {
        var id: String
        var titre: String
        var symbole: String
        var cible: Cible
        var ajoutee = false
    }

    private(set) var ajoutes: [Tuile]
    private var dossiers: [Tuile] = []
    private var groupes: [Tuile] = []
    private let defaults: UserDefaults
    private let demo: Bool
    private static let cle = "raccourcisAccueil.v1"

    init(defaults: UserDefaults = .standard, demo: Bool = ProcessInfo.processInfo.environment["PAPAI_DEMO"] != nil) {
        self.defaults = defaults
        self.demo = demo
        ajoutes = defaults.data(forKey: Self.cle).flatMap { try? JSONDecoder().decode([Tuile].self, from: $0) } ?? []
    }

    var tuiles: [Tuile] {
        if demo {
            return [
                application("Mail", "com.apple.mail"), application("Photos", "com.apple.Photos"),
                application("Safari", "com.apple.Safari"),
                Tuile(id: "images", titre: "Images", symbole: "folder", cible: .dossier("/Users/demo/Pictures")),
                Tuile(id: "noel", titre: "Noël 2025", symbole: "photo.on.rectangle", cible: .dossier("/Users/demo/Pictures/Noël 2025")),
                Tuile(id: "album", titre: "Petits-enfants", symbole: "rectangle.stack", cible: .album("Petits-enfants"), ajoutee: true),
                nouveauMessage
            ]
        }
        let apps = AppUsage.shared.top.prefix(3).map { application($0.name, $0.bundle) }
        let mail = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") == nil ? [] : [nouveauMessage]
        return Array((apps + ajoutes + mail + groupes.prefix(1) + dossiers).prefix(8))
    }

    private var nouveauMessage: Tuile {
        Tuile(id: "message", titre: "Nouveau message", symbole: "square.and.pencil", cible: .message)
    }

    private func application(_ nom: String, _ bundle: String) -> Tuile {
        Tuile(id: bundle, titre: nom, symbole: "app", cible: .application(bundle))
    }

    func actualiser() {
        guard !demo else { return }
        let fm = FileManager.default
        let repertoires: [(FileManager.SearchPathDirectory, String)] = [
            (.picturesDirectory, "Images"), (.documentDirectory, "Documents"), (.downloadsDirectory, "Téléchargements")
        ]
        dossiers = repertoires.compactMap { repertoire, nom in
            guard let url = fm.urls(for: repertoire, in: .userDomainMask).first,
                  let cible = DossierRaccourci.valider(url) else { return nil }
            return Tuile(id: cible.path, titre: nom, symbole: "folder", cible: .dossier(cible.path))
        }
        guard let images = fm.urls(for: .picturesDirectory, in: .userDomainMask).first,
              let valide = DossierRaccourci.valider(images),
              let enfants = try? fm.contentsOfDirectory(at: valide, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { groupes = []; return }
        groupes = enfants.compactMap { DossierRaccourci.valider($0) }
            .filter { dossier in
                guard let fichiers = try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey], options: [.skipsHiddenFiles]) else { return false }
                return fichiers.contains { fichier in
                    guard let valeurs = try? fichier.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]) else { return false }
                    return valeurs.isRegularFile == true && valeurs.contentType?.conforms(to: .image) == true
                }
            }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return a == b ? $0.path < $1.path : a > b
            }
            .prefix(2).map { Tuile(id: $0.path, titre: $0.lastPathComponent, symbole: "photo.on.rectangle", cible: .dossier($0.path)) }
    }

    @discardableResult
    func ajouterDossier(_ url: URL) -> Bool {
        guard let cible = DossierRaccourci.valider(url) else { return false }
        ajouter(Tuile(id: UUID().uuidString, titre: cible.lastPathComponent, symbole: "folder", cible: .dossier(cible.path), ajoutee: true))
        return true
    }

    @discardableResult
    func ajouterAlbum(_ nom: String) -> Bool {
        let titre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titre.isEmpty else { return false }
        ajouter(Tuile(id: UUID().uuidString, titre: titre, symbole: "rectangle.stack", cible: .album(titre), ajoutee: true))
        return true
    }

    private func ajouter(_ tuile: Tuile) {
        guard !ajoutes.contains(where: { $0.cible == tuile.cible }) else { return }
        ajoutes.append(tuile)
        enregistrer()
    }

    func retirer(_ tuile: Tuile) {
        ajoutes.removeAll { $0.id == tuile.id }
        enregistrer()
    }

    private func enregistrer() {
        guard !demo, let donnees = try? JSONEncoder().encode(ajoutes) else { return }
        defaults.set(donnees, forKey: Self.cle)
    }

    static func echapperAlbum(_ nom: String) -> String {
        nom.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    func ouvrir(_ tuile: Tuile, notice: @escaping (String) -> Void) {
        switch tuile.cible {
        case .application(let bundle): ouvrirApplication(bundle, notice: notice)
        case .dossier(let chemin):
            guard let url = DossierRaccourci.valider(URL(fileURLWithPath: chemin)),
                  let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
            else { notice("Ce dossier n'est pas disponible ou ne peut pas être ouvert en toute sécurité."); return }
            NSWorkspace.shared.open([url], withApplicationAt: finder, configuration: .init()) { _, erreur in
                if erreur != nil { Task { @MainActor in notice("Je n'arrive pas à ouvrir ce dossier dans le Finder.") } }
            }
        case .message:
            guard let mail = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail"),
                  let url = URL(string: "mailto:") else { notice("Mail n'est pas disponible sur cet ordinateur."); return }
            NSWorkspace.shared.open([url], withApplicationAt: mail, configuration: .init()) { _, erreur in
                if erreur != nil { Task { @MainActor in notice("Je n'arrive pas à ouvrir un nouveau message dans Mail.") } }
            }
        case .album(let nom):
            guard tuile.ajoutee, ajoutes.contains(where: { $0.cible == .album(nom) }) || demo else {
                notice("Ajoutez vous-même cet album pour l'ouvrir ici."); return
            }
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") != nil else {
                notice("Photos n'est pas disponible sur cet ordinateur."); return
            }
            var erreur: NSDictionary?
            let script = NSAppleScript(source: "tell application \"Photos\" to spotlight album \"\(Self.echapperAlbum(nom))\"")
            _ = script?.executeAndReturnError(&erreur)
            if erreur != nil || script == nil {
                ouvrirApplication("com.apple.Photos", notice: notice)
                notice("Je n'ai pas pu ouvrir cet album. J'ouvre Photos à la place.")
            }
        }
    }

    private func ouvrirApplication(_ bundle: String, notice: @escaping (String) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            notice("Cette application n'est pas disponible sur cet ordinateur."); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, erreur in
            if erreur != nil { Task { @MainActor in notice("Je n'arrive pas à ouvrir cette application.") } }
        }
    }
}
