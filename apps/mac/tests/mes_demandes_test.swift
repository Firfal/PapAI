import Foundation

@main
struct MesDemandesTest {
    static func main() async throws {
        var total = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            total += 1
            print("  OK      \(label)")
        }
        func decode(_ json: String) throws -> [UserRequest] {
            try JSONDecoder().decode(UserRequestsResponse.self, from: Data(json.utf8)).requests
        }
        let rows = try decode(UserRequestsResponse.demo)
        check(rows.count == 4, "quatre demandes de démonstration")
        check(rows[0].solution?.kind == "automate" && rows[0].solution?.lesson == "print", "solution automate")
        check(rows[0].relaunchID(availableIDs: ["print"]) == "print", "automate disponible : relance")
        check(rows[0].relaunchID(availableIDs: []) == nil, "automate retiré : aucune relance")
        check(rows[1].relaunchID(availableIDs: ["print"]) == nil, "plan : aucune relance")
        check(rows[1].solution?.steps == ["Ouvrir le Finder", "Ouvrir le dossier Documents"], "plan texte")
        check(rows[2].solution?.text == "Ouvrez les Réglages, puis choisissez Très grande.", "réponse validée")
        check(rows[2].solution?.sources?.first?.url == "https://example.org/aide", "source texte")
        check(rows[3].solution == nil && rows[3].relaunch == nil, "demande en attente sans solution")
        check(rows[0].dateText.contains("novembre 2026"), "date française")
        for (status, label) in [("nouveau", "En attente"), ("en_attente", "En attente"), ("rdv", "Rendez-vous prévu"),
                                ("en_cours", "En cours"), ("a_reprendre", "Interrompue"), ("resolu", "Réglée")] {
            let r = try decode("{\"requests\":[{\"id\":\"r\",\"status\":\"\(status)\"}]}")[0]
            check(r.statusText == label, "état \(status)")
        }
        let empty = try decode("{}")
        let null = try decode("{\"requests\":null}")
        check(empty.isEmpty && null.isEmpty, "liste absente ou nulle")
        let missing = try decode(#"{"requests":[{}, {"id":"r","task":null,"status":null,"created":null,"solution":null,"relaunch":null}]}"#)
        check(missing.count == 1 && missing[0].task.isEmpty && missing[0].statusText == "En attente", "champs manquants ou nuls, id requis")
        check(missing[0].dateText.isEmpty && missing[0].relaunchID(availableIDs: ["print"]) == nil, "date et relance absentes")
        let partial = try decode(#"{"requests":[{"id":"r","solution":{"kind":"answer","text":null,"sources":[{"title":null}]}},{"id":"p","solution":{"kind":"plan","steps":null}},{"id":"a","relaunch":""}]}"#)
        check(partial[0].solution?.sources?.first?.url == nil && partial[1].solution?.steps == nil, "solutions partielles tolérées")
        check(partial[2].relaunchID(availableIDs: [""]) == nil, "id de relance vide refusé")
        do {
            _ = try decode("pas du JSON")
            preconditionFailure("JSON invalide accepté")
        } catch { check(true, "JSON invalide rejeté") }
        print("\(total) vérifications passées")
    }
}
