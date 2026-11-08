// Support connecté d'office à l'organisation : configuration gérée, liste des postes et,
// avec un serveur local, le vrai HelperModel qui voit les postes et reçoit leurs demandes.
//   swiftc -parse-as-library -o /tmp/support_org_test apps/ios/Sources/{HelperModel,People,SupportConfig,Platform}.swift \
//     apps/mac/tests/support_org_test.swift && /tmp/support_org_test
// Essai réel (facultatif) : PAPAI_TEST_SERVER=http://127.0.0.1:8081 PAPAI_TEST_SUPPORT=<jeton sup-…>
// PAPAI_TEST_POSTES=<clé1>,<clé2> /tmp/support_org_test. Le jeton n'est jamais affiché.
import Foundation

@main
struct SupportOrgTest {
    @MainActor static func main() async {
        var total = 0
        func verifier(_ value: Bool, _ name: String) {
            precondition(value, name)
            total += 1
            print("  OK      \(name)")
        }

        // Jeton et serveur gérés
        let tok = "sup-" + String(repeating: "a1_-", count: 6)
        verifier(SupportConfig.token(tok) == tok, "jeton support accepté")
        verifier(SupportConfig.token("  \(tok)\n") == tok, "espaces autour retirés")
        verifier(SupportConfig.token("ins-" + String(repeating: "a", count: 24)) == nil, "jeton d'inscription refusé")
        verifier(SupportConfig.token("sup-court") == nil, "jeton trop court refusé")
        verifier(SupportConfig.token("sup-" + String(repeating: "a", count: 20) + "/x") == nil, "caractère hors URL refusé")
        verifier(SupportConfig.token(42) == nil, "valeur non texte refusée")
        verifier(SupportConfig.server("https://Papai.example.com/o/x/") == "https://papai.example.com", "serveur ramené à son origine")
        verifier(SupportConfig.server("http://127.0.0.1:8081") == "http://127.0.0.1:8081", "serveur local avec port")
        verifier(SupportConfig.server("https://u:p@h.example") == nil, "identifiants dans l'adresse refusés")
        verifier(SupportConfig.server("ftp://h.example") == nil, "autre schéma refusé")
        verifier(SupportConfig.resolve([]) == nil, "sans source : aucune organisation")
        verifier(SupportConfig.resolve([["supportToken": ""], ["server": "https://x.example"]]) == nil, "serveur seul : aucune organisation")
        let r = SupportConfig.resolve([["supportToken": "faux"], ["supportToken": tok, "server": "https://acme.example"], ["supportToken": tok]])
        verifier(r == SupportOrg(server: "https://acme.example", token: tok), "première source valide, serveur de la même source")
        verifier(SupportConfig.resolve([["supportToken": tok, "server": "pas une adresse"]])?.server == SupportConfig.officialServer,
                 "serveur absent ou invalide : serveur officiel")
        let d = UserDefaults(suiteName: "support-org-test-\(UUID().uuidString)")!
        verifier(SupportConfig.current(defaults: d) == nil, "préférences vides : aucune organisation")
        d.set(tok, forKey: "supportToken"); d.set("http://127.0.0.1:8081", forKey: "server")
        verifier(SupportConfig.current(defaults: d) == SupportOrg(server: "http://127.0.0.1:8081", token: tok), "préférences supportToken et server lues")

        // Liste des postes
        let known = [Person(server: "s/k/a", key: "a", name: "Christine", label: "", helperId: "h1")]
        let spaces: [[String: Any]] = [
            ["key": "a", "name": "", "label": "Comptabilité"], ["key": "a", "name": "Doublon"],
            ["key": "b", "name": "Marc", "label": "Marc"], ["key": "../x"], ["name": "sans clé"],
        ]
        let list = People.fromSpaces(spaces, server: "https://acme.example", known: known)
        verifier(list.map(\.key) == ["a", "b"], "postes sans doublon ni clé invalide")
        verifier(list[0].server == "https://acme.example/k/a", "adresse de l'espace du poste")
        verifier(list[0].name == "Christine" && list[0].helperId == "h1", "prénom et identifiant connus gardés")
        verifier(People.title(list[0]) == "Christine" && People.detail(list[0]) == "Comptabilité", "prénom · service")
        verifier(People.detail(list[1]) == nil, "pas de détail qui répète le prénom")
        verifier(People.title(Person(server: "", key: "c", label: "MacBook")) == "MacBook", "sans prénom : nom du poste")

        // Sans organisation : rien à configurer, aucune connexion.
        let vide = HelperModel(org: nil)
        vide.quiet = true
        vide.start()
        verifier(!vide.orgConfigured && !vide.isConfigured && vide.people.isEmpty, "sans jeton : aucune organisation, aucun poste")

        // Essai réel contre un serveur local
        let env = ProcessInfo.processInfo.environment
        if let server = env["PAPAI_TEST_SERVER"], let token = env["PAPAI_TEST_SUPPORT"], let keys = env["PAPAI_TEST_POSTES"] {
            let postes = keys.split(separator: ",").map(String.init)
            for k in ["serverURL", "helperKey", "seniorName"] { UserDefaults.standard.removeObject(forKey: k) }
            let m = HelperModel(org: SupportOrg(server: server, token: token))
            m.quiet = true
            m.start()
            func attendre(_ secondes: Double, _ ok: () -> Bool) async -> Bool {
                let fin = Date().addingTimeInterval(secondes)
                while Date() < fin { if ok() { return true }; try? await Task.sleep(for: .milliseconds(200)) }
                return ok()
            }
            verifier(await attendre(10) { m.people.count == postes.count }, "le support voit les \(postes.count) postes de l'organisation")
            verifier(m.orgName == "Acme Démo" && m.orgTitle == "Support IT · Acme Démo", "nom de l'organisation")
            verifier(await attendre(10) { m.connected }, "connecté d'office au premier poste")
            verifier(m.helperKey == postes[0], "premier poste suivi en détail")
            verifier(await attendre(10) { m.seniorName == "Christine" }, "prénom de l'employé reçu")
            verifier(await attendre(10) { m.othersOnline[postes[1]] == true }, "deuxième poste surveillé, en ligne")
            print("  …       attente des demandes (le faux poste les envoie)")
            verifier(await attendre(40) { m.othersAsking[postes[1]] == true }, "demande du deuxième poste signalée")
            verifier(await attendre(40) { m.task == "Imprimer le bulletin de paie" && m.state != nil },
                     "demande du poste suivi reçue (\(m.state ?? "?"))")
            m.switchTo(m.people[1])
            verifier(m.helperKey == postes[1], "bascule vers le deuxième poste")
            verifier(await attendre(10) { m.connected && m.seniorName == "Marc" }, "connecté au deuxième poste")
            verifier(await attendre(10) { m.task == "Installer l'imprimante" }, "sa demande en cours s'affiche")
            for k in ["serverURL", "helperKey", "seniorName", "helperIds"] { UserDefaults.standard.removeObject(forKey: k) }
        } else {
            print("  (essai réel sauté : PAPAI_TEST_SERVER, PAPAI_TEST_SUPPORT, PAPAI_TEST_POSTES absents)")
        }
        print("\(total) contrôles, zéro échec")
    }
}
