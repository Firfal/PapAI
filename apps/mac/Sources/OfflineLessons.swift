import CryptoKit
import Foundation

/// Automates gardés sur le Mac pour marcher sans réseau : seulement ceux qui
/// n'ont besoin ni de Holo ni d'un fichier du serveur. Un automate ne contient
/// que des actions et des consignes : jamais de clé Wi-Fi ni d'identifiant.
enum OfflineLessons {
    static let needsServer: Set<String> = ["holo", "install_templates"]

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PapAI", isDirectory: true)
            .appendingPathComponent("automates-hors-ligne.json")
    }

    /// Empreinte de l'espace (le serveur et sa clé) : une liste ne sert que là où elle a été reçue.
    static func space(_ base: String) -> String {
        SHA256.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func usable(_ raw: [String: Any]) -> Bool {
        guard raw["id"] is String else { return false }
        let acts = raw["actions"] as? [[String: Any]] ?? []
        return !acts.contains { needsServer.contains($0["do"] as? String ?? "") }
    }

    static func save(_ data: Data, base: String) {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let out = try? JSONSerialization.data(withJSONObject: ["space": space(base),
                                                                    "lessons": list.filter(usable)]) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? out.write(to: file, options: .atomic)
    }

    static func load(base: String) -> [Lesson] {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              saved["space"] as? String == space(base),
              let list = saved["lessons"] as? [[String: Any]],
              let clean = try? JSONSerialization.data(withJSONObject: list.filter(usable)) else { return [] }
        return (try? JSONDecoder().decode([Lesson].self, from: clean)) ?? []
    }
}
