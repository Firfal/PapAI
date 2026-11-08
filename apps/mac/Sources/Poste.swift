import Foundation

/// Configuration du poste de l'employé. Rien ne se règle dans l'app : le service
/// informatique la dépose (profil de configuration MDM, ou à la main pour un essai) :
///
///     defaults write com.quentin.papai orgToken ins-…        # rattache le poste à l'organisation
///     defaults write com.quentin.papai server https://…      # serveur PapAI de l'organisation (facultatif)
///     defaults write com.quentin.papai displayName Christine # nom affiché (facultatif, démo)
///     defaults write com.quentin.papai role support          # poste d'un agent du support IT
///
/// `UserDefaults.standard` lit d'abord les valeurs imposées par un profil, puis celles
/// écrites par `defaults write` : les deux marchent, le profil l'emporte.
enum Poste {
    /// Vrai quand la valeur est imposée par un profil de configuration (non modifiable sur le poste).
    static func isForced(_ key: String) -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, kCFPreferencesCurrentApplication)
    }

    /// Valeur gérée, sans espaces autour ; `nil` si absente ou vide.
    static func managed(_ key: String, defaults: UserDefaults = .standard) -> String? {
        let t = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// Le nom affiché (« Bonjour Christine ») : `displayName` géré, sinon le prénom du
    /// compte macOS (premier mot du nom complet), sinon le nom court du compte.
    static func displayName(managed: String?, fullName: String, userName: String) -> String {
        if let m = managed?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return String(m.prefix(40)) }
        if let first = fullName.split(whereSeparator: \.isWhitespace).first { return String(first) }
        let u = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.prefix(1).uppercased() + u.dropFirst()
    }

    /// Jeton d'inscription de l'organisation (`ins-…`), sinon vide.
    static func orgToken(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("ins-") && t.count <= 100 ? t : ""
    }

    /// `ws://h/k/x/ws/bridge` → `http://h/k/x` : base des routes HTTP de l'espace.
    static func httpBase(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
        if s.hasSuffix("/ws/bridge") { s.removeLast("/ws/bridge".count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Le serveur seul, sans la clé de l'espace : `ws://h/k/x/ws/bridge` → `http://h`.
    static func origin(_ url: String) -> String {
        var s = httpBase(url)
        if let r = s.range(of: "/k/") { s = String(s[..<r.lowerBound]) }
        return s
    }

    /// Adresse du pont sans clé (serveur local de développement).
    static func plainBridge(_ server: String) -> String {
        if server.hasPrefix("ws://") || server.hasPrefix("wss://") { return server }
        let b = origin(server).replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        return b + "/ws/bridge"
    }

    /// Le pont de l'espace créé sur `base` : on garde le chemin `/k/<clé>/ws/bridge` renvoyé
    /// par le serveur, mais sur l'adresse configurée (un serveur local annonce son IP de réseau).
    static func bridge(from returned: String, base: String) -> String? {
        guard returned.hasPrefix("ws://") || returned.hasPrefix("wss://"),
              let r = returned.range(of: "/k/") else { return nil }
        let ws = base.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        return ws + returned[r.lowerBound...]
    }

    enum Route: Equatable {
        /// Se connecter à ce pont.
        case bridge(String)
        /// Créer l'espace du poste sur ce serveur (`POST <base>/spaces`, avec le jeton s'il y en a un).
        case createSpace(base: String)
    }

    /// Où se connecter, d'après le serveur géré (`server`, ou PAPAI_SERVER), le pont déjà
    /// obtenu (`bridgeURL`) et le jeton de l'organisation.
    static func route(server: String?, stored: String?, orgToken: String, official: String) -> Route {
        if let s = server, s.contains("/k/") { return .bridge(s) }  // pont complet (installs existantes)
        let base = server.map(origin) ?? official
        if let b = stored, b.contains("/k/"), origin(b) == base { return .bridge(b) }
        if let s = server, orgToken.isEmpty { return .bridge(plainBridge(s)) }  // serveur local sans espaces
        return .createSpace(base: base)
    }
}
