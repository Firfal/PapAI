// Configuration du poste d'entreprise : nom affiché, jeton, adresse du pont.
//   swiftc -parse-as-library -o /tmp/poste_test apps/mac/Sources/Poste.swift apps/mac/tests/poste_test.swift && /tmp/poste_test
import Foundation

@main
struct PosteTest {
    static func main() {
        var total = 0
        func verifier(_ value: Bool, _ name: String) {
            precondition(value, name)
            total += 1
            print("  OK      \(name)")
        }

        // Nom affiché : géré, sinon prénom du compte macOS, sinon nom court.
        verifier(Poste.displayName(managed: "Christine", fullName: "Robert Quentin", userName: "rq") == "Christine", "displayName géré prioritaire")
        verifier(Poste.displayName(managed: "  ", fullName: "Robert Quentin", userName: "rq") == "Robert", "displayName vide ignoré")
        verifier(Poste.displayName(managed: nil, fullName: "Jean-Pierre  Martin", userName: "jp") == "Jean-Pierre", "premier mot du nom complet")
        verifier(Poste.displayName(managed: nil, fullName: "", userName: "christine") == "Christine", "nom court en repli")

        // Jeton d'organisation.
        verifier(Poste.orgToken(" ins-abc \n") == "ins-abc", "jeton nettoyé")
        verifier(Poste.orgToken("sup-abc") == "", "jeton support refusé")
        verifier(Poste.orgToken(nil) == "", "pas de jeton")

        // Adresses.
        verifier(Poste.httpBase("wss://h.example/k/abc/ws/bridge") == "https://h.example/k/abc", "base HTTP de l'espace")
        verifier(Poste.origin("ws://localhost:8071/k/abc/ws/bridge") == "http://localhost:8071", "origine du serveur")
        verifier(Poste.bridge(from: "ws://192.168.1.4:8071/k/abc/ws/bridge", base: "http://localhost:8071") == "ws://localhost:8071/k/abc/ws/bridge",
                 "pont recalé sur l'adresse configurée")
        verifier(Poste.bridge(from: "https://x/k/abc", base: "http://localhost:8071") == nil, "pont non websocket refusé")

        // Routes.
        let off = "https://papai.example"
        verifier(Poste.route(server: nil, stored: nil, orgToken: "", official: off) == .createSpace(base: off), "rien : espace sur le serveur officiel")
        verifier(Poste.route(server: nil, stored: "wss://papai.example/k/a/ws/bridge", orgToken: "ins-x", official: off)
                 == .bridge("wss://papai.example/k/a/ws/bridge"), "espace déjà créé : on le garde")
        verifier(Poste.route(server: "http://localhost:8071", stored: "wss://papai.example/k/a/ws/bridge", orgToken: "ins-x", official: off)
                 == .createSpace(base: "http://localhost:8071"), "nouveau serveur géré : nouvel espace")
        verifier(Poste.route(server: "http://localhost:8071", stored: "ws://localhost:8071/k/b/ws/bridge", orgToken: "ins-x", official: off)
                 == .bridge("ws://localhost:8071/k/b/ws/bridge"), "serveur géré, espace déjà créé")
        verifier(Poste.route(server: "ws://localhost:8000/ws/bridge", stored: nil, orgToken: "", official: off)
                 == .bridge("ws://localhost:8000/ws/bridge"), "serveur local sans jeton : pont direct")
        verifier(Poste.route(server: "wss://papai.example/k/old/ws/bridge", stored: nil, orgToken: "ins-x", official: off)
                 == .bridge("wss://papai.example/k/old/ws/bridge"), "ancien pont complet conservé")
        print("Poste : \(total) contrôles OK")
    }
}
