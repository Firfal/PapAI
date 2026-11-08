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

    static func usable(_ raw: [String: Any]) -> Bool {
        guard raw["id"] is String else { return false }
        let acts = raw["actions"] as? [[String: Any]] ?? []
        return !acts.contains { needsServer.contains($0["do"] as? String ?? "") }
    }

    static func save(_ data: Data) {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let out = try? JSONSerialization.data(withJSONObject: list.filter(usable)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? out.write(to: file, options: .atomic)
    }

    static func load() -> [Lesson] {
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let clean = try? JSONSerialization.data(withJSONObject: list.filter(usable)) else { return [] }
        return (try? JSONDecoder().decode([Lesson].self, from: clean)) ?? []
    }
}
