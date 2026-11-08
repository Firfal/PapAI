import AppKit
import Observation

/// Les applications de l'accueil : celles que la personne utilise le plus, et
/// celles qui reviennent dans ses demandes d'aide.
///
/// Tout reste sur ce Mac (UserDefaults) : on compte les passages au premier plan
/// et les mots des demandes, rien n'est envoyé au serveur.
@MainActor @Observable
final class AppUsage {
    static let shared = AppUsage()

    struct App: Identifiable, Equatable {
        let bundle: String
        let name: String
        var id: String { bundle }
    }

    /// Les 6 applications à montrer, de la plus utile à la moins utile.
    private(set) var top: [App] = []

    /// Les 6 dernières applications passées au premier plan, la plus récente d'abord.
    private(set) var recent: [App] = []

    /// Sans historique, l'accueil montre ces classiques.
    private static let defaults = ["com.apple.mail", "com.apple.Photos", "com.apple.Safari",
                                   "com.apple.FaceTime", "com.apple.finder", "com.apple.iCal"]

    /// Une demande d'aide pèse plus qu'une ouverture : c'est là que la personne bloque.
    private static let requestWeight = 5.0

    /// Mots d'une demande → application. Le navigateur par défaut remplace Safari.
    private static let keywords: [(words: [String], bundle: String)] = [
        (["mail", "courriel", "e-mail", "email", "message électronique"], "com.apple.mail"),
        (["photo", "image", "album", "selfie"], "com.apple.Photos"),
        (["internet", "site", "google", "recherche", "navigateur", "page web"], "browser"),
        (["facetime", "appel vidéo", "visio"], "com.apple.FaceTime"),
        (["whatsapp"], "net.whatsapp.WhatsApp"),
        (["sms", "imessage", "messages"], "com.apple.MobileSMS"),
        (["agenda", "calendrier", "rendez-vous", "rdv"], "com.apple.iCal"),
        (["dossier", "fichier", "document", "télécharg", "ranger"], "com.apple.finder"),
        (["note"], "com.apple.Notes"),
        (["musique", "chanson", "radio"], "com.apple.Music"),
        (["calcul"], "com.apple.calculator"),
        (["zoom"], "us.zoom.xos"),
        (["word"], "com.microsoft.Word"),
    ]

    private var scores: [String: Double]
    private let key = "appUsageScores"

    /// Bundle → date du dernier passage au premier plan (secondes depuis 1970).
    private var lastSeen: [String: Double]
    private let recentKey = "appUsageLastSeen"

    private init() {
        scores = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        lastSeen = UserDefaults.standard.dictionary(forKey: recentKey) as? [String: Double] ?? [:]
        recompute()
        recomputeRecent()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier, app?.activationPolicy == .regular else { return }
            MainActor.assumeIsolated { self?.bump(id, by: 1); self?.noteActivation(id) }
        }
    }

    /// Une demande d'aide : les applications qu'elle évoque montent.
    func noteRequest(_ text: String) {
        let t = text.lowercased()
        for (words, bundle) in Self.keywords where words.contains(where: { t.contains($0) }) {
            bump(bundle == "browser" ? Self.browser : bundle, by: Self.requestWeight)
        }
    }

    private static var browser: String {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let id = Bundle(url: url)?.bundleIdentifier else { return "com.apple.Safari" }
        return id
    }

    private func bump(_ bundle: String, by w: Double) {
        guard bundle != Bundle.main.bundleIdentifier, !Self.hidden.contains(bundle) else { return }
        // Un léger oubli : ce qui servait il y a des mois descend peu à peu.
        for k in scores.keys { scores[k]! *= 0.995 }
        scores[bundle, default: 0] += w
        UserDefaults.standard.set(scores, forKey: key)
        recompute()
    }

    private func noteActivation(_ bundle: String) {
        guard bundle != Bundle.main.bundleIdentifier, !Self.hidden.contains(bundle) else { return }
        lastSeen[bundle] = Date().timeIntervalSince1970
        // On garde une trentaine d'applications : bien assez pour en montrer 6.
        if lastSeen.count > 30 {
            for (k, _) in lastSeen.sorted(by: { $0.value > $1.value }).dropFirst(30) { lastSeen[k] = nil }
        }
        UserDefaults.standard.set(lastSeen, forKey: recentKey)
        recomputeRecent()
    }

    /// Outils de développeur et utilitaires système : jamais sur l'accueil d'un senior.
    private static let hidden: Set<String> = [
        "com.apple.Terminal", "com.apple.dt.Xcode", "com.apple.ActivityMonitor", "com.apple.systempreferences",
        "com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.dock", "com.apple.Spotlight",
        "com.anthropic.claudefordesktop", "com.microsoft.VSCode", "com.googlecode.iterm2",
    ]

    private func recompute() {
        let ranked = scores.sorted { $0.value > $1.value }.map(\.key)
        let out = Self.apps(ranked + Self.defaults)
        if out != top { top = out }
    }

    private func recomputeRecent() {
        let ranked = lastSeen.sorted { $0.value > $1.value }.map(\.key)
            .filter { $0 != Bundle.main.bundleIdentifier && !Self.hidden.contains($0) }
        let out = Self.apps(ranked + Self.defaults)
        if out != recent { recent = out }
    }

    /// Les 6 premières applications installées de la liste, sans doublon.
    private static func apps(_ bundles: [String]) -> [App] {
        var out: [App] = []
        for b in bundles where out.count < 6 && !out.contains(where: { $0.bundle == b }) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            out.append(App(bundle: b, name: name))
        }
        return out
    }
}
