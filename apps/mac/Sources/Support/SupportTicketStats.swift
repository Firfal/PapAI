import Foundation

/// Les catégories des tickets, mêmes identifiants que `backend/ticket_stats.py`.
enum TicketCategory {
    static let all: [(id: String, label: String)] = [
        ("wifi", "Wi-Fi et réseau"), ("imprimante", "Imprimante"), ("comptes", "Comptes et mots de passe"),
        ("logiciels", "Logiciels"), ("messagerie", "Messagerie"), ("fichiers", "Fichiers"),
        ("securite", "Sécurité"), ("autre", "Autre"),
    ]
    static func label(_ id: String) -> String { all.first { $0.id == id }?.label ?? "Autre" }
}

/// Statistiques des tickets (`GET …/k/<clé>/tickets/stats`), fusionnables entre
/// plusieurs utilisateurs pour l'onglet Tickets du Mac support.
struct TicketStats {
    struct Example: Identifiable, Hashable {
        var tid: String
        var number: Int
        var task: String
        var created: Double
        var personKey: String
        /// Même identifiant que `SupportTicket.id`, pour retrouver le ticket dans la liste.
        var id: String { personKey + "/" + tid }
        var label: String { String(format: "T-%04d", number) }
    }
    struct Category: Identifiable {
        var id: String
        var label: String
        var count: Int
        var resolved: Int
        var byAutomate: Int
        var monthPeople: Int
        var medianResolution: Double?
        var examples: [Example]
        var phrase: String
        var draft: [String: String]?
        var durations: [Double] = []   // `resolution_s` du serveur, pour la médiane fusionnée
    }
    struct Week: Identifiable {
        var start: String
        var total: Int
        var by: [String: Int]
        var id: String { start }
    }
    struct Suggestion: Identifiable {
        var category: String
        var count: Int
        var text: String
        var draft: [String: String]
        var id: String { category }
    }

    static let suggestMin = 5
    static let examplesMax = 3

    var since: String
    var weeks: [Week]
    var categories: [Category]
    var count: Int
    var resolved: Int
    var byAutomate: Int
    var medianResolution: Double?
    var automateShare: Double { resolved > 0 ? Double(byAutomate) / Double(resolved) : 0 }

    var suggestions: [Suggestion] {
        categories.compactMap { c in
            guard var d = c.draft, c.monthPeople >= Self.suggestMin else { return nil }
            let ex = c.examples.map(\.task).filter { !$0.isEmpty }
            d["description"] = "Préparé à partir des demandes reçues"
                + (ex.isEmpty ? "" : " : " + ex.map { "« \($0) »" }.joined(separator: " ; ")) + "."
            return Suggestion(category: c.id, count: c.monthPeople,
                              text: "\(c.monthPeople) demandes \(c.phrase) ce mois-ci : créer un automate ?", draft: d)
        }
    }

    init(since: String = "", weeks: [Week] = [], categories: [Category] = [], count: Int = 0, resolved: Int = 0,
         byAutomate: Int = 0, medianResolution: Double? = nil) {
        self.since = since; self.weeks = weeks; self.categories = categories
        self.count = count; self.resolved = resolved; self.byAutomate = byAutomate
        self.medianResolution = medianResolution
    }

    init?(_ d: [String: Any], personKey: String = "") {
        guard let tot = d["totals"] as? [String: Any], let ws = d["weeks"] as? [[String: Any]] else { return nil }
        func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
        func dbl(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        since = d["since"] as? String ?? ""
        weeks = ws.map { w in
            Week(start: w["start"] as? String ?? "", total: int(w["total"]),
                 by: ((w["by"] as? [String: Any]) ?? [:]).mapValues { int($0) })
        }
        categories = ((d["categories"] as? [[String: Any]]) ?? []).compactMap { c in
            guard let id = c["id"] as? String else { return nil }
            let ex = ((c["examples"] as? [[String: Any]]) ?? []).compactMap { e -> Example? in
                guard let tid = e["id"] as? String else { return nil }
                return Example(tid: tid, number: int(e["number"]), task: e["task"] as? String ?? "",
                               created: dbl(e["created"]) ?? 0, personKey: personKey)
            }
            let draft = (c["draft"] as? [String: Any])?.compactMapValues { $0 as? String }
            return Category(id: id, label: c["label"] as? String ?? TicketCategory.label(id), count: int(c["count"]),
                            resolved: int(c["resolved"]), byAutomate: int(c["by_automate"]),
                            monthPeople: int(c["month_people"]), medianResolution: dbl(c["median_resolution_s"]),
                            examples: ex, phrase: c["phrase"] as? String ?? "", draft: draft,
                            durations: ((c["resolution_s"] as? [Any]) ?? []).compactMap { dbl($0) })
        }
        count = int(tot["count"]); resolved = int(tot["resolved"]); byAutomate = int(tot["by_automate"])
        medianResolution = dbl(tot["median_resolution_s"])
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Additionne les statistiques de plusieurs utilisateurs. Une médiane ne
    /// s'additionne pas : avec plusieurs parts, elle est recalculée à partir des
    /// durées de résolution (`resolutions[catégorie]`, toutes catégories sous ""),
    /// par défaut celles envoyées par le serveur pour chaque catégorie.
    static func merge(_ parts: [TicketStats], resolutions given: [String: [Double]] = [:]) -> TicketStats {
        if parts.count == 1 { return parts[0] }
        var resolutions = given
        if resolutions.isEmpty {
            for c in parts.flatMap(\.categories) where !c.durations.isEmpty {
                resolutions[c.id, default: []] += c.durations
                resolutions["", default: []] += c.durations
            }
        }
        var out = TicketStats(since: parts.map(\.since).filter { !$0.isEmpty }.min() ?? "")
        var weeks: [String: Week] = [:]
        var cats: [String: Category] = [:]
        for p in parts {
            out.count += p.count; out.resolved += p.resolved; out.byAutomate += p.byAutomate
            for w in p.weeks {
                var m = weeks[w.start] ?? Week(start: w.start, total: 0, by: [:])
                m.total += w.total
                for (k, v) in w.by { m.by[k, default: 0] += v }
                weeks[w.start] = m
            }
            for c in p.categories {
                guard var m = cats[c.id] else { cats[c.id] = c; continue }
                m.count += c.count; m.resolved += c.resolved; m.byAutomate += c.byAutomate
                m.monthPeople += c.monthPeople
                m.durations += c.durations
                m.examples = Array((m.examples + c.examples).sorted { $0.created > $1.created }.prefix(examplesMax))
                if m.draft == nil { m.draft = c.draft }
                if m.phrase.isEmpty { m.phrase = c.phrase }
                cats[c.id] = m
            }
        }
        out.weeks = weeks.values.sorted { $0.start < $1.start }
        let order = TicketCategory.all.map(\.id)
        out.categories = cats.values.map { c in
            var c = c
            c.medianResolution = median(resolutions[c.id] ?? [])
            return c
        }.sorted { ($0.count, order.firstIndex(of: $1.id) ?? 99) > ($1.count, order.firstIndex(of: $0.id) ?? 99) }
        out.medianResolution = median(resolutions[""] ?? [])
        return out
    }
}
