// Fusion des statistiques de tickets de plusieurs utilisateurs (onglet Tickets du Mac support).
//   swiftc -o /tmp/ticket_stats_test apps/mac/Sources/Support/SupportTicketStats.swift apps/mac/tests/ticket_stats_test.swift && /tmp/ticket_stats_test
import Foundation

func stats(_ json: String, key: String) -> TicketStats {
    let d = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    return TicketStats(d, personKey: key)!
}

@main
struct TicketStatsTest {
    static func main() {
        let a = stats("""
        {"since": "2026-09-14", "totals": {"count": 4, "resolved": 2, "by_automate": 1, "median_resolution_s": 600},
         "weeks": [{"start": "2026-10-26", "total": 1, "by": {"wifi": 1}}, {"start": "2026-11-02", "total": 3, "by": {"wifi": 3}}],
         "categories": [{"id": "wifi", "label": "Wi-Fi et réseau", "count": 4, "resolved": 2, "by_automate": 1,
                         "month_people": 3, "median_resolution_s": 600, "phrase": "Wi-Fi",
                         "draft": {"title": "Rétablir le Wi-Fi", "goal": "Reconnecter", "description": "x"},
                         "examples": [{"id": "a1", "number": 4, "task": "Wi-Fi coupé", "created": 300}]}]}
        """, key: "k1")
        precondition(a.count == 4 && a.categories[0].examples[0].id == "k1/a1", "lecture")
        precondition(a.suggestions.isEmpty, "3 demandes : pas de suggestion")
        precondition(TicketStats.merge([a]).medianResolution == 600, "une seule part : médiane du serveur")

        let b = stats("""
        {"since": "2026-09-14", "totals": {"count": 3, "resolved": 1, "by_automate": 0, "median_resolution_s": 7200},
         "weeks": [{"start": "2026-11-02", "total": 3, "by": {"wifi": 2, "imprimante": 1}}],
         "categories": [{"id": "wifi", "count": 2, "resolved": 1, "by_automate": 0, "month_people": 2, "phrase": "Wi-Fi",
                         "examples": [{"id": "b1", "number": 2, "task": "Plus d'internet", "created": 500},
                                      {"id": "b2", "number": 1, "task": "Box éteinte", "created": 100}]},
                        {"id": "imprimante", "count": 1, "month_people": 1, "examples": []}]}
        """, key: "k2")
        let m = TicketStats.merge([a, b], resolutions: ["": [600, 600, 7200], "wifi": [600, 600, 7200]])
        precondition(m.count == 7 && m.resolved == 3 && m.byAutomate == 1, "totaux additionnés")
        precondition(abs(m.automateShare - 1.0 / 3) < 1e-9, "part réglée par un automate")
        precondition(m.weeks.map(\.start) == ["2026-10-26", "2026-11-02"] && m.weeks[1].total == 6
                     && m.weeks[1].by["wifi"] == 5, "semaines alignées par date")
        let wifi = m.categories[0]
        precondition(wifi.id == "wifi" && wifi.count == 6 && m.categories[1].id == "imprimante", "tri par nombre")
        precondition(wifi.examples.map(\.id) == ["k2/b1", "k1/a1", "k2/b2"], "exemples les plus récents, tous utilisateurs")
        precondition(wifi.medianResolution == 600 && m.medianResolution == 600, "médiane recalculée")
        let s = m.suggestions
        precondition(s.count == 1 && s[0].text == "5 demandes Wi-Fi ce mois-ci : créer un automate ?", "suggestion au total")
        precondition(s[0].draft["title"] == "Rétablir le Wi-Fi" && s[0].draft["description"]!.contains("« Plus d'internet »"),
                     "brouillon prérempli")
        precondition(TicketCategory.label("securite") == "Sécurité" && TicketCategory.label("??") == "Autre", "libellés")
        precondition(TicketStats.median([]) == nil && TicketStats.median([1, 3]) == 2, "médiane")
        print("ticket_stats_test : OK")
    }
}
