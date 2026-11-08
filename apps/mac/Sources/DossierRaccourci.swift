import AppKit
import UniformTypeIdentifiers

enum SousDossier {
    static func valider(_ valeur: String) -> String? {
        let nom = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nom.unicodeScalars.count <= 100, nom.unicodeScalars.allSatisfy({ c in
            switch c.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
                return true
            default: return " -_'’(),&+".unicodeScalars.contains(c)
            }
        }) else { return nil }
        return nom
    }
}

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

    static func cible(dans base: URL, sousDossier: String) -> URL? {
        guard let nom = SousDossier.valider(sousDossier),
              let racine = valider(base),
              let cible = valider(nom.isEmpty ? base : base.appendingPathComponent(nom, isDirectory: true))
        else { return nil }
        let prefixe = racine.path.hasSuffix("/") ? racine.path : racine.path + "/"
        guard cible == racine || cible.path.hasPrefix(prefixe) else { return nil }
        return cible
    }

    @MainActor
    static func ouvrir(_ url: URL, completion: @escaping (Error?) -> Void) -> Bool {
        guard let cible = valider(url),
              let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        else { return false }
        NSWorkspace.shared.open([cible], withApplicationAt: finder, configuration: .init()) { _, erreur in
            completion(erreur)
        }
        return true
    }
}
