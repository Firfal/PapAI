import Foundation
import Observation

// Partagé avec le mode support de l'app Mac (apps/mac/project.yml) : les données
// de l'accueil du support (tickets, bibliothèque d'automates), sans écran.

// MARK: - Tickets

struct SupportTicketSuggestion: Identifiable {
    var id: String
    var title: String
}

/// Un ticket d'un utilisateur (`GET …/k/<clé>/tickets`), avec la personne d'où il vient.
struct SupportTicket: Identifiable {
    var id: String { person.key + "/" + tid }
    var tid: String
    var number: Int
    var task: String
    var status: String
    var source: String
    var updated: Double
    var created: Double
    var rdv: Double?
    var assignee: String
    /// Où un automate s'est arrêté : « Étape 2 (Ouvrir Photos) : bouton introuvable ».
    var blocked: String?
    var suggestions: [SupportTicketSuggestion] = []
    var suggestionLancee: String?
    var category: String
    var categoryBy: String
    var resolved: Double?
    var person: Person
    /// Demande d'automate : le plan proposé par Holo, à valider pour créer l'automate.
    var plan: (titre: String, etapes: [String])?

    var label: String { String(format: "T-%04d", number) }
    var isOpen: Bool { status != "resolu" }
    /// « Prendre en charge » et « Clore » : ticket ouvert hors assistance en cours.
    var canTake: Bool { isOpen && status != "en_cours" }
    var personName: String { person.name.isEmpty ? "Utilisateur" : person.name }

    init?(_ d: [String: Any], person: Person) {
        guard let id = d["id"] as? String else { return nil }
        tid = id
        number = (d["number"] as? NSNumber)?.intValue ?? 0
        task = d["task"] as? String ?? ""
        status = d["status"] as? String ?? "nouveau"
        source = d["source"] as? String ?? ""
        updated = (d["updated"] as? NSNumber)?.doubleValue ?? 0
        created = (d["created"] as? NSNumber)?.doubleValue ?? updated
        rdv = (d["rdv"] as? NSNumber)?.doubleValue
        assignee = d["assignee"] as? String ?? ""
        if let b = d["blocked"] as? [String: Any], let n = (b["step"] as? NSNumber)?.intValue {
            let label = (b["label"] as? String).flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
            let reason = (b["reason"] as? String).flatMap { $0.isEmpty ? nil : " : \($0)" } ?? ""
            blocked = "Bloqué à l’étape \(n)\(label)\(reason)"
        }
        suggestions = (d["suggestions"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
            return SupportTicketSuggestion(id: id, title: title)
        }
        suggestionLancee = d["suggestion_lancee"] as? String
        category = d["category"] as? String ?? "autre"
        categoryBy = d["category_by"] as? String ?? ""
        resolved = (d["resolved"] as? NSNumber)?.doubleValue
        if let a = d["automate"] as? [String: Any] {
            plan = (a["title"] as? String ?? "Nouvel automate", a["steps"] as? [String] ?? [])
        }
        self.person = person
    }

    /// Libellé et ton de la pastille d'état.
    var statut: (texte: String, ton: TonPastille) {
        switch status {
        case "nouveau": ("Nouveau", .bleu)
        case "en_attente": ("En attente", .orange)
        case "rdv": ("Rendez-vous", .violet)
        case "en_cours": ("En cours", .vert)
        case "a_reprendre": ("À reprendre", .orange)
        case "resolu": ("Résolu", .gris)
        default: (status, .gris)
        }
    }

    var quand: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM 'à' HH:mm"
        if status == "rdv", let r = rdv { return "Rendez-vous le " + f.string(from: Date(timeIntervalSince1970: r)) }
        return "Mis à jour le " + f.string(from: Date(timeIntervalSince1970: updated))
    }
}

/// Tous les tickets formulés par tous les utilisateurs reliés à ce support,
/// les plus récents d'abord, et les actions dessus (`POST …/tickets/<id>`).
@MainActor
@Observable
final class TicketBoard {
    var tickets: [SupportTicket] = []
    var loading = false
    var errors: [String] = []
    /// Ticket dont une action est en cours d'envoi.
    var busy: String?

    var openCount: Int { tickets.filter(\.isOpen).count }

    func load(_ people: [Person]) async {
        guard !people.isEmpty else { tickets = []; errors = []; return }
        loading = true; defer { loading = false }
        var all: [SupportTicket] = []
        var errs: [String] = []
        await withTaskGroup(of: ([SupportTicket], String?).self) { g in
            for p in people {
                g.addTask {
                    guard let url = URL(string: AutomateLibrary.base(p) + "/tickets"),
                          let (d, r) = try? await URLSession.shared.data(from: url),
                          (r as? HTTPURLResponse)?.statusCode == 200,
                          let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                          let list = obj["tickets"] as? [[String: Any]]
                    else { return ([], "Tickets de \(p.name.isEmpty ? "un utilisateur" : p.name) indisponibles") }
                    return (list.compactMap { SupportTicket($0, person: p) }, nil)
                }
            }
            for await (l, e) in g { all += l; if let e { errs.append(e) } }
        }
        tickets = all.sorted { $0.updated > $1.updated }
        errors = errs.sorted()
    }

    /// `take`, `close` ou `reopen`, puis relit la liste. Renvoie le message d'erreur, ou nil.
    func act(_ t: SupportTicket, _ action: String, by: String, people: [Person]) async -> String? {
        guard let url = URL(string: AutomateLibrary.base(t.person) + "/tickets/" + t.tid) else { return "Adresse invalide" }
        busy = t.id; defer { busy = nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "by": by])
        var error: String?
        if let (d, r) = try? await URLSession.shared.data(for: req) {
            if (r as? HTTPURLResponse)?.statusCode != 200 {
                let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                error = obj?["error"] as? String ?? "Action refusée"
            }
        } else {
            error = "Serveur injoignable"
        }
        await load(people)
        return error
    }
}

// MARK: - Mes automates

/// « Mes automates » : la bibliothèque du support, gardée sur son poste
/// (~/Library/Application Support/PapAI/automates.json). Chaque automate est un
/// pack `.papai` ; le support décide ensuite à qui l'appliquer. Appliquer =
/// l'importer dans l'espace de la personne (`POST /automations`), ce qui le valide.
@MainActor
@Observable
final class AutomateLibrary {
    struct Entry: Codable, Identifiable {
        var id: String
        var pack: Data          // le JSON .papai, tel quel
        var applied: [String]   // clés des personnes chez qui il est appliqué
        var created: Double
        var orgKeys: [String: [String]]? = nil   // organisations entières : jeton -> clés de leurs postes

        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: pack)) as? [String: Any] ?? [:] }
        var title: String { json["title"] as? String ?? "Sans titre" }
        var detail: String { json["description"] as? String ?? "" }
        var publisher: String { json["publisher"] as? String ?? "" }
        var platforms: [String] { json["platforms"] as? [String] ?? [] }
        var stepCount: Int { (json["steps"] as? [Any])?.count ?? 0 }
        var firstAction: String { ((json["actions"] as? [[String: Any]])?.first?["do"] as? String) ?? "" }
    }

    static let shared = AutomateLibrary()
    var entries: [Entry] = []

    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PapAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("automates.json")
    }

    init() {
        if let d = try? Data(contentsOf: file), let l = try? JSONDecoder().decode([Entry].self, from: d) {
            entries = l
        } else {
            seedExamples()
        }
    }

    /// Premier lancement : les exemples livrés avec l'app (dossier `automations/` du dépôt).
    private func seedExamples() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "papai", subdirectory: "automates") ?? []
        for u in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let d = try? Data(contentsOf: u) { _ = add(pack: d, save: false) }
        }
        save()
    }

    @discardableResult
    func add(pack: Data, save doSave: Bool = true) -> Entry? {
        guard let obj = (try? JSONSerialization.jsonObject(with: pack)) as? [String: Any],
              obj["papai"] as? Int == 1, obj["title"] is String else { return nil }
        let e = Entry(id: UUID().uuidString, pack: pack, applied: [], created: Date().timeIntervalSince1970)
        entries.insert(e, at: 0)
        if doSave { save() }
        return e
    }

    /// Les automates déjà présents chez les utilisateurs entrent dans la bibliothèque, marqués
    /// comme appliqués chez eux : rien n'existe côté utilisateur sans exister côté support.
    @MainActor
    func syncFromUsers(_ people: [Person]) async {
        var changed = false
        for p in people {
            guard let url = URL(string: Self.base(p) + "/lessons"),
                  let (d, r) = try? await URLSession.shared.data(from: url),
                  (r as? HTTPURLResponse)?.statusCode == 200,
                  let list = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { continue }
            for var l in list {
                guard let title = l["title"] as? String, !title.isEmpty else { continue }
                let k = title.lowercased()
                if !entries.contains(where: { $0.title.lowercased() == k }) {
                    l["papai"] = 1
                    guard let pack = try? JSONSerialization.data(withJSONObject: l),
                          add(pack: pack, save: false) != nil else { continue }
                    changed = true
                }
                if let i = entries.firstIndex(where: { $0.title.lowercased() == k }), !entries[i].applied.contains(p.key) {
                    entries[i].applied.append(p.key)
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    func remove(_ e: Entry) { entries.removeAll { $0.id == e.id }; save() }

    func markApplied(_ e: Entry, keys: [String], org: String? = nil) {
        guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return }
        entries[i].applied = Array(Set(entries[i].applied).union(keys))
        if let org { entries[i].orgKeys = (entries[i].orgKeys ?? [:]).merging([org: keys]) { _, n in n } }
        save()
    }

    /// Applique à toute une organisation (`POST /o/<jeton>/automations`) : le serveur le copie sur
    /// chacun de ses postes et sur ceux qui la rejoindront plus tard. Renvoie un message d'erreur, ou nil.
    func apply(_ e: Entry, toOrg o: OrgMembers) async -> String? {
        let err = await Self.post(e.pack, to: o.server + "/o/" + o.token + "/automations")
        if err == nil { markApplied(e, keys: o.keys, org: o.token) }
        return err
    }

    /// « Appliquer… » : les organisations cochées d'un coup, puis les utilisateurs cochés hors de
    /// ces organisations. Renvoie, par jeton d'organisation ou clé d'utilisateur, "" ou l'erreur.
    func apply(_ e: Entry, people: [Person], orgs: [OrgMembers]) async -> [String: String] {
        var results: [String: String] = [:]
        for o in orgs {
            let err = await apply(e, toOrg: o)
            results[o.token] = err ?? ""
            if err == nil { for k in o.keys { results[k] = "" } }
        }
        let covered = Set(orgs.filter { results[$0.token] == "" }.flatMap(\.keys))
        results.merge(await apply(e, to: people.filter { !covered.contains($0.key) })) { _, n in n }
        return results
    }

    /// Pour « Appliqué à : … » : l'organisation entière, puis les autres utilisateurs.
    static func appliedTo(_ e: Entry, people: [Person], org: SupportOrg?, orgName: String?) -> [String] {
        let whole = e.orgKeys ?? [:]
        let inOrgs = Set(whole.values.flatMap { $0 })
        let orgNames = whole.keys.sorted().map { t in
            t == org?.token ? orgName.map { "toute l’organisation \($0)" } ?? "toute l’organisation" : "toute une organisation"
        }
        return orgNames + people.filter { e.applied.contains($0.key) && !inOrgs.contains($0.key) }
            .map { $0.name.isEmpty ? "Utilisateur" : $0.name }
    }

    /// Applique l'automate à chacune des personnes et note où il a réussi.
    /// Renvoie, par clé, "" si appliqué ou le message d'erreur.
    func apply(_ e: Entry, to people: [Person]) async -> [String: String] {
        var results: [String: String] = [:]
        for p in people { results[p.key] = await Self.apply(e, to: p) ?? "" }
        markApplied(e, keys: results.filter { $0.value.isEmpty }.map(\.key))
        return results
    }

    func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: file, options: .atomic) }
    }

    /// Adresse HTTP de l'espace d'une personne (comme `HelperModel.baseHTTP`).
    nonisolated static func base(_ p: Person) -> String {
        var s = p.server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.contains("://") { s = "http://" + s }
        return s
    }

    /// Importe le pack chez une personne. Renvoie un message d'erreur, ou nil.
    static func apply(_ e: Entry, to p: Person) async -> String? {
        await post(e.pack, to: base(p) + "/automations")
    }

    private static func post(_ pack: Data, to address: String) async -> String? {
        guard let url = URL(string: address) else { return "Adresse invalide" }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = pack
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return "Serveur injoignable" }
        if (r as? HTTPURLResponse)?.statusCode == 200 { return nil }
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        return obj?["error"] as? String ?? "Refusé par le serveur"
    }
}

/// L'organisation du support et ses utilisateurs (`GET /o/<jeton>/spaces`),
/// pour « Appliquer… » à toute l'organisation d'un coup.
struct OrgMembers: Identifiable, Equatable {
    var id: String { token }
    var server: String
    var token: String
    var name: String
    var keys: [String]

    static func load(_ org: SupportOrg?, name: String?) async -> [OrgMembers] {
        var out: [OrgMembers] = []
        for o in [org].compactMap({ $0 }) {
            guard let url = URL(string: "\(o.server)/o/\(o.token)/spaces"),
                  let (d, r) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20)),
                  (r as? HTTPURLResponse)?.statusCode == 200,
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            let keys = (obj["spaces"] as? [[String: Any]] ?? []).compactMap { $0["key"] as? String }
            let name = (obj["org"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name ?? ""
            out.append(OrgMembers(server: o.server, token: o.token, name: name, keys: keys))
        }
        return out
    }

    /// « 3 utilisateurs, et ceux qui la rejoindront »
    var detail: String {
        "\(keys.count) utilisateur\(keys.count > 1 ? "s" : ""), et ceux qui la rejoindront"
    }
}
