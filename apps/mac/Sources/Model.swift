import AppKit
import Observation
import SwiftUI

enum AppScreen { case home, consent, session, lesson }

struct Helper: Identifiable, Equatable {
    var id: String
    var name: String
    var relation: String
    /// Support connecté en ce moment (`helpers[].online`), faux si absent.
    var online = false
}

/// Quelqu'un a tapé le code à 6 chiffres sans clé : il ne devient support qu'avec l'accord de la personne.
struct PairRequest: Equatable {
    var req: String
    var name: String
    var relation: String
}

struct RemoteRequest: Equatable {
    var from: String
    var task: String
    /// Ticket en attente que le support reprend (ou rendez-vous arrivé).
    var ticket: String? = nil
    var rdv = false
}

/// Demande partie en ticket sans support disponible.
struct QueuedTicket: Equatable {
    var ticket: String
    var number: Int
    var task: String
    var rdv: Date?
}

enum SessionState: String {
    case planning, awaiting_approval, active, awaiting_helper, done, stopped
    var isOpen: Bool { self != .done && self != .stopped }
}

@MainActor
@Observable
final class AppModel {
    var connected = false
    var screen: AppScreen = .home
    var state: SessionState?
    var sessionWhere: String?
    /// L'aide est en pause à la demande de la personne aidée : Holo n'agit plus et
    /// elle retrouve sa souris et son clavier.
    var paused = false
    /// Dernier message du serveur : sans nouvelles, le verrou des entrées se lève.
    @ObservationIgnored private var lastHeard = Date()
    var task = ""
    var plan: [String] = []
    /// Étape du plan validé que Holo exécute (à partir de 1). Absente d'un ancien serveur.
    var planStep: Int?
    var question: String?
    /// Vrai quand Holo pose la question à la personne aidée elle-même (`ask_senior`).
    var questionForMe = false
    var questionOptions: [String] = []
    var answer: String?
    var currentAction: String?
    var lessons: [Lesson] = []
    var notice: String?
    var lesson: Lesson?
    var screenOK = Permissions.screenOK
    var axOK = Permissions.accessibilityOK
    var permissionsDismissed = false
    /// Accord de partage d'écran donné une fois, gardé ; retirable dans Réglages.
    var screenConsent = UserDefaults.standard.bool(forKey: "screenConsent")
    var showSettings = false
    var captureError: String?
    /// Plus de pages d'introduction : l'app s'ouvre directement sur l'accueil.
    /// (L'accueil en 4 étapes reste dans le code, sans être montré.)
    var onboarded = true
    /// Dans le modèle et non dans la vue : changer la taille du texte recrée
    /// toute la fenêtre (`.id(textScale)`), l'accueil doit garder son étape.
    var onboardingStep = 0
    var textScale = TextScale.current
    var realtimeProtection = GuardSignals.enabled
    var helpers: [Helper] = []
    var pairCode: String?
    var pairURL: String?
    /// Lien `papai://` du QR, envoyé par le serveur (`app_url`) ou construit depuis `pairURL`.
    var pairAppURL: String?
    var pairAdded: String?
    /// Vrai pour une invitation à envoyer (SMS, WhatsApp…), valable 24 h.
    var pairLong = false
    var pairExpires = 600
    var remoteRequest: RemoteRequest?
    var queued: QueuedTicket?
    var queuedShown = false
    var pairRequest: PairRequest?
    var showHelpers = false
    var pairingWhenConnected = false
    var pendingTask = ""
    var pendingAutomation: Lesson?
    var actions: [String] = []
    var guardAlert: GuardAlert?
    var stoppedBy: String?
    var guardAcknowledged = false

    @ObservationIgnored let gate = StopGate()
    @ObservationIgnored let client = BridgeClient()
    @ObservationIgnored let webHost = WebAgentHost()
    @ObservationIgnored private var webFronted = false
    @ObservationIgnored weak var window: NSWindow? { didSet { watchWindow(); applyLevel() } }
    /// La grande fenêtre est rangée pour laisser voir ce que fait Holo.
    @ObservationIgnored private var compact = false
    /// La personne a rouvert PapAI en grand pendant la tâche : on la laisse, jusqu'au prochain état.
    @ObservationIgnored private var userExpanded = false
    @ObservationIgnored private var lastState: SessionState?
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var autoSent = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// Vrai entre la connexion et la réponse du serveur au `hello`.
    @ObservationIgnored private var awaitingInitialHelpers = false
    @ObservationIgnored private var homeTimer: Task<Void, Never>?

    var sessionOpen: Bool { state?.isOpen ?? false }
    var serverURL: String {
        let stored = UserDefaults.standard.string(forKey: "server")?.trimmingCharacters(in: .whitespaces) ?? ""
        if !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["PAPAI_SERVER"], !env.isEmpty { return env }
        return "ws://localhost:8000/ws/bridge"
    }
    /// Serveur PapAI officiel : sans réglage, le Mac y crée son espace au premier lancement.
    static let officialHTTP = "https://papai-450417131702.europe-west1.run.app"
    /// Jeton d'inscription d'une organisation (service IT) : préférence gérée
    /// (`defaults write … orgToken ins-…` ou profil MDM), ou PAPAI_ORG.
    var orgToken: String {
        let t = (ProcessInfo.processInfo.environment["PAPAI_ORG"]
                 ?? UserDefaults.standard.string(forKey: "orgToken") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("ins-") && t.count <= 100 ? t : ""
    }
    var orgName: String { UserDefaults.standard.string(forKey: "orgName") ?? "" }
    private var machineName: String {
        [NSFullUserName(), Host.current().localizedName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var needsSpace: Bool {
        let stored = UserDefaults.standard.string(forKey: "server")?.trimmingCharacters(in: .whitespaces) ?? ""
        return stored.isEmpty && (ProcessInfo.processInfo.environment["PAPAI_SERVER"] ?? "").isEmpty
    }
    var httpBase: String {
        var s = serverURL
        s = s.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
        if s.hasSuffix("/ws/bridge") { s.removeLast("/ws/bridge".count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
<<<<<<< ours
    var firstName: String {
        let n = UserDefaults.standard.string(forKey: "firstName")?.trimmingCharacters(in: .whitespaces) ?? ""
        return n
=======
    /// Propriété observée (et non lue dans UserDefaults à chaque fois) : l'accueil
    /// « Bonsoir <prénom> » se met à jour dès qu'on change le prénom dans les Réglages.
    var firstName = AppModel.storedFirstName

    /// Prénom par défaut tant que la personne n'en a pas choisi un dans les Réglages.
    static let defaultFirstName = "Christine"
    static var storedFirstName: String {
        let n = UserDefaults.standard.string(forKey: "firstName")?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? defaultFirstName : n
>>>>>>> theirs
    }

    /// Qui aide : toujours au singulier pour accorder le verbe qui suit.
    var helperName: String {
        switch helpers.count {
        case 0: "votre support"
        case 1: helpers[0].name
        case 2: "\(helpers[0].name) ou \(helpers[1].name)"
        default: "votre support"
        }
    }
    var HelperName: String {
        let n = helperName
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    /// L'aidant qui a validé le plan, envoyé par le serveur pendant la session.
    var sessionHelper: String?
    /// Qui s'occupe de la demande, au singulier : « Quentin s'en occupe ».
    var carer: String {
        if let n = sessionHelper, !n.isEmpty { return n }
        return helpers.count == 1 ? helpers[0].name : "Votre support"
    }

    // MARK: Accueil et proches

    func setFirstName(_ name: String) {
        UserDefaults.standard.set(name.trimmingCharacters(in: .whitespaces), forKey: "firstName")
        sendProfile()
    }

    /// Le prénom réellement saisi (sans la valeur d'exemple), transmis au serveur
    /// pour que l'aidant lise « Vous allez aider Sophie » et non un nom figé.
    func sendProfile() {
        let n = Self.storedFirstName
        // Les proches connus voyagent avec le profil : le serveur les retrouve après un redémarrage.
        let known = helpers.isEmpty ? Self.cachedHelpers() : helpers.map { ["id": $0.id, "name": $0.name, "relation": $0.relation] }
        var msg: [String: Any] = ["type": "profile", "known_helpers": known, "protection": realtimeProtection]
        if !n.isEmpty { msg["name"] = n }
        client.send(msg)
    }

    private static let helpersKey = "knownHelpers"
    static func cachedHelpers() -> [[String: String]] {
        UserDefaults.standard.array(forKey: helpersKey) as? [[String: String]] ?? []
    }
    /// Retire un proche aussi de la copie locale (sinon il reviendrait au prochain démarrage).
    private var removing = false

    func setTextScale(_ v: Double) {
        TextScale.current = v
        textScale = v
    }

    func setRealtimeProtection(_ on: Bool) {
        GuardSignals.enabled = on
        realtimeProtection = on
        sendProfile()
    }

    func finishOnboarding() {
        // L'inscription vaut accord de partage d'écran pendant les demandes d'aide.
        UserDefaults.standard.set(true, forKey: "screenConsent")
        screenConsent = true
        UserDefaults.standard.set(true, forKey: "onboarded")
        onboarded = true
        permissionsDismissed = true
        stopPairing()
    }

    func startPairing(long: Bool = true) {
        pairingWhenConnected = false
        pairAdded = nil
        client.send(long ? ["type": "pair_start", "long": true] : ["type": "pair_start"])
    }

    /// Le texte de l'invitation envoyée au proche, avec le lien d'appairage.
    var invitationText: String {
<<<<<<< ours
        let n = UserDefaults.standard.string(forKey: "firstName")?.trimmingCharacters(in: .whitespaces) ?? ""
        let who = n.isEmpty ? "Votre support" : n
=======
        let n = Self.storedFirstName
        let who = n.isEmpty ? "Une personne de votre entourage" : n
>>>>>>> theirs
        return "\(who) aimerait que vous l'aidiez sur son ordinateur avec PapAI. Ouvrez ce lien sur votre téléphone pour vous relier (valable 24 heures) :"
    }

    func stopPairing() {
        pairingWhenConnected = false
        pairCode = nil
        pairURL = nil
        pairAppURL = nil
        pairLong = false
    }

    func openSupportPairing() {
        showHelpers = true
        pairingWhenConnected = true
        startPendingPairing()
    }

    func startPendingPairing() {
        guard connected, showHelpers, pairingWhenConnected else { return }
        startPairing()
    }

    /// `papai://pair?u=<url encodée>` : l'appareil photo de l'iPhone ouvre l'app, pas Safari.
    static func appPairingURL(_ url: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return "papai://pair?u=" + (url.addingPercentEncoding(withAllowedCharacters: allowed) ?? url)
    }

    func removeHelper(_ h: Helper) {
        removing = true
        client.send(["type": "remove_helper", "id": h.id])
    }

    /// Le proche propose une session : rien ne démarre sans ce clic.
    func acceptRemote() {
        guard let r = remoteRequest else { return }
        remoteRequest = nil
        let task = r.task.isEmpty ? "\(r.from) propose de m'aider sur l'ordinateur" : r.task
        askHelp(task: task, requestedBy: r.from, ticket: r.ticket)
    }

    func answerPair(_ accept: Bool) {
        guard let r = pairRequest else { return }
        pairRequest = nil
        client.send(["type": "pair_decision", "req": r.req, "accept": accept])
    }

    func refuseRemote() {
        let ticket = remoteRequest?.ticket
        remoteRequest = nil
        var msg: [String: Any] = ["type": "remote_answer", "accepted": false]
        if let ticket { msg["ticket"] = ticket }
        client.send(msg)
    }

    /// Rendez-vous pour la demande en attente : dans 1 h, demain 9 h ou 14 h.
    func scheduleTicket(_ slot: String) {
        guard let q = queued else { return }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let at: Date?
        switch slot {
        case "1h": at = Date().addingTimeInterval(3600)
        case "demain9": at = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case "demain14": at = cal.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow)
        default: at = nil
        }
        guard let at else { return }
        client.send(["type": "ticket_schedule", "ticket": q.ticket, "at": Int(at.timeIntervalSince1970)])
    }

    // MARK: Démarrage

    func start() {
        guard !started else { return }
        started = true
        client.onMessage = { [weak self] m in self?.handle(m) }
        webHost.onChange = { [weak self] id in
            self?.client.send(["type": "web_agent", "session_id": id ?? NSNull()])
        }
        InputLock.shared.allowedRect = { [weak self] in self?.protectedRect() }
        InputLock.shared.onEscape = { [weak self] in self?.stop() }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if InputLock.shared.isOn, Date().timeIntervalSince(self.lastHeard) > 45 {
                    self.webHost.stopLocal()
                    InputLock.shared.set(false)
                }
            }
        }
        client.onConnection = { [weak self] ok in
            guard let self else { return }
            self.connected = ok
            // Plus de connexion : la personne ne doit jamais rester bloquée.
            if !ok {
                self.webHost.stopLocal()
                InputLock.shared.set(false)
            }
            if ok {
                // Démo (PAPAI_DEMO=alert) : l'alerte locale reste affichée.
                self.awaitingInitialHelpers = ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil
                self.sendProfile()
            }
            self.startPendingPairing()
            // Test : PAPAI_AUTOTASK lance une demande dès la connexion.
            if ok, !self.autoSent, let t = ProcessInfo.processInfo.environment["PAPAI_AUTOTASK"], !t.isEmpty {
                self.autoSent = true
                self.askHelp(task: t)
            }
        }
        reconnect()
        Task { await refreshLessons() }
        if ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil {
            // Protection en temps réel : trois signaux textuels toutes les 8 s, jamais l'écran.
            Task {
                while true {
                    try? await Task.sleep(nanoseconds: GuardSignals.period)
                    guard connected, realtimeProtection else { continue }
                    let signals = await GuardSignals.collect(withURL: !sessionOpen)
                    if connected, realtimeProtection { client.send(signals) }
                }
            }
        }
        Task {
            while true {
                screenOK = Permissions.screenOK
                axOK = Permissions.accessibilityOK
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        // Mode capture d'écran : PAPAI_DEMO=awaiting_approval etc.
        if let demo = ProcessInfo.processInfo.environment["PAPAI_DEMO"] {
            permissionsDismissed = true
            connected = true
            if demo.hasPrefix("onboarding") { onboarded = false; return }
            onboarded = true
            helpers = [Helper(id: "1", name: "Claire", relation: "sa fille")]
            if demo == "settings" || demo == "helpers_pair" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if demo == "settings" { self.showSettings = true }
                    else {
                        self.pairCode = "482913"
                        self.pairURL = "https://papai.example/p/482913"
                        self.pairAppURL = Self.appPairingURL(self.pairURL!)
                        self.pairLong = true
                        self.showHelpers = true
                    }
                }
                return
            }
            if demo == "remote" {
                remoteRequest = RemoteRequest(from: "Claire", task: "Mettre à jour votre ordinateur")
                return
            }
            let json = #"[{"id":"a","title":"Mes photos de Noël","shortcut":{"folder":"pictures"},"steps":[{"instruction":"Ouvrez le Finder"}]},{"id":"b","title":"Mes documents","shortcut":{"folder":"documents"}}]"#
            lessons = (try? JSONDecoder().decode([Lesson].self, from: Data(json.utf8))) ?? []
            if demo == "home" { return }
            if demo == "home_empty" { lessons = []; return }
            if demo == "alert" {
                guardAlert = GuardAlert(level: "danger",
                                        title: "Quelqu'un est en train de prendre la main sur votre ordinateur",
                                        detail: "Le logiciel « anydesk » est en marche. Il permet à une personne à distance de voir votre écran et de cliquer à votre place. Est-ce bien quelqu'un que vous connaissez ?")
                return
            }
            if demo == "consent" { pendingTask = "Je ne retrouve plus mes photos de Noël"; screen = .consent; return }
            guard let s = SessionState(rawValue: demo) else { return }
            task = "Je ne retrouve plus mes photos de Noël"
            plan = ["Ouvrir le Finder", "Aller dans le dossier Images", "Ouvrir le dossier « Noël 2025 »"]
            planStep = 2
            answer = "Vos photos de Noël sont ouvertes dans le dossier Images."
            currentAction = "Je clique sur l'icône du Finder"
            actions = ["J'ouvre la recherche du Mac", "J'écris « Finder »", "Je clique sur l'icône du Finder"]
            question = "Je vois deux dossiers « Noël ». Lequel faut-il ouvrir ?"
            state = s
            screen = .session
        }
    }

    func reconnect() {
        guard ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil else { return }
        if needsSpace {
            Task { [weak self] in await self?.createSpace() }
            return
        }
        guard let url = URL(string: serverURL) else { return }
        client.start(url: url)
        let tok = orgToken
        if !tok.isEmpty, UserDefaults.standard.string(forKey: "orgJoined") != tok, serverURL.contains("/k/") {
            Task { [weak self] in await self?.joinOrg(tok) }
        }
    }

    @ObservationIgnored private var joiningOrg = false

    /// Poste déjà installé : le jeton déposé par l'IT le rattache à son organisation.
    /// Hors ligne, on réessaie ; un refus du serveur (jeton inconnu, autre organisation) est définitif.
    private func joinOrg(_ tok: String) async {
        guard !joiningOrg else { return }
        joiningOrg = true
        defer { joiningOrg = false }
        var delay = 5.0
        while orgToken == tok, UserDefaults.standard.string(forKey: "orgJoined") != tok {
            guard let url = URL(string: httpBase + "/org") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["org": tok, "name": machineName])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 10
            let r = try? await URLSession.shared.data(for: req)
            let status = (r?.1 as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let data = r?.0,
               let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                UserDefaults.standard.set(tok, forKey: "orgJoined")
                UserDefaults.standard.set(d["org"] as? String ?? "", forKey: "orgName")
                await refreshLessons()
                return
            }
            if (400..<500).contains(status) && status != 429 { return }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 60)
        }
    }

    /// Premier lancement : `POST /spaces` donne l'adresse du pont, clé comprise. Rien à régler.
    private func createSpace(withOrg: Bool = true) async {
        guard let url = URL(string: Self.officialHTTP + "/spaces") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let tok = withOrg ? orgToken : ""
        req.httpBody = tok.isEmpty ? Data("{}".utf8)
            : try? JSONSerialization.data(withJSONObject: ["org": tok, "name": machineName])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let r = try? await URLSession.shared.data(for: req)
        if !tok.isEmpty, (r?.1 as? HTTPURLResponse)?.statusCode == 403 {
            // Jeton refusé : le poste a quand même son espace, hors organisation.
            await createSpace(withOrg: false)
            return
        }
        if let data = r?.0,
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let b = d["bridge_url"] as? String, b.hasPrefix("wss://") || b.hasPrefix("ws://"), b.contains("/k/") {
            if let org = d["org"] as? String, !tok.isEmpty {
                UserDefaults.standard.set(tok, forKey: "orgJoined")
                UserDefaults.standard.set(org, forKey: "orgName")
            }
            UserDefaults.standard.set(b, forKey: "server")
            reconnect()
            return
        }
        try? await Task.sleep(for: .seconds(30))  // serveur injoignable : on réessaie
        reconnect()
    }

    func refreshLessons() async {
        guard ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil,
              let url = URL(string: httpBase + "/lessons") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let list = try? JSONDecoder().decode([Lesson].self, from: data) {
            lessons = list
        }
    }

    // MARK: Fenêtre

    func applyLevel() {
        // La grande fenêtre ne reste plus au premier plan : elle masquerait Holo.
        window?.level = .normal
        if state != lastState {
            let wasOpen = lastState?.isOpen ?? false
            userExpanded = false; lastState = state
            // Fin de l'aide (faite ou arrêtée) : la grande fenêtre revient pour le dire.
            if wasOpen && !sessionOpen {
                compact = false
                showMainWindow()
            }
        }
        // Holo agit (ou l'aidant a la main) : on range PapAI, l'encart suffit.
        let wantCompact = sessionOpen && !userExpanded
            && (state == .active || (state == .awaiting_helper && !questionForMe))
        if wantCompact != compact {
            compact = wantCompact
            if wantCompact {
                window?.orderOut(nil)
                MiniPanel.shared.show(model: self)
            } else {
                showMainWindow()
            }
        } else if wantCompact, !MiniPanel.shared.isVisible {
            MiniPanel.shared.show(model: self)
        }
        // Souris et clavier réservés à Holo et à l'aidant pendant qu'il agit.
        // Une question posée à la personne (se connecter à un site…) lui rend la main.
        let holoActs = (state == .active || (state == .awaiting_helper && !questionForMe)) && !paused && !gate.isStopped
        InputLock.shared.set(holoActs)
    }

    /// Bouton « agrandir » de l'encart : la grande fenêtre revient.
    func expandWindow() {
        userExpanded = true
        compact = false
        showMainWindow()
    }

    private func showMainWindow() {
        MiniPanel.shared.hide()
        if let w = window {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Fenêtre réduite à la main : l'encart reste en bas à droite.
    private func watchWindow() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        guard let w = window else { return }
        let nc = NotificationCenter.default
        windowObservers = [
            nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { MiniPanel.shared.show(model: self) } }
            },
            nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.compact == false { MiniPanel.shared.hide() } }
            },
        ]
    }

    /// Pause ou reprise, depuis l'écran de la personne aidée.
    func togglePause() {
        guard sessionOpen else { return }
        paused.toggle()
        client.send(["type": paused ? "pause" : "resume"])
        applyLevel()
    }

    /// Cadre de la fenêtre PapAI, en points écran, origine en haut à gauche.
    func protectedRect() -> CGRect? {
        // Fenêtre rangée : c'est l'encart qu'il faut protéger.
        guard let w = window, w.isVisible, !w.isMiniaturized else { return MiniPanel.shared.protectedRect() }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let f = w.frame
        return CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height).insetBy(dx: -4, dy: -4)
    }

    // MARK: Demande d'aide

    /// L'accord de partage est donné une seule fois, à l'inscription : une demande
    /// d'aide part directement, sans deuxième confirmation (décision de l'équipe).
    func requestConsent(task: String) {
        if !screenConsent {
            UserDefaults.standard.set(true, forKey: "screenConsent")
            screenConsent = true
        }
        askHelp(task: task)
    }

    /// Transcription en direct de la dictée, montrée à l'aidant pendant qu'elle parle.
    private var lastDictationSent = Date.distantPast
    func sendDictation(_ text: String, final: Bool = false) {
        let now = Date()
        guard final || now.timeIntervalSince(lastDictationSent) > 0.35 else { return }
        lastDictationSent = now
        client.send(["type": "dictation", "text": String(text.prefix(300)), "final": final])
    }

    /// Réponse de la personne aidée à une question de Holo qui lui est posée.
    func answerSenior(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        client.send(["type": "senior_answer", "text": t])
    }

    func giveConsent() {
        UserDefaults.standard.set(true, forKey: "screenConsent")
        screenConsent = true
        if let a = pendingAutomation {
            pendingAutomation = nil
            pendingTask = ""
            screen = .home
            runAutomation(a)
            return
        }
        askHelp(task: pendingTask)
    }

    func revokeConsent() {
        UserDefaults.standard.set(false, forKey: "screenConsent")
        screenConsent = false
    }

    func cancelConsent() {
        pendingTask = ""
        pendingAutomation = nil
        screen = .home
    }

    func askHelp(task: String, requestedBy: String? = nil, ticket: String? = nil) {
        guard guardAlert == nil else { return }
        queuedShown = false
        if let ticket, queued?.ticket == ticket { queued = nil }
        gate.reset()
        stoppedBy = nil
        sessionWhere = nil
        guardAcknowledged = false
        homeTimer?.cancel()
        self.task = task
        pendingTask = ""
        plan = []; planStep = nil; question = nil; answer = nil; currentAction = nil; actions = []
        sessionHelper = nil
        AppUsage.shared.noteRequest(task)
        webFronted = false
        state = .planning
        screen = .session
        applyLevel()
        var msg: [String: Any] = ["type": "help_request", "task": task]
        if let requestedBy { msg["requested_by"] = requestedBy }
        if let ticket { msg["ticket"] = ticket }
        client.send(msg)
    }

    /// Le verrou local passe d'abord, puis le serveur est prévenu.
    func stop() {
        gate.raise()
        webHost.stopLocal(notifyServer: false)
        client.send(["type": "stop"])
        state = .stopped
        currentAction = nil
        applyLevel()
    }

    func backHome() {
        guard guardAlert == nil else { return }
        homeTimer?.cancel()
        screen = .home
        state = nil
        applyLevel()
    }

    // MARK: Messages du serveur

    private func handle(_ m: [String: Any]) {
        lastHeard = Date()
        switch m["type"] as? String {
        case "capture":
            guard let req = m["req"] as? String else { return }
            Task { await doCapture(req) }
        case "execute":
            guard let req = m["req"] as? String, let action = m["action"] as? [String: Any] else { return }
            Task { await doExecute(req, action) }
        case "status":
            applyStatus(m)
        case "web_agent_start":
            if sessionOpen && !gate.isStopped { webHost.start() }
        case "web_agent_stop":
            webHost.stopLocal(notifyServer: false)
        case "answer":
            answer = m["content"] as? String
        case "helpers":
            let list = (m["helpers"] as? [[String: Any]]) ?? []
            helpers = list.compactMap { d in
                guard let id = d["id"] as? String, let n = d["name"] as? String else { return nil }
                return Helper(id: id, name: n, relation: d["relation"] as? String ?? "",
                              online: d["online"] as? Bool ?? false)
            }
            // Premier `helpers` après le `hello` : le serveur envoie l'alerte en attente
            // juste après. Rien ne suit si elle a été rejetée pendant la coupure.
            if awaitingInitialHelpers {
                awaitingInitialHelpers = false
                guardAlert = nil
            }
            // Une liste vide d'un serveur qui vient de redémarrer n'efface pas la copie locale.
            if !helpers.isEmpty || removing {
                UserDefaults.standard.set(helpers.map { ["id": $0.id, "name": $0.name, "relation": $0.relation] },
                                          forKey: Self.helpersKey)
                removing = false
            } else if !Self.cachedHelpers().isEmpty {
                sendProfile()
            }
            if let added = m["added"] as? String {
                pairAdded = added
                stopPairing()
            }
        case "lessons_changed":
            Task {
                await refreshLessons()
                if let t = m["title"] as? String { showNotice("Nouvel automate : « \(t) »") }
            }
        case "pair_code":
            pairCode = m["code"] as? String
            pairURL = m["url"] as? String
            pairAppURL = m["app_url"] as? String ?? pairURL.map(Self.appPairingURL)
            pairLong = m["long"] as? Bool ?? false
            pairExpires = m["expires_in"] as? Int ?? 600
        case "alert":
            webHost.stopLocal()
            // Le gardien a reconnu une situation : le proche est prévenu en même temps.
            gate.raise()
            InputLock.shared.set(false)
            guardAlert = GuardAlert(level: m["level"] as? String ?? "attention",
                                    title: m["title"] as? String ?? "",
                                    detail: m["detail"] as? String ?? "",
                                    id: m["alert_id"] as? String,
                                    blocked: m["blocked"] as? Bool ?? false,
                                    acknowledged: m["acknowledged"] as? Bool ?? (m["acknowledged_by"] as? String != nil))
            guardAcknowledged = guardAlert?.acknowledged ?? false
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        case "alert_acknowledged":
            if let id = m["alert_id"] as? String, id == guardAlert?.id {
                guardAlert?.acknowledged = true
                guardAcknowledged = true
            }
        case "alert_cleared":
            if let id = m["alert_id"] as? String, id == guardAlert?.id { guardAlert = nil }
        case "automation_refused":
            // L'écran était déjà passé en préparation : retour à l'accueil, avec la raison.
            state = nil
            screen = .home
            applyLevel()
            showNotice(m["reason"] as? String ?? "Cet automate n'a pas pu être lancé.")
        case "ticket_refused":
            queuedShown = false
            showNotice(m["reason"] as? String ?? "Ce rendez-vous n'est pas possible.")
        case "pair_confirm":
            guard let req = (m["req"] as? String) ?? (m["req"] as? Int).map(String.init) else { return }
            pairRequest = PairRequest(req: req, name: m["name"] as? String ?? "Quelqu'un",
                                      relation: m["relation"] as? String ?? "")
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        case "ticket_queued":
            // Aucun support disponible : la demande attend, retour à l'accueil.
            queued = QueuedTicket(ticket: m["ticket"] as? String ?? "", number: m["number"] as? Int ?? 0,
                                  task: m["task"] as? String ?? task, rdv: nil)
            queuedShown = true
            state = nil
            screen = .home
            applyLevel()
        case "ticket_scheduled":
            if let at = m["at"] as? Double, queued?.ticket == m["ticket"] as? String {
                queued?.rdv = Date(timeIntervalSince1970: at)
            }
        case "remote_request":
            guard !sessionOpen else { return }
            remoteRequest = RemoteRequest(from: m["from"] as? String ?? "Votre support",
                                          task: m["task"] as? String ?? "",
                                          ticket: m["ticket"] as? String, rdv: m["rdv"] as? Bool ?? false)
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        default:
            break
        }
    }

    private func applyStatus(_ m: [String: Any]) {
        stoppedBy = m["stopped_by"] as? String
        sessionWhere = m["where"] as? String
        if let ack = m["guard_acknowledged"] as? Bool { guardAcknowledged = ack }
        guard screen == .session else { return }
        if gate.isStopped { state = .stopped; applyLevel(); return }
        let before = state
        if let s = (m["state"] as? String).flatMap(SessionState.init(rawValue:)) { state = s }
        if state == .done, before != .done { scheduleHome() }
        if let t = m["task"] as? String, !t.isEmpty { task = t }
        plan = (m["plan"] as? [String]) ?? []
        planStep = m["plan_step"] as? Int
        paused = m["paused"] as? Bool ?? false
        if let h = m["helper_name"] as? String, !h.isEmpty { sessionHelper = h }
        let q = m["question"] as? [String: Any]
        question = q?["question"] as? String
        questionForMe = (q?["to"] as? String) == "senior"
        questionOptions = q?["options"] as? [String] ?? []
        if state != .active { currentAction = nil }
        if state == .done || state == .stopped {
            webHost.stopLocal()
        } else if (m["where"] as? String) == "web", state == .active || state == .awaiting_helper, !webFronted {
            webFronted = true
            webHost.bringToFront()
        }
        applyLevel()
    }

    /// Étape 7 : le partage est déjà coupé ; l'écran de fin reste un moment
    /// puis l'accueil revient tout seul.
    private func scheduleHome() {
        homeTimer?.cancel()
        homeTimer = Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if !Task.isCancelled, screen == .session, state == .done { backHome() }
        }
    }

    private func doCapture(_ req: String) async {
        if gate.isStopped { return }
        do {
            let f = try await ScreenGrabber.capture()
            captureError = nil
            if gate.isStopped { return }
            client.send(["type": "frame", "req": req, "frame_id": UUID().uuidString.prefix(8).lowercased(),
                         "png_b64": f.pngB64, "width": f.width, "height": f.height])
        } catch {
            captureError = "Capture impossible : \(error.localizedDescription)"
            print("[papai] \(captureError ?? "")")
        }
    }

    private func doExecute(_ req: String, _ action: [String: Any]) async {
        let name = action["name"] as? String ?? ""
        let args = action["args"] as? [String: Any] ?? [:]
        func reply(_ text: String, refused: Bool) {
            client.send(["type": "result", "req": req, "result": text, "refused": refused])
        }
        if gate.isStopped || guardAlert != nil { reply("Assistance arrêtée ou alerte du gardien en attente.", refused: true); return }
        let said = describeAction(name, args)
        currentAction = said
        if actions.last != said { actions.append(said) }
        do {
            let r = try await Actuator.run(name: name, args: args, gate: gate, protected: protectedRect())
            reply(r, refused: false)
        } catch ActionError.stopped {
            reply("Arrêt demandé par la personne aidée.", refused: true)
        } catch ActionError.protectedZone {
            // Refus ciblé : l'agent l'apprend et continue, la session survit.
            reply("Action refusée : cette zone appartient à la fenêtre PapAI, que seule la personne aidée peut manipuler.", refused: false)
        } catch ActionError.noAccessibility {
            reply("Autorisation Accessibilité manquante sur cet ordinateur.", refused: true)
        } catch ActionError.unknownKey(let k) {
            reply("Touche inconnue : \(k)", refused: false)
        } catch {
            reply("échec : \(error.localizedDescription)", refused: true)
        }
    }

    // MARK: Automates

    func runShortcut(_ l: Lesson) {
        if !(l.actions ?? []).isEmpty { runAutomation(l); return }
        guard let sc = l.shortcut else { openLesson(l); return }
        let r = Shortcuts.open(sc)
        if r.ok {
            showNotice("C'est ouvert.")
        } else {
            showNotice("Je ne retrouve pas ce dossier. \(HelperName) a reçu un message pour s'en occuper.")
            client.send(["type": "automation_failed", "title": l.title, "detail": r.detail])
        }
    }

    /// Un automate importé par un support, lancé en un clic. Pas de
    /// validation à chaque fois : le support l'a validé à l'import.
    func runAutomation(_ l: Lesson) {
        let acts = l.actions ?? []
        if let p = l.platforms, !p.contains("mac") {
            showNotice("Cet automate est prévu pour un autre ordinateur.")
            return
        }
        let holo = acts.first { $0.kind == "holo" }
        if holo != nil && !screenConsent {
            pendingAutomation = l
            pendingTask = l.title
            screen = .consent
            return
        }
        gate.reset()
        showNotice("C'est parti : \(l.title)…")
        Task {
            let r = await Automations.play(l, base: httpBase, gate: gate)
            if gate.isStopped { showNotice("Arrêté. Rien d'autre ne sera fait."); return }
            guard r.ok else {
                showNotice("« \(l.title) » n'a pas pu aller au bout. \(HelperName) a reçu un message pour s'en occuper.")
                client.send(["type": "automation_failed", "title": l.title, "detail": r.detail])
                return
            }
            guard let holo else { showNotice(r.detail.isEmpty ? "C'est fait." : r.detail); return }
            homeTimer?.cancel()
            task = holo.goal ?? l.title
            plan = []; planStep = nil; question = nil; answer = nil; currentAction = nil; actions = []
            sessionHelper = nil
            state = .planning
            screen = .session
            applyLevel()
            client.send(["type": "run_automation", "id": l.id])
        }
    }

    func openLesson(_ l: Lesson) {
        lesson = l
        screen = .lesson
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { notice = nil }
        }
    }
}
