import Foundation

/// Un poste de l'organisation suivi par ce support : un ordinateur, son espace et sa clé.
/// La liste vient du serveur (`GET /o/<jeton support>/spaces`) : rien ne s'ajoute ni ne se retire ici.
struct Person: Equatable, Identifiable {
    var server: String
    var key: String
    /// Prénom de l'employé (compte de l'ordinateur), sinon vide.
    var name: String = ""
    /// Nom donné par le poste à son inscription (nom de l'ordinateur, service).
    var label: String = ""
    var helperId: String = ""
    var id: String { key }
}

enum People {
    static let max = 500
    private static let asking: Set<String> = ["waiting_consent", "planning", "awaiting_approval", "awaiting_helper"]

    /// Postes renvoyés par `/o/<jeton>/spaces`, sans doublon ; ce qu'on savait déjà (prénom
    /// appris par `hello`, identifiant de support) n'est pas effacé par du vide.
    static func fromSpaces(_ spaces: [[String: Any]], server: String, known: [Person]) -> [Person] {
        var seen = Set<String>()
        var out: [Person] = []
        for s in spaces {
            guard let k = s["key"] as? String, !k.isEmpty, k.count <= 200,
                  k.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }),
                  seen.insert(k).inserted else { continue }
            let old = known.first { $0.key == k }
            let name = (s["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (s["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Person(server: "\(server)/k/\(k)", key: k,
                              name: name.isEmpty ? (old?.name ?? "") : name,
                              label: label.isEmpty ? (old?.label ?? "") : label,
                              helperId: old?.helperId ?? ""))
            if out.count >= max { break }
        }
        return out
    }

    /// « Christine · Comptabilité » : prénom, puis le nom du poste s'il dit autre chose.
    static func title(_ p: Person) -> String {
        let n = p.name.isEmpty ? (p.label.isEmpty ? "Poste" : p.label) : p.name
        return n
    }

    static func detail(_ p: Person) -> String? {
        guard !p.label.isEmpty, !p.name.isEmpty, p.label != p.name else { return nil }
        return p.label
    }

    /// Une demande attend le support : aide demandée, plan à valider, question de Holo.
    static func isAsking(_ state: String?) -> Bool { state.map(asking.contains) ?? false }
}
