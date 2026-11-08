import Foundation

struct UserRequest: Decodable, Identifiable {
    struct Solution: Decodable {
        struct Source: Decodable {
            var title: String?
            var url: String?
        }
        var kind: String?
        var lesson: String?
        var title: String?
        var steps: [String]?
        var text: String?
        var sources: [Source]?
    }

    var id: String
    var task: String
    var status: String
    var created: TimeInterval?
    var solution: Solution?
    var relaunch: String?

    enum CodingKeys: String, CodingKey { case id, task, status, created, solution, relaunch }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        task = (try? c.decode(String.self, forKey: .task)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? "nouveau"
        created = try? c.decode(TimeInterval.self, forKey: .created)
        solution = try? c.decode(Solution.self, forKey: .solution)
        relaunch = try? c.decode(String.self, forKey: .relaunch)
    }

    var statusText: String {
        switch status {
        case "rdv": "Rendez-vous prévu"
        case "en_cours": "En cours"
        case "a_reprendre": "Interrompue"
        case "resolu": "Réglée"
        default: "En attente"
        }
    }

    var dateText: String {
        guard let created, created > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: created))
    }

    func relaunchID(availableIDs: Set<String>) -> String? {
        guard let relaunch, !relaunch.isEmpty, availableIDs.contains(relaunch) else { return nil }
        return relaunch
    }
}

struct UserRequestsResponse: Decodable {
    var requests: [UserRequest]
    enum CodingKeys: String, CodingKey { case requests }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decodeIfPresent([UserRequest].self, forKey: .requests) ?? []
        requests.removeAll { $0.id.isEmpty }
    }

    static let demo = #"""
    {"requests":[
      {"id":"r1","created":1794132000,"task":"Je voudrais imprimer un document","status":"resolu",
       "solution":{"kind":"automate","title":"Configurer mon imprimante","lesson":"print"},"relaunch":"print"},
      {"id":"r2","created":1794045600,"task":"Retrouver mes documents","status":"resolu",
       "solution":{"kind":"plan","steps":["Ouvrir le Finder","Ouvrir le dossier Documents"]},"relaunch":null},
      {"id":"r3","created":1793959200,"task":"Comment changer la taille du texte ?","status":"resolu",
       "solution":{"kind":"answer","text":"Ouvrez les Réglages, puis choisissez Très grande.",
                   "sources":[{"title":"Aide PapAI","url":"https://example.org/aide"}]},"relaunch":null},
      {"id":"r4","created":1793872800,"task":"Mon casque ne fonctionne plus","status":"en_attente","solution":null,"relaunch":null}
    ]}
    """#
}
