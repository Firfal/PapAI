import Foundation

/// Un utilisateur suivie par ce support : un ordinateur, son espace et sa clé.
struct Person: Codable, Equatable, Identifiable {
    var server: String
    var key: String
    var name: String = ""
    var helperId: String = ""
    var relation: String = ""
    var id: String { key }
}

enum People {
    static let max = 200
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

/// Une organisation (service IT) suivie par ce support : son jeton liste tous ses postes.
struct Org: Codable, Equatable {
    var server: String
    var token: String
    var name: String = ""
}

enum Orgs {
    static func valid(_ t: String) -> Bool {
        t.hasPrefix("sup-") && (14...104).contains(t.count)
            && t.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }

    /// Lien donné par l'IT : `https://…/o/sup-…`, `papai://org?u=…&t=sup-…`, ou le jeton seul.
    static func parse(_ input: String, officialHost: String) -> Org? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if valid(s) { return Org(server: "https://" + officialHost, token: s) }
        guard let c = URLComponents(string: s), let scheme = c.scheme?.lowercased() else { return nil }
        if scheme == "papai", c.host == "org" {
            let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard var base = q["u"], let t = q["t"], valid(t),
                  base.hasPrefix("https://") || base.hasPrefix("http://") else { return nil }
            while base.hasSuffix("/") { base.removeLast() }
            return Org(server: base, token: t)
        }
        let parts = c.path.split(separator: "/").map(String.init)
        guard ["https", "http"].contains(scheme), let h = c.host, parts.count == 2, parts[0] == "o", valid(parts[1]) else { return nil }
        return Org(server: "\(scheme)://\(h)" + (c.port.map { ":\($0)" } ?? ""), token: parts[1])
    }

    static func load() -> [Org] {
        guard let d = UserDefaults.standard.data(forKey: "orgs"),
              let list = try? JSONDecoder().decode([Org].self, from: d) else { return [] }
        var seen = Set<String>()
        return Array(list.filter { valid($0.token) && seen.insert($0.token).inserted }.prefix(10))
    }

    static func save(_ list: [Org]) {
        if let d = try? JSONEncoder().encode(Array(list.prefix(10))) { UserDefaults.standard.set(d, forKey: "orgs") }
    }
}
