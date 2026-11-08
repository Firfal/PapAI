import SwiftUI
import UserNotifications
import os

private let log = Logger(subsystem: "com.quentin.papai.aidant", category: "connexion")

struct PlanStep: Identifiable {
    let id: Int
    let title: String
    let detail: String?
    init(id: Int, raw: String) {
        self.id = id
        for sep in [" — ", " : ", ": "] {
            if let r = raw.range(of: sep) {
                title = String(raw[..<r.lowerBound])
                detail = String(raw[r.upperBound...])
                return
            }
        }
        title = raw; detail = nil
    }
}

struct Lesson: Decodable, Identifiable {
    struct Step: Decodable { var instruction: String? }
    var title: String
    var steps: [Step]?
    /// Identifiant du serveur s'il est fourni : deux automates peuvent porter le même titre.
    var serverId: String?
    var id: String { serverId ?? title }
    enum CodingKeys: String, CodingKey { case title, steps, serverId = "id" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        steps = try c.decodeIfPresent([Step].self, forKey: .steps)
        // Un `id` absent ou d'un autre type ne doit pas faire échouer la liste.
        serverId = (try? c.decodeIfPresent(String.self, forKey: .serverId)) ?? nil
    }
}

struct DraftStep: Identifiable {
    let id = UUID()
    var instruction: String
    var checkpoint: String?
    var preview: UIImage?
}

enum Screen { case idle, waiting, planning, approval, active, helper, done, stopped }

enum AppSheet: Identifiable {
    case settings, scanner, pair(PairLink)
    var id: String {
        switch self {
        case .settings: "settings"
        case .scanner: "scanner"
        case .pair(let l): "pair-\(l.id)"
        }
    }
}

@MainActor @Observable
final class HelperModel {
    // Réglages mémorisés
    var serverURL: String
    var helperKey: String
    var helperName: String? = UserDefaults.standard.string(forKey: "helperName")
    /// Identifiant de cet aidant chez le serveur : il apparaît dans « Mes proches » sur l'ordinateur.
    private var helperId: String = UserDefaults.standard.string(forKey: "helperId") ?? ""
    private var helperRelation: String = UserDefaults.standard.string(forKey: "helperRelation") ?? ""

    // Mes personnes aidées : une liaison par ordinateur, une seule suivie en détail à la fois.
    var people: [Person] = People.load()
    /// Pour les autres personnes : clé → ordinateur connecté / demande en attente.
    var othersOnline: [String: Bool] = [:]
    var othersAsking: [String: Bool] = [:]
    /// Ordinateur de la personne suivie connecté au serveur (`hello.bridge`) ; nil tant qu'inconnu.
    var seniorOnline: Bool?
    private var watches: [String: Task<Void, Never>] = [:]
    private var watchSockets: [String: URLSessionWebSocketTask] = [:]

    // Connexion
    var connected = false
    /// Raison lisible de la dernière coupure ou du dernier échec (nil si tout va bien).
    var linkError: String?
    /// Prochain essai automatique (nil si connecté ou si on n'essaie plus).
    var retryAt: Date?
    /// Le serveur a refusé la clé : inutile de réessayer en boucle.
    var keyRefused = false

    // Feuilles et appairage
    var sheet: AppSheet?
    var pairBusy = false
    var pairError: String?
    var pairRefused = false
    var pairNeedsNew = false
    var pairDone = false

    // Session
    var state: String?
    var sessionWhere: String?
    var task = ""
    var plan: [String] = []
    /// Étape du plan validé que Holo exécute (à partir de 1). Absente d'un ancien serveur.
    var planStep: Int?
    /// Ce que Holo est en train de faire, en une phrase (envoyée par le serveur).
    var doing: String?
    var question: (text: String, options: [String])?
    /// Vrai quand Holo pose la question à la personne aidée (`to: senior`).
    var questionToSenior = false
    /// Ce que la personne aidée est en train de dicter, en direct.
    var liveDictation: String?
    /// La personne aidée a mis l'aide en pause depuis son écran.
    var seniorPaused = false
    private var dictationClear: Task<Void, Never>?
    var sessionId = ""
    var requestStart = Date()
    var iRefusedPlan = false
    var doneFresh = false
    var doneAnswer: String?
    var pausing = false
    var planBusy = false

    // Capture
    var frame: UIImage?
    var frameId: String?
    var frameAt: Date?

    // Visée
    var aiming = false
    var target: CGPoint?
    var sending = false

    // Fiche
    var lessonBusy = false
    var draftTitle = ""
    var draftSteps: [DraftStep] = []
    /// Ce que la tuile ouvrira chez la personne aidée (« Images › Noël 2025 »), à voir avant de valider.
    var draftTarget: String?
    var hasDraft = false
    var savedTitle: String?
    var lessons: [Lesson] = []

    var toast: String?
    var sensitiveRefusal: String?
    var lastAlert: (title: String, detail: String)?
    var guardAlertId: String?
    var guardTask = ""
    var guardAcknowledged = false
    var stoppedBy: String?

    private var socket: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    private var lastPong = Date()
    private let wsSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 20   // une adresse morte échoue en 20 s, pas en 60
        return URLSession(configuration: c)
    }()
    private var toastTask: Task<Void, Never>?
    static let frameTTL: Double = 30

    init() {
        #if DEBUG
        // `-serverURL …` et `-helperKey …` au lancement (dépannage, démo) : on les garde.
        let args = ProcessInfo.processInfo.arguments
        for k in ["serverURL", "helperKey"] {
            if let i = args.firstIndex(of: "-" + k), i + 1 < args.count {
                let v = args[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { UserDefaults.standard.set(v, forKey: k) }
            }
        }
        #endif
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        helperKey = UserDefaults.standard.string(forKey: "helperKey") ?? ""
        rememberCurrent()
        Task { await refreshOrgs() }
    }

    // MARK: Organisations (service IT) : chaque poste inscrit devient une personne aidée, sans code.

    var orgs: [Org] = Orgs.load()
    var orgError: String?
    var orgBusy = false

    func addOrg(_ input: String) async -> Bool {
        guard let o = Orgs.parse(input, officialHost: PairServer.officialHost) else {
            orgError = "Lien d’organisation non reconnu."; return false
        }
        guard PairServer.allowed(o.server) else { orgError = PairServer.refusal; return false }
        orgError = nil; orgBusy = true
        defer { orgBusy = false }
        return await fetchOrg(o, manual: true)
    }

    func refreshOrgs() async {
        for o in orgs { await fetchOrg(o, manual: false) }
    }

    @discardableResult
    private func fetchOrg(_ o: Org, manual: Bool) async -> Bool {
        guard let url = URL(string: "\(o.server)/o/\(o.token)/spaces") else { return false }
        do {
            let (d, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
            let r = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                if manual { orgError = r["error"] as? String ?? "Lien d’organisation invalide." }
                return false
            }
            let name = r["org"] as? String ?? ""
            var kept = o
            if !name.isEmpty { kept.name = name }
            orgs = orgs.filter { $0.token != o.token } + [kept]
            Orgs.save(orgs)
            let spaces = r["spaces"] as? [[String: Any]] ?? []
            for s in spaces {
                guard let k = s["key"] as? String, !k.isEmpty else { continue }
                people = People.upsert(people, Person(server: "\(o.server)/k/\(k)", key: k, name: s["name"] as? String ?? ""))
            }
            People.save(people)
            if !isConfigured, let first = people.first { switchTo(first) }
            watchOthers()
            if manual {
                let n = spaces.count
                showToast("\(n) poste\(n > 1 ? "s" : "") ajouté\(n > 1 ? "s" : "")" + (name.isEmpty ? "." : " (\(name))."))
            }
            return true
        } catch {
            if manual { orgError = "Le serveur ne répond pas." }
            return false
        }
    }

    var isConfigured: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !helperKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var screen: Screen {
        switch state {
        case "waiting_consent": return .waiting
        case "planning": return .planning
        case "awaiting_approval": return .approval
        case "active": return .active
        case "awaiting_helper": return .helper
        case "done": return doneFresh ? .done : .idle
        case "stopped": return .stopped
        default: return .idle
        }
    }

    // MARK: Réglages et connexion

    private var baseHTTP: String {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.contains("://") { s = "http://" + s }
        return s
    }
    private var wsURL: URL? {
        let b = baseHTTP.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        let key = helperKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "\(b)/ws/aidant/\(key)")
    }

    /// Hôte affiché dans les messages (sans la clé famille du chemin).
    var displayHost: String {
        guard let u = URL(string: baseHTTP), let h = u.host else { return serverURL }
        return u.port.map { "\(h):\($0)" } ?? h
    }
    var lastGood: (server: String, key: String)? {
        guard let s = UserDefaults.standard.string(forKey: "lastGoodServerURL"),
              let k = UserDefaults.standard.string(forKey: "lastGoodHelperKey") else { return nil }
        return (s, k)
    }

    /// Enregistre de nouveaux réglages. Jamais de valeur vide : une configuration
    /// qui marche n'est pas effacée par un champ laissé blanc.
    @discardableResult
    func applySettings(server: String, key: String) -> Bool {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !k.isEmpty else { return false }
        guard PairServer.allowed(s) else { pairError = PairServer.refusal; return false }
        pairError = nil
        serverURL = s; helperKey = k
        UserDefaults.standard.set(s, forKey: "serverURL")
        UserDefaults.standard.set(k, forKey: "helperKey")
        rememberCurrent()
        reconnect()
        return true
    }

    // MARK: Mes personnes aidées

    private func rememberCurrent() {
        guard isConfigured else { return }
        people = People.upsert(people, Person(server: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                              key: helperKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                              name: seniorName, helperId: helperId, relation: helperRelation))
        People.save(people)
    }

    func isCurrent(_ p: Person) -> Bool { p.key == helperKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Suivre une autre personne : la liaison active change, les autres restent surveillées.
    func switchTo(_ p: Person) {
        sensitiveRefusal = nil
        guard !isCurrent(p) else { return }
        rememberCurrent()
        serverURL = p.server; helperKey = p.key; seniorName = p.name
        helperId = p.helperId; helperRelation = p.relation
        let d = UserDefaults.standard
        d.set(p.server, forKey: "serverURL"); d.set(p.key, forKey: "helperKey"); d.set(p.name, forKey: "seniorName")
        d.set(p.helperId, forKey: "helperId"); d.set(p.relation, forKey: "helperRelation")
        clearSession()
        reconnect()
    }

    func forget(_ p: Person) {
        let wasCurrent = isCurrent(p)
        people.removeAll { $0.key == p.key }
        People.save(people)
        guard wasCurrent else { watchOthers(); return }
        helperKey = ""
        if let next = people.first { switchTo(next); return }
        runTask?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        runTask = nil; socket = nil; connected = false
        serverURL = ""; seniorName = ""
        for k in ["serverURL", "helperKey", "seniorName"] { UserDefaults.standard.removeObject(forKey: k) }
        clearSession()
        watchOthers()
        syncLive()
    }

    private func clearSession() {
        state = nil; sessionWhere = nil; sessionId = ""; task = ""; plan = []; planStep = nil
        doing = nil; question = nil; questionToSenior = false; liveDictation = nil; seniorPaused = false
        frame = nil; frameId = nil; frameAt = nil; aiming = false; target = nil
        lessons = []; lastAlert = nil; guardAlertId = nil; doneFresh = false; hasDraft = false; savedTitle = nil
        seniorOnline = nil
    }

    private static func wsURL(server: String, key: String) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.contains("://") { s = "http://" + s }
        let b = s.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(b)/ws/aidant/\(key.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    /// Un canal discret par autre personne, pour savoir qui demande une assistance.
    func watchOthers() {
        let others = Dictionary(people.filter { !isCurrent($0) }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for k in Array(watches.keys) where others[k] == nil {
            watches.removeValue(forKey: k)?.cancel()
            watchSockets.removeValue(forKey: k)?.cancel(with: .goingAway, reason: nil)
            othersOnline[k] = nil; othersAsking[k] = nil
        }
        for (k, p) in others where watches[k] == nil {
            watches[k] = Task { await watch(p) }
        }
    }

    private func watch(_ p: Person) async {
        while !Task.isCancelled {
            guard let url = Self.wsURL(server: p.server, key: p.key) else { return }
            let t = wsSession.webSocketTask(with: url)
            watchSockets[p.key] = t
            t.resume()
            var refused = false
            while !Task.isCancelled {
                guard let msg = try? await t.receive() else { break }
                let data: Data
                switch msg {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: continue
                }
                guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if m["type"] as? String == "refused" { refused = true; break }
                observe(p.key, m)
            }
            t.cancel(with: .goingAway, reason: nil)
            if watchSockets[p.key] === t { watchSockets[p.key] = nil }
            othersOnline[p.key] = false
            if refused { return }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func observe(_ key: String, _ m: [String: Any]) {
        let known = people.first { $0.key == key }?.name ?? ""
        let who = known.isEmpty ? "Une personne aidée" : known
        switch m["type"] as? String {
        case "hello":
            othersOnline[key] = m["bridge"] as? Bool ?? false; othersAsking[key] = false
            rename(key, m["senior"] as? String)
        case "senior":
            rename(key, m["name"] as? String)
        case "status":
            let was = othersAsking[key] ?? false
            let now = People.isAsking(m["state"] as? String)
            othersAsking[key] = now
            if now && !was {
                showToast("\(who) demande une assistance.")
                let t = (m["task"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                notifyLocal(title: "\(who) demande une assistance", body: t.isEmpty ? "Ouvrez PapAI pour voir la demande." : "« \(t) »")
            }
        case "alert_cleared":
            othersAsking[key] = false
        case "helper_added":
            if let name = m["name"] as? String { showToast("\(name) est maintenant support.") }
        case "alert":
            othersAsking[key] = true
            notifyLocal(title: "\(who) : \(m["title"] as? String ?? "alerte")", body: m["detail"] as? String ?? "")
        default: break
        }
    }

    private func rename(_ key: String, _ name: String?) {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = people.firstIndex(where: { $0.key == key }), people[i].name != n else { return }
        people[i].name = n
        People.save(people)
    }

    func start() {
        watchOthers()
        guard runTask == nil, isConfigured else { return }
        syncLive()
        runTask = Task { await run() }
        Task { await loadLessons() }
    }

    func reconnect() {
        runTask?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        runTask = nil; connected = false; keyRefused = false; linkError = nil; retryAt = nil
        start()
    }

    /// Retour au premier plan : on n'attend pas la fin du délai d'attente.
    func wakeUp() {
        guard isConfigured else { return }
        LiveAlert.shared.resume()
        if !connected {
            // Connexion déjà en cours d'ouverture (lancement de l'app) : on la laisse finir.
            if runTask != nil, socket != nil, retryAt == nil, !keyRefused { return }
            log.info("premier plan : reconnexion immédiate"); reconnect(); return
        }
        Task { await loadLessons() }
        guard let t = socket else { return }
        let sent = Date()
        t.sendPing { [weak self] err in
            Task { @MainActor in if err == nil { self?.lastPong = Date() } }
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if socket === t, lastPong < sent {
                log.error("premier plan : pas de pong en 5 s, reconnexion")
                reconnect()
            }
        }
    }

    private func run() async {
        var delay = 1.0
        while !Task.isCancelled {
            guard let url = wsURL else { linkError = "Adresse du serveur invalide."; return }
            let host = displayHost
            let t = wsSession.webSocketTask(with: url)
            t.maximumMessageSize = 32 * 1024 * 1024
            socket = t
            lastPong = Date()
            t.resume()
            log.info("ouverture vers \(host, privacy: .public)")
            let opened = Date()
            var hello = false
            let pinger = Task { await keepAlive(t) }
            do {
                while true {
                    let m = try await t.receive()
                    if !hello {
                        if case .string(let s) = m, s.contains("\"refused\"") {
                            // Le serveur refuse la clé avant même `hello`.
                            keyRefused = true
                            let reason = (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])?["reason"] as? String
                            linkError = "Clé refusée par \(host)" + (reason.map { " (\($0))" } ?? "") + "."
                            log.error("clé refusée : \(reason ?? "", privacy: .public)")
                            t.cancel(with: .normalClosure, reason: nil)
                            break
                        }
                        hello = true; connected = true; linkError = nil; retryAt = nil; delay = 1
                        rememberGood()
                        log.info("connecté à \(host, privacy: .public)")
                    }
                    handle(m)
                }
            } catch {
                let lasted = Int(Date().timeIntervalSince(opened))
                let reason = t.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let http = (t.response as? HTTPURLResponse)?.statusCode ?? 0
                log.error("""
                    fermée après \(lasted, privacy: .public) s : code \(t.closeCode.rawValue, privacy: .public) \
                    raison « \(reason, privacy: .public) » http \(http, privacy: .public) \
                    erreur \(String(describing: error), privacy: .public)
                    """)
                if !Task.isCancelled { linkError = describe(error, http: http, hello: hello, host: host) }
            }
            pinger.cancel()
            // Une tâche annulée par `reconnect()` finit après le départ de la suivante :
            // elle ne doit pas effacer l'état de la nouvelle connexion.
            if Task.isCancelled { return }
            connected = false; socket = nil; seniorOnline = nil
            if keyRefused { retryAt = nil; return }   // on attend « Vérifier les réglages » ou le premier plan
            retryAt = Date().addingTimeInterval(delay)
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 8)   // backoff jusqu'à 8 s
        }
    }

    /// Ping toutes les 15 s : garde la connexion vivante à travers les proxys
    /// et détecte une liaison morte (pas de pong en 40 s).
    private func keepAlive(_ t: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            if Task.isCancelled { return }
            if Date().timeIntervalSince(lastPong) > 40 {
                log.error("pas de pong depuis 40 s : on coupe pour réessayer")
                t.cancel(with: .goingAway, reason: Data("pong absent".utf8))
                return
            }
            t.sendPing { [weak self] err in
                if let err { log.error("ping en échec : \(String(describing: err), privacy: .public)") }
                else { Task { @MainActor in self?.lastPong = Date() } }
            }
        }
    }

    private func describe(_ error: Error, http: Int, hello: Bool, host: String) -> String {
        if http == 401 || http == 403 { keyRefused = true; return "Clé refusée par \(host)." }
        if http == 404 { return "Adresse introuvable sur \(host) : vérifiez l’adresse du serveur." }
        if http >= 400 { return "Le serveur \(host) répond une erreur \(http)." }
        if hello { return "Connexion coupée" }
        if let u = error as? URLError, u.code == .notConnectedToInternet { return "Ce téléphone n’a pas de connexion internet." }
        return "Le serveur ne répond pas à \(host)"
    }

    private func rememberGood() {
        UserDefaults.standard.set(serverURL, forKey: "lastGoodServerURL")
        UserDefaults.standard.set(helperKey, forKey: "lastGoodHelperKey")
    }

    // MARK: Appairage

    // MARK: Personne aidée

    /// Prénom saisi sur l'ordinateur de la personne aidée (`hello.senior`, `senior`,
    /// réponse d'appairage, paramètre `n` du lien). Jamais un nom figé.
    var seniorName: String = UserDefaults.standard.string(forKey: "seniorName") ?? ""
    /// Dans une phrase : « Rien à signaler pour Sophie », sinon « de la personne aidée ».
    var senior: String { seniorName.isEmpty ? "la personne aidée" : seniorName }
    /// En début de phrase : « Sophie a besoin de vous », sinon « La personne aidée… ».
    var seniorTitle: String { seniorName.isEmpty ? "La personne aidée" : seniorName }
    var webBrowserTitle: String {
        let firstName = seniorName.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return firstName.map { "Chrome PapAI de \($0)" } ?? "Chrome PapAI"
    }
    var webLive: Bool {
        sessionWhere == "web" && (state == "active" || state == "awaiting_helper")
    }

    func setSenior(_ name: String?) {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != seniorName else { return }
        seniorName = n
        UserDefaults.standard.set(n, forKey: "seniorName")
        rememberCurrent()
        syncLive()
    }

    func open(url: URL) {
        if url.host == "open" { return }   // touché depuis la carte de l'écran verrouillé
        if url.host == "org" { Task { _ = await addOrg(url.absoluteString) }; return }
        guard let link = PairLink.parse(url.absoluteString) else { showToast(PairServer.refusal); return }
        openPair(link)
    }

    func openPair(_ link: PairLink) {
        pairDone = false; pairError = nil; pairBusy = false; pairRefused = false; pairNeedsNew = false
        sheet = .pair(link)
    }

    /// Saisie du code à la main : serveur déjà réglé, sinon le serveur PapAI officiel.
    func manualPairLink() -> PairLink? {
        let s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return PairLink(base: "https://" + PairServer.officialHost, code: nil) }
        // `/p/<code>` sans le préfixe `/k/<clé>` : le code peut viser une autre personne aidée.
        let origin = PairLink(base: baseHTTP, code: nil).origin
        return PairServer.allowed(origin) ? PairLink(base: origin, code: nil) : nil
    }

    /// POST du prénom et du lien, puis réglage de l'app avec la réponse du serveur.
    /// Une nouvelle personne s'ajoute à la liste : la liaison précédente est gardée.
    func submitPair(_ link: PairLink, code: String?, name: String, relation: String) async {
        guard !pairBusy, !pairNeedsNew else { return }
        pairRefused = false
        guard PairServer.allowed(link.base) else { pairError = PairServer.refusal; return }
        let c = (link.code ?? code ?? "").filter(\.isNumber)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.token != nil || c.count == 6 else { pairError = "Le code fait 6 chiffres."; return }
        guard !n.isEmpty else { pairError = "Indiquez votre prénom."; return }
        guard let url = URL(string: link.endpoint(code: c)) else { pairError = "Adresse invalide."; return }
        pairBusy = true; pairError = nil
        defer { pairBusy = false }
        var req = URLRequest(url: url, timeoutInterval: 150)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": n, "relation": relation])
        do {
            let (d, response) = try await URLSession.shared.data(for: req)
            let r = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
            guard (response as? HTTPURLResponse)?.statusCode == 200, r["ok"] as? Bool == true else {
                pairRefused = r["refused"] as? Bool == true
                pairNeedsNew = PairServer.needsNew(status: (response as? HTTPURLResponse)?.statusCode ?? 0, refused: pairRefused)
                pairError = r["error"] as? String ?? "Le serveur a refusé la liaison."
                return
            }
            guard let key = r["key"] as? String, !key.isEmpty else {
                pairError = "Le serveur n’a pas renvoyé de clé : réglez la connexion à la main."
                return
            }
            var server = (r["server"] as? String) ?? link.origin
            if !PairServer.allowed(server) || !PairServer.sameOrigin(server, link.origin) { server = link.origin }
            while server.hasSuffix("/") { server.removeLast() }
            // Pas setSenior : il renommerait la personne suivie jusqu'ici.
            seniorName = (r["senior"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(seniorName, forKey: "seniorName")
            helperName = r["name"] as? String ?? n
            UserDefaults.standard.set(helperName, forKey: "helperName")
            helperId = r["id"] as? String ?? ""; UserDefaults.standard.set(helperId, forKey: "helperId")
            helperRelation = relation; UserDefaults.standard.set(relation, forKey: "helperRelation")
            log.info("appairé avec \(server, privacy: .public)")
            pairDone = true
            applySettings(server: server + "/k/" + key, key: key)
        } catch {
            pairError = "Le serveur ne répond pas à \(link.host)."
            log.error("appairage : \(String(describing: error), privacy: .public)")
        }
    }

    func send(_ o: [String: Any]) {
        guard let socket, connected, let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else {
            planBusy = false; sending = false
            showToast("Pas de connexion au serveur."); return
        }
        if o["type"] as? String != "helper_hello" { sensitiveRefusal = nil }
        socket.send(.string(s)) { _ in }
    }

    func loadLessons() async {
        guard let url = URL(string: baseHTTP + "/lessons"),
              let (d, _) = try? await URLSession.shared.data(from: url),
              let l = try? JSONDecoder().decode([Lesson].self, from: d) else { return }
        lessons = l
    }

    func showToast(_ s: String) {
        toast = s
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { toast = nil } }
    }

    // MARK: Messages

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        let data: Data
        switch msg {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = m["type"] as? String else { return }

        switch type {
        case "hello":
            setSenior(m["senior"] as? String)
            seniorOnline = m["bridge"] as? Bool ?? false
            // Une alerte toujours en attente est renvoyée juste après `hello` :
            // sinon elle a été réglée ailleurs pendant la coupure.
            clearGuardAlert()
            // On se présente : l'ordinateur doit voir ce support dans sa liste.
            send(["type": "helper_hello", "id": helperId, "name": helperName ?? "Support",
                  "relation": helperRelation])

        case "helper_id":
            if let id = m["id"] as? String, !id.isEmpty {
                helperId = id; UserDefaults.standard.set(id, forKey: "helperId")
                rememberCurrent()
            }

        case "dictation":
            let t = (m["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            liveDictation = t.isEmpty ? nil : t
            dictationClear?.cancel()
            // Sans nouvelle demande dans la minute, on efface le texte affiché.
            dictationClear = Task { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { liveDictation = nil } }

        case "senior":
            setSenior(m["name"] as? String)

        case "status":
            let newState = m["state"] as? String
            let sid = "\(m["session"] ?? "")"
            var wasWebLive = webLive
            if sid != sessionId {
                wasWebLive = false
                liveDictation = nil
                sessionId = sid; requestStart = Date(); iRefusedPlan = false
                sessionWhere = nil
                doneAnswer = nil; hasDraft = false; savedTitle = nil; lessonBusy = false
                pausing = false; doneFresh = false
            }
            let newWhere = m["where"] as? String
            let newWebLive = newWhere == "web" && (newState == "active" || newState == "awaiting_helper")
            if newWebLive && !wasWebLive {
                aiming = false; target = nil; sending = false
                frame = nil; frameId = nil; frameAt = nil
            }
            if wasWebLive && !newWebLive {
                frame = nil; frameId = nil; frameAt = nil
                target = nil; sending = false
            }
            sessionWhere = newWhere
            // La question d'abord : la notification ci-dessous en reprend le texte.
            if let q = m["question"] as? [String: Any], let t = q["question"] as? String {
                question = (t, q["options"] as? [String] ?? [])
                questionToSenior = (q["to"] as? String) == "senior"
            } else if newState != "awaiting_helper" { question = nil }
            if newState != state {
                if newState == "awaiting_approval" || newState == "awaiting_helper" { notify(newState!) }
                if newState == "done" { doneFresh = true; Task { await loadLessons() } }
                if newState == "active" { pausing = false; planBusy = false }
                if newState != "awaiting_helper" { aiming = false; target = nil; sending = false }
                if newState == "awaiting_approval" { planBusy = false }
            }
            state = newState
            stoppedBy = m["stopped_by"] as? String
            task = m["task"] as? String ?? task
            plan = m["plan"] as? [String] ?? []
            planStep = m["plan_step"] as? Int
            doing = m["doing"] as? String
            seniorPaused = m["paused"] as? Bool ?? false
            syncLive()

        case "frame":
            if let b64 = m["png_b64"] as? String, let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
                frame = img; frameId = m["frame_id"] as? String; frameAt = Date()
                target = nil
            }

        case "question":
            if let t = m["question"] as? String { question = (t, m["options"] as? [String] ?? []) }

        case "answer":
            doneAnswer = m["content"] as? String

        case "guard_advice":
            let t = m["title"] as? String ?? "Avis de sécurité indisponible"
            notifyLocal(title: t, body: m["detail"] as? String ?? "Vérifiez le plan avant de le valider.")
            showToast(t)

        case "alert":
            let t = m["title"] as? String ?? "Alerte", d = m["detail"] as? String ?? ""
            let aid = m["alert_id"] as? String
            let fresh = guardAlertId != aid || lastAlert?.detail != d
            if let aid {
                lastAlert = (t, d)
                guardAlertId = aid
                guardTask = m["task"] as? String ?? ""
                guardAcknowledged = m["acknowledged"] as? Bool ?? (m["acknowledged_by"] as? String != nil)
            } else if guardAlertId == nil {
                lastAlert = (t, d)   // échec d'un automate : simple information, l'alerte ouverte reste
            }
            if fresh { notifyLocal(title: t, body: d) }
            if aid == nil { showToast(t) }
            syncLive()

        case "alert_acknowledged":
            if let id = m["alert_id"] as? String, id == guardAlertId {
                guardAcknowledged = true
            }

        case "alert_cleared":
            if let id = m["alert_id"] as? String, id == guardAlertId {
                guardAlertId = nil; lastAlert = nil; guardTask = ""
                guardAcknowledged = false
                syncLive()
                showToast("Alerte rejetée. L'assistance reste arrêtée.")
            }

        case "refused":
            if m["blocked"] as? String == "sensitive" {
                sensitiveRefusal = m["reason"] as? String ?? "Cette fenêtre est protégée (réglages ou mots de passe)."
                toast = nil
            } else {
                let reason = m["reason"] as? String ?? "Refusé"
                if reason.contains("n'est plus en attente") { clearGuardAlert() }
                showToast(reason)
            }
            sending = false; planBusy = false; lessonBusy = false

        case "ack":
            if m["what"] as? String == "click" {
                sending = false; aiming = false; target = nil
                showToast("Clic transmis à l’ordinateur de \(senior).")
            } else if m["what"] as? String == "pause" { pausing = true }

        case "lesson_pending": lessonBusy = true

        case "lesson_draft":
            lessonBusy = false
            if let l = m["lesson"] as? [String: Any] {
                draftTitle = l["title"] as? String ?? ""
                draftTarget = Self.shortcutLabel(l["shortcut"] as? [String: Any])
                let previews = m["preview"] as? [String: String] ?? [:]
                draftSteps = (l["steps"] as? [[String: Any]] ?? []).map { s in
                    var img: UIImage?
                    if let f = s["frame"] as? String, let b = previews[f], let d = Data(base64Encoded: b) { img = UIImage(data: d) }
                    return DraftStep(instruction: s["instruction"] as? String ?? "",
                                     checkpoint: s["checkpoint"] as? String, preview: img)
                }
                hasDraft = true
            }

        case "lesson_saved":
            hasDraft = false; lessonBusy = false
            savedTitle = (m["lesson"] as? [String: Any])?["title"] as? String ?? draftTitle
            Task { await loadLessons() }

        case "helper_added":
            if let name = m["name"] as? String { showToast("\(name) est maintenant support.") }

        default: break
        }
    }

    /// Efface l'alerte du gardien locale (et donc l'écran plein qu'elle ouvre).
    private func clearGuardAlert() {
        guard guardAlertId != nil else { return }
        guardAlertId = nil; lastAlert = nil; guardTask = ""; guardAcknowledged = false
        syncLive()
    }

    // MARK: Notifications

    /// Met à jour la grande carte de l'écran verrouillé (voir `LiveAlert`).
    func syncLive() {
        if guardAlertId != nil, let alert = lastAlert {
            LiveAlert.shared.update(senior: seniorTitle, state: "awaiting_helper", task: guardTask,
                                    question: alert.title, step: nil, steps: 0,
                                    paused: true, linked: isConfigured)
            return
        }
        // Une question pour le proche n'appelle pas l'aidant.
        let st = (state == "awaiting_helper" && questionToSenior) ? "active" : state
        LiveAlert.shared.update(senior: seniorTitle, state: st, task: task,
                                question: question?.text, step: planStep, steps: plan.count,
                                paused: seniorPaused, linked: isConfigured)
    }

    private func notify(_ s: String) {
        // La grande carte de l'écran verrouillé s'en charge déjà (écran allumé, son).
        if LiveAlert.shared.isRunning { UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
        let who = seniorTitle
        if s == "awaiting_approval" {
            notifyLocal(title: "\(who) demande de l’aide", body: task.isEmpty ? "Un plan attend votre accord." : "« \(task) » : un plan attend votre accord.")
        } else {
            notifyLocal(title: "\(who) a besoin de vous", body: question?.text ?? "Holo attend votre aide.")
        }
    }

    private func notifyLocal(title: String, body: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let c = UNMutableNotificationContent()
        c.interruptionLevel = .timeSensitive
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: Actions

    func dismissGuardAlert() {
        guard let id = guardAlertId else { return }
        send(["type": "dismiss_alert", "alert_id": id])
    }

    func acknowledgeGuardAlert() {
        guard let id = guardAlertId else { return }
        send(["type": "ack_alert", "alert_id": id])
    }

    func approvePlan() { planBusy = true; send(["type": "approve_plan"]) }
    func refinePlan(_ text: String) { planBusy = true; send(["type": "refine_plan", "text": text]) }
    func refusePlan() { iRefusedPlan = true; send(["type": "refuse_plan"]) }
    func answer(_ t: String) { send(["type": "answer", "text": t]) }
    func pause() { pausing = true; send(["type": "pause"]); showToast("Pause demandée : l’action en cours se termine.") }
    func refresh() { send(["type": "refresh"]) }

    func setAiming(_ on: Bool) {
        aiming = on && state == "awaiting_helper"
        target = nil
        if aiming { refresh() }   // la dernière image date du dernier pas de Holo
    }

    func confirmClick() {
        guard let t = target, let id = frameId, !sending else { return }
        sending = true
        send(["type": "click", "frame_id": id, "x": t.x, "y": t.y])
    }

    func requestLesson() { lessonBusy = true; send(["type": "draft_lesson"]) }
    static func shortcutLabel(_ s: [String: Any]?) -> String? {
        guard let folder = s?["folder"] as? String else { return nil }
        let names = ["downloads": "Téléchargements", "pictures": "Images", "documents": "Documents",
                     "desktop": "Bureau", "videos": "Vidéos", "music": "Musique"]
        let sub = (s?["subfolder"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let root = names[folder.lowercased()] ?? folder
        return sub.isEmpty ? root : "\(root) › \(sub)"
    }

    func approveLesson() {
        let steps = draftSteps.map { ["instruction": $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines)] }
        send(["type": "approve_lesson", "lesson": ["title": draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), "steps": steps]])
    }
}
