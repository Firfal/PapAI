import Foundation

/// L'organisation du support, déposée par le service informatique : rien ne se saisit dans l'app.
/// Avec le jeton support (`sup-…`), le support voit d'office tous les postes de l'organisation
/// (`GET /o/<jeton>/spaces`) et reçoit leurs demandes. Pas de liaison poste par poste.
///
/// Partagé avec le mode support de l'app Mac (apps/mac/project.yml). Sources, dans l'ordre :
/// - iPhone : configuration gérée MDM (`com.apple.configuration.managed` : `supportToken`, `server`) ;
/// - Mac : préférences gérées (profil) ou, pour un essai,
///       defaults write com.quentin.papai supportToken sup-…
///       defaults write com.quentin.papai server https://…   (facultatif)
///   (iPhone : les mêmes clés passées au lancement, `-supportToken sup-…`, pour les essais) ;
/// - iPhone, démo sans MDM : `PapAISupportToken` / `PapAIServer` dans Info.plist, injectés depuis
///   le fichier local non suivi `apps/ios/Config/Support.local.xcconfig` (voir Support.xcconfig).
struct SupportOrg: Equatable {
    var server: String
    var token: String
}

enum SupportConfig {
    static let officialServer = "https://papai-450417131702.europe-west1.run.app"

    /// Jeton support valide (`sup-` + caractères d'URL), sinon nil.
    static func token(_ raw: Any?) -> String? {
        let t = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("sup-"), (14...104).contains(t.count),
              t.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }) else { return nil }
        return t
    }

    /// `https://hôte[:port]`, sans chemin ni identifiants ; nil si ce n'est pas une adresse http(s).
    /// La valeur vient de l'administrateur (profil, préférence gérée), pas d'un lien reçu.
    static func server(_ raw: Any?) -> String? {
        let s = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: s), let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let h = c.host?.lowercased(), !h.isEmpty, c.user == nil, c.password == nil else { return nil }
        return "\(scheme)://\(h)" + (c.port.map { ":\($0)" } ?? "")
    }

    /// Première source qui porte un jeton valide ; le serveur vient de la même source
    /// (serveur PapAI officiel s'il est absent).
    static func resolve(_ sources: [[String: Any]]) -> SupportOrg? {
        for s in sources {
            if let t = token(s["supportToken"]) {
                return SupportOrg(server: server(s["server"]) ?? officialServer, token: t)
            }
        }
        return nil
    }

    static func current(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> SupportOrg? {
        var sources: [[String: Any]] = []
        #if os(iOS)
        if let m = defaults.dictionary(forKey: "com.apple.configuration.managed") { sources.append(m) }
        #endif
        var plain: [String: Any] = [:]
        if let t = defaults.string(forKey: "supportToken") { plain["supportToken"] = t }
        if let s = defaults.string(forKey: "server") { plain["server"] = s }
        sources.append(plain)
        #if os(iOS)
        let info = bundle.infoDictionary ?? [:]
        sources.append(["supportToken": info["PapAISupportToken"] ?? "", "server": info["PapAIServer"] ?? ""])
        #endif
        return resolve(sources)
    }
}
