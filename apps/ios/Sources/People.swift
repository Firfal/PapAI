import Foundation

/// Une personne aidée suivie par ce support : un ordinateur, son espace et sa clé.
struct Person: Codable, Equatable, Identifiable {
    var server: String
    var key: String
    var name: String = ""
    var helperId: String = ""
    var relation: String = ""
    var id: String { key }
}

enum People {
    static let max = 50
    private static let asking: Set<String> = ["waiting_consent", "planning", "awaiting_approval", "awaiting_helper"]

    static func load() -> [Person] {
        guard let d = UserDefaults.standard.data(forKey: "people"),
              let list = try? JSONDecoder().decode([Person].self, from: d) else { return [] }
        var seen = Set<String>()
        return Array(list.filter { !$0.server.isEmpty && !$0.key.isEmpty && seen.insert($0.key).inserted }.prefix(max))
    }

    static func save(_ list: [Person]) {
        if let d = try? JSONEncoder().encode(Array(list.prefix(max))) { UserDefaults.standard.set(d, forKey: "people") }
    }

    /// Ajoute ou met à jour la personne de même clé, sans effacer par du vide ce qu'on savait.
    static func upsert(_ list: [Person], _ p: Person) -> [Person] {
        var out = list
        guard let i = out.firstIndex(where: { $0.key == p.key }) else { return Array((out + [p]).prefix(max)) }
        let old = out[i]
        out[i] = Person(server: p.server, key: p.key,
                        name: p.name.isEmpty ? old.name : p.name,
                        helperId: p.helperId.isEmpty ? old.helperId : p.helperId,
                        relation: p.relation.isEmpty ? old.relation : p.relation)
        return out
    }

    /// Une demande attend le support : aide demandée, plan à valider, question de Holo.
    static func isAsking(_ state: String?) -> Bool { state.map(asking.contains) ?? false }
}
