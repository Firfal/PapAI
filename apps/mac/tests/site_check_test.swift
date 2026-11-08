import Foundation

@main
struct SiteCheckTest {
    struct Cas: Decodable {
        let url: String
        let sites: [String]
        let hosts: [String]
        let attendu: String
    }

    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "tests/site_check_cases.json"
        let cases = try JSONDecoder().decode([Cas].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        var failures = 0
        var total = 0
        func check(_ success: Bool, _ name: String) {
            total += 1
            if !success { failures += 1; print("ÉCHEC : \(name)") }
        }
        for (index, item) in cases.enumerated() {
            let result = SiteCheck.classify(item.url, sites: item.sites, hosts: item.hosts)
            check(result == item.attendu, "cas \(index + 1) : \(result), attendu \(item.attendu)")
        }
        print("Swift : \(cases.count) cas vérifiés")
        check(SiteCheck.hostOf("https://AMELI.FR.:443/a") == "ameli.fr", "hôte normalisé")
        check(SiteCheck.hostOf("https://аmeli.fr") == "xn--meli-43d.fr", "hôte Unicode")
        check(SiteCheck.hostOf("https://ameli.fr:80") == nil, "port refusé")
        let chain = ["https://ameli.fr", "https://connexion.ameli.fr", "https://evil.com"]
        check(chain.map { SiteCheck.classify($0, sites: ["ameli.fr"]) } == ["ok", "ok", "hors"],
              "chaîne de redirections")
        print("\(failures == 0 ? "OK" : "ÉCHEC") : \(total - failures)/\(total) contrôles, \(failures) échec(s)")
        if failures > 0 { exit(1) }
    }
}
