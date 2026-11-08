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

struct RemoteRequest: Equatable {
    var from: String
    var task: String
    /// Ticket en attente que le support reprend (ou rendez-vous arrivé).
    var ticket: String? = nil
    var rdv = false
}

/// Demande partie en ticket sans support disponible.
struct QueuedSuggestion: Equatable, Identifiable {
    var id: String
    var title: String
}

struct QueuedTicket: Equatable {
    var ticket: String
    var number: Int
    var task: String
    var rdv: Date?
    var suggestions: [QueuedSuggestion] = []
    var suggestionLancee: String?
}

/// Demande qui a déjà son ticket : encore ouvert, ou réglé avec sa solution.
struct ExistingTicket: Equatable {
    var solved: Bool
    var ticket: String
    var number: Int
    var task: String
    /// Ce que la personne vient de demander, renvoyé tel quel si elle insiste.
    var asked: String
    var status = ""
    var rdv: Date?
    var note = ""
    var by = ""
    var at: Date?
    var steps: [String] = []
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
    /// L'aide est en pause à la demande de l’utilisateur : Holo n'agit plus.
    var paused = false
    /// Dernier message du serveur : sans nouvelles, l'agent navigateur local s'arrête.
    @ObservationIgnored private var lastHeard = Date()
    @ObservationIgnored private var holoActing = false
    var task = ""
    var plan: [String] = []
    /// Étape du plan validé que Holo exécute (à partir de 1). Absente d'un ancien serveur.
    var planStep: Int?
    var question: String?
    /// Vrai quand Holo pose la question à l’utilisateur lui-même (`ask_senior`).
    var questionForMe = false
    var questionOptions: [String] = []
    var answer: String?
    var currentAction: String? {
        didSet { if let currentAction { narration.say(currentAction) } }
    }
    @ObservationIgnored let narration = LocalNarration.shared
    var answerSources: [[String: String]] = []
    var lessons: [Lesson] = []
    var requests: [UserRequest] = []
    var showRequests = false
    var requestsLoading = false
    var requestsError = false
    /// Onglet de l'accueil : 0 Accueil, 1 Automates (affiché dans l'en-tête).
    var homeTab = 0
    var notice: String?
    var lesson: Lesson?
    /// La fiche d'automate ouverte par-dessus l'accueil.
    var docLesson: Lesson?
    /// Où en est l'automate lancé depuis la liste : affiché à la place de « Exécuter », sur sa ligne.
    struct RunStatus: Equatable { var id: String; var text: String; var enCours: Bool }
    var runStatus: RunStatus?
    /// L'automate en cours ou arrêté : il se joue seul. Le support n'est prévenu
    /// que si l’utilisateur appuie sur « Demander une assistance » (en haut à droite).
    struct AutomationRun: Equatable {
        var id: String
        var title: String
        var ticket: String? = nil
        var number: Int? = nil
        /// Étape où l'automate s'est arrêté, et pourquoi.
        var step: Int? = nil
        var reason: String? = nil
        /// Arrêté avant Holo, sur l'accueil.
        var local = false
        var asked = false
        /// Échec local hors ligne : `automation_failed` repart à la reconnexion pour ouvrir le ticket.
        var unsent = false
    }
    var automationRun: AutomationRun?
    var canAskAutomationSupport: Bool {
        guard let r = automationRun else { return false }
        return !r.asked && r.ticket != nil && guardAlert == nil
    }
    private var runStatusTask: Task<Void, Never>?
    var screenOK = Permissions.screenOK
    var axOK = Permissions.accessibilityOK
    var permissionsDismissed = false
    /// Accord de partage d'écran donné une fois, gardé ; retirable dans Réglages.
    var screenConsent = UserDefaults.standard.bool(forKey: "screenConsent")
    var showSettings = false
    var captureError: String?
    var textScale = TextScale.current
    var realtimeProtection = GuardSignals.enabled
    /// Les agents du support IT connus de ce poste (`helpers` du serveur), avec leur présence.
    var helpers: [Helper] = []
    var remoteRequest: RemoteRequest?
    var queued: QueuedTicket?
    var queuedShown = false
    /// Nom de l'organisation qui gère ce poste, connu après l'inscription par jeton.
    var orgName = UserDefaults.standard.string(forKey: "orgName") ?? ""
    var existing: ExistingTicket?
    var pendingTask = ""
    var pendingAutomation: Lesson?
    var pendingAutomationTicket: String?
    var actions: [String] = []
    var guardAlert: GuardAlert?
    var stoppedBy: String?
    var guardAcknowledged = false
    /// Dernier rangement guidé, annulable d'un clic (journal local, `Rangement.swift`).
    var lastTidy: TidyRecord? = TidyJournal.standard.last
    @ObservationIgnored private var tidyScan: TidyScan?

    @ObservationIgnored let gate = StopGate()
    @ObservationIgnored private var planApproved = false
    @ObservationIgnored private var executionState: String?
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
    /// Serveur PapAI officiel : sans serveur géré, le poste y crée son espace au premier lancement.
    static let officialHTTP = "https://papai-450417131702.europe-west1.run.app"
    /// Serveur géré (`server`, profil MDM ou `defaults write`), sinon PAPAI_SERVER.
    var managedServer: String? {
        Poste.managed("server") ?? ProcessInfo.processInfo.environment["PAPAI_SERVER"].flatMap { $0.isEmpty ? nil : $0 }
    }
    /// Jeton d'inscription de l'organisation (service IT) : préférence gérée `orgToken`, ou PAPAI_ORG.
    var orgToken: String {
        Poste.orgToken(ProcessInfo.processInfo.environment["PAPAI_ORG"] ?? Poste.managed("orgToken"))
    }
    /// Vrai quand le jeton vient d'un profil de configuration (et non d'un `defaults write`).
    var orgTokenForced: Bool { Poste.isForced("orgToken") }
    /// Où se connecter : le pont de l'espace du poste, ou créer cet espace d'abord.
    var route: Poste.Route {
        Poste.route(server: managedServer, stored: Poste.managed("bridgeURL"),
                    orgToken: orgToken, official: Self.officialHTTP)
    }
    var serverURL: String {
        if case .bridge(let b) = route { return b }
        return ""
    }
    private var machineName: String {
        [NSFullUserName(), Host.current().localizedName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var httpBase: String {
        switch route {
        case .bridge(let b): Poste.httpBase(b)
        case .createSpace(let base): base
        }
    }
    /// Le nom affiché sur l'accueil : celui du compte macOS de l'employé, ou `displayName` géré.
    /// Il n'y a rien à saisir.
    let displayName = Poste.displayName(managed: Poste.managed("displayName"),
                                        fullName: NSFullUserName(), userName: NSUserName())

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

    // MARK: Profil et support

    /// Le nom du poste, transmis au serveur pour que le support lise « Vous allez aider Christine ».
    func sendProfile() {
        // Les agents connus voyagent avec le profil : le serveur les retrouve après un redémarrage.
        let known = helpers.isEmpty ? Self.cachedHelpers() : helpers.map { ["id": $0.id, "name": $0.name, "relation": $0.relation] }
        var msg: [String: Any] = ["type": "profile", "known_helpers": known, "protection": realtimeProtection]
        if !displayName.isEmpty { msg["name"] = displayName }
        client.send(msg)
    }

    private static let helpersKey = "knownHelpers"
    static func cachedHelpers() -> [[String: String]] {
        UserDefaults.standard.array(forKey: helpersKey) as? [[String: String]] ?? []
    }

    func setTextScale(_ v: Double) {
        TextScale.current = v
        textScale = v
    }

    func setRealtimeProtection(_ on: Bool) {
        GuardSignals.enabled = on
        realtimeProtection = on
        sendProfile()
    }

    /// Le support propose une assistance : rien ne démarre sans ce clic.
    func acceptRemote() {
        guard let r = remoteRequest else { return }
        remoteRequest = nil
        let task = r.task.isEmpty ? "\(r.from) propose de m'aider sur l'ordinateur" : r.task
        askHelp(task: task, requestedBy: r.from, ticket: r.ticket)
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
        _ = DesktopSafety.shared
        guard !started else { return }
        started = true
        client.onMessage = { [weak self] m in self?.handle(m) }
        webHost.onChange = { [weak self] id in
            self?.client.send(["type": "web_agent", "session_id": id ?? NSNull()])
        }
        webHost.onOffSite = { [weak self] url in
            self?.client.send(["type": "web_off_site", "url": url])
        }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if self.holoActing, Date().timeIntervalSince(self.lastHeard) > 45 {
                    self.webHost.stopLocal()
                    self.holoActing = false
                }
            }
        }
        client.onConnection = { [weak self] ok in
            guard let self else { return }
            self.connected = ok
            if ok { Task { await self.refreshLessons() } }
            if ok, let r = self.automationRun, r.unsent, r.ticket == nil {
                self.automationRun?.unsent = false
                self.client.send(["type": "automation_failed", "id": r.id, "step": r.step ?? 1,
                                  "title": r.title, "detail": r.reason ?? ""])
            }
            // Plus de connexion : la personne ne doit jamais rester bloquée.
            if !ok {
                self.narration.context(assistance: self.sessionOpen, speakingAllowed: false)
                self.webHost.stopLocal()
            }
            if ok {
                // Démo (PAPAI_DEMO=alert) : l'alerte locale reste affichée.
                self.awaitingInitialHelpers = ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil
                self.sendProfile()
            }
            // Test : PAPAI_AUTOTASK lance une demande dès la connexion.
            if ok, !self.autoSent, let t = ProcessInfo.processInfo.environment["PAPAI_AUTOTASK"], !t.isEmpty {
                self.autoSent = true
                self.askHelp(task: t)
            }
        }
        reconnect()
        Task { await refreshLessons() }
        if ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil {
            // Protection en temps réel : comparée ici toutes les 8 s, seul ce qui correspond part.
            Task {
                while true {
                    try? await Task.sleep(nanoseconds: GuardSignals.period)
                    guard connected, realtimeProtection else { continue }
                    if let signals = await GuardSignals.collect(withURL: !sessionOpen),
                       connected, realtimeProtection { client.send(signals) }
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
            helpers = [Helper(id: "1", name: "Marc", relation: "Service informatique", online: true)]
            if orgName.isEmpty { orgName = "Acme" }
            if demo == "settings" || demo == "settings_none" {
                if demo == "settings_none" { orgName = ""; helpers = [] }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showSettings = true }
                return
            }
            if demo == "remote" {
                remoteRequest = RemoteRequest(from: "Marc", task: "Mettre à jour votre ordinateur")
                return
            }
            let json = #"[{"id":"a","title":"Dossier comptabilité","shortcut":{"folder":"documents"},"steps":[{"instruction":"Ouvrez le Finder"}]},{"id":"b","title":"Mes téléchargements","shortcut":{"folder":"downloads"}}]"#
            lessons = (try? JSONDecoder().decode([Lesson].self, from: Data(json.utf8))) ?? []
            if demo == "requests" {
                let automate = #"{"id":"print","title":"Configurer mon imprimante","platforms":["mac"],"actions":[{"do":"open_settings","page":"printers"}]}"#
                if let l = try? JSONDecoder().decode(Lesson.self, from: Data(automate.utf8)) { lessons.append(l) }
                requests = (try? JSONDecoder().decode(UserRequestsResponse.self, from: Data(UserRequestsResponse.demo.utf8)).requests) ?? []
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showRequests = true }
                return
            }
            if demo == "tickets" { homeTab = 2; return }
            if demo == "home" { return }
            if demo == "home_empty" { lessons = []; return }
            if demo == "alert" {
                guardAlert = GuardAlert(level: "danger",
                                        title: "Quelqu'un est en train de prendre la main sur votre ordinateur",
                                        detail: "Le logiciel « anydesk » est en marche. Il permet à une personne à distance de voir votre écran et de cliquer à votre place. Est-ce bien quelqu'un que vous connaissez ?")
                return
            }
            if demo == "consent" { pendingTask = "Je ne retrouve plus le dossier de la comptabilité"; screen = .consent; return }
            guard let s = SessionState(rawValue: demo) else { return }
            task = "Je ne retrouve plus le dossier de la comptabilité"
            plan = ["Ouvrir le Finder", "Aller dans le dossier Documents", "Ouvrir le dossier « Comptabilité 2025 »"]
            planStep = 2
            answer = "Le dossier Comptabilité 2025 est ouvert dans Documents."
            currentAction = "Je clique sur l'icône du Finder"
            actions = ["J'ouvre la recherche du Mac", "J'écris « Finder »", "Je clique sur l'icône du Finder"]
            question = "Je vois deux dossiers « Comptabilité ». Lequel faut-il ouvrir ?"
            state = s
            screen = .session
        }
    }

    func reconnect() {
        guard ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil else { return }
        let bridge: String
        switch route {
        case .createSpace(let base):
            Task { [weak self] in await self?.createSpace(base: base) }
            return
        case .bridge(let b):
            bridge = b
        }
        guard let url = URL(string: bridge) else { return }
        client.start(url: url)
        let tok = orgToken
        if !tok.isEmpty, UserDefaults.standard.string(forKey: "orgJoined") != tok, bridge.contains("/k/") {
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
                orgName = d["org"] as? String ?? ""
                UserDefaults.standard.set(orgName, forKey: "orgName")
                await refreshLessons()
                return
            }
            if (400..<500).contains(status) && status != 429 { return }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 60)
        }
    }

    /// Premier lancement : `POST <serveur>/spaces`, avec le jeton de l'organisation, donne
    /// l'adresse du pont, clé comprise. Rien à régler sur le poste.
    private func createSpace(base: String, withOrg: Bool = true) async {
        guard let url = URL(string: base + "/spaces") else { return }
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
            await createSpace(base: base, withOrg: false)
            return
        }
        if let data = r?.0,
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let returned = d["bridge_url"] as? String, let b = Poste.bridge(from: returned, base: base) {
            if let org = d["org"] as? String, !tok.isEmpty {
                UserDefaults.standard.set(tok, forKey: "orgJoined")
                orgName = org
                UserDefaults.standard.set(org, forKey: "orgName")
            }
            // Clé à part de `server` : celle-ci peut être imposée par un profil.
            UserDefaults.standard.set(b, forKey: "bridgeURL")
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
            OfflineLessons.save(data, base: httpBase)
            if list.isEmpty { await seedExampleAutomates() }
        } else if lessons.isEmpty {
            lessons = OfflineLessons.load(base: httpBase)  // pas de réseau : ceux qui n'ont pas besoin de Holo
        }
    }

    /// Espace tout neuf : on y importe une fois les automates d'exemple livrés avec
    /// l'app (`Resources/automates/*.papai`, actions de premier niveau seulement),
    /// pour que « Derniers automates » et l'onglet Automates ne soient pas vides.
    private func seedExampleAutomates() async {
        let flag = "exemplesAutomates.v1"
        guard !UserDefaults.standard.bool(forKey: flag),
              let url = URL(string: httpBase + "/automations") else { return }
        let files = (Bundle.main.urls(forResourcesWithExtension: "papai", subdirectory: "automates") ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard !files.isEmpty else { return }
        var added = 0
        for f in files {
            guard let body = try? Data(contentsOf: f) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let (_, r) = try? await URLSession.shared.upload(for: req, from: body),
               (r as? HTTPURLResponse)?.statusCode == 200 { added += 1 }
        }
        guard added > 0 else { return }
        UserDefaults.standard.set(true, forKey: flag)
        if let (data, _) = try? await URLSession.shared.data(from: URL(string: httpBase + "/lessons")!),
           let list = try? JSONDecoder().decode([Lesson].self, from: data) {
            lessons = list
        }
    }

    func refreshRequests() async {
        guard ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil else { return }
        requestsLoading = true
        requestsError = false
        defer { requestsLoading = false }
        guard let url = URL(string: httpBase + "/requests") else {
            requests = []; requestsError = true
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            requests = try JSONDecoder().decode(UserRequestsResponse.self, from: data).requests
        } catch {
            requests = []
            requestsError = true
        }
    }

    func relaunchRequest(_ request: UserRequest) {
        guard let id = request.relaunchID(availableIDs: Set(lessons.map(\.id))),
              let lesson = lessons.first(where: { $0.id == id }) else { return }
        showRequests = false
        runAutomation(lesson)
    }

    // MARK: Fenêtre

    func applyLevel() {
        narration.context(assistance: sessionOpen,
                          speakingAllowed: connected && state == .active && !paused && guardAlert == nil)
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
        holoActing = (state == .active || (state == .awaiting_helper && !questionForMe)) && !paused && !gate.isStopped
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

    /// Pause ou reprise, depuis l'écran de l’utilisateur.
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

    /// Réponse de l’utilisateur à une question de Holo qui lui est posée.
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
            let ticket = pendingAutomationTicket
            pendingAutomationTicket = nil
            pendingTask = ""
            screen = .home
            runAutomation(a, ticket: ticket)
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
        pendingAutomationTicket = nil
        screen = .home
    }

    /// Déjà réglée mais le problème est revenu : le même ticket est rouvert.
    func retryExisting() {
        guard let e = existing, e.solved else { return }
        existing = nil
        askHelp(task: e.asked.isEmpty ? e.task : e.asked, reopen: e.ticket)
    }

    /// Ce n'est pas la même demande : elle part avec son propre ticket.
    func newRequest() {
        guard let e = existing else { return }
        existing = nil
        askHelp(task: e.asked.isEmpty ? e.task : e.asked, new: true)
    }

    func askHelp(task: String, requestedBy: String? = nil, ticket: String? = nil,
                 reopen: String? = nil, new: Bool = false) {
        guard guardAlert == nil else { return }
        existing = nil
        // « Range mes documents » : seuls les noms des fichiers partent, avec la demande.
        tidyScan = nil
        if Tidy.isRequest(task) {
            guard let folder = Tidy.folder(in: task) ?? chooseTidyFolder() else { return }
            do {
                tidyScan = try Tidy.scan(folder, home: FileManager.default.homeDirectoryForCurrentUser)
            } catch {
                showNotice(error.localizedDescription)
                return
            }
        }
        queuedShown = false
        if let ticket, queued?.ticket == ticket { queued = nil }
        gate.reset()
        planApproved = false
        executionState = nil
        stoppedBy = nil
        sessionWhere = nil
        guardAcknowledged = false
        homeTimer?.cancel()
        self.task = task
        pendingTask = ""
        plan = []; planStep = nil; question = nil; answer = nil; answerSources = []; currentAction = nil; actions = []
        sessionHelper = nil
        automationRun = nil
        AppUsage.shared.noteRequest(task)
        webFronted = false
        state = .planning
        screen = .session
        applyLevel()
        var msg: [String: Any] = ["type": "help_request", "task": task]
        if let requestedBy { msg["requested_by"] = requestedBy }
        if let ticket { msg["ticket"] = ticket }
        if let tidyScan { msg["tidy"] = tidyScan.payload }
        if let reopen { msg["reopen"] = reopen }
        if new { msg["new"] = true }
        client.send(msg)
    }

    private func chooseTidyFolder() -> TidyFolder? {
        let alert = NSAlert()
        alert.messageText = "Quel dossier ranger ?"
        alert.informativeText = "Holo ne lit que les noms des fichiers, jamais leur contenu. \(helperName) validera le rangement, et vous pourrez l'annuler."
        for f in TidyFolder.allCases { alert.addButton(withTitle: f.label) }
        alert.addButton(withTitle: "Annuler")
        let i = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return TidyFolder.allCases.indices.contains(i) ? TidyFolder.allCases[i] : nil
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
        automationRun = nil
        screen = .home
        state = nil
        planApproved = false
        executionState = nil
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
        case "tidy_execute":
            guard let req = m["req"] as? String else { return }
            doTidy(req, m)
        case "status":
            applyStatus(m)
        case "session":
            if m["automation"] as? String != nil, automationRun != nil {
                automationRun?.ticket = m["ticket"] as? String
                automationRun?.number = m["number"] as? Int
            }
        case "automation_ticket":
            automationRun?.ticket = m["ticket"] as? String
            automationRun?.number = m["number"] as? Int
        case "support_requested":
            automationRun?.asked = true
            showNotice("C'est envoyé à \(helperName), avec l'étape où l'automate s'est arrêté.")
        case "web_agent_start":
            webHost.updateSites(m["sites"] as? [String] ?? [], hosts: m["hosts"] as? [String] ?? [])
            if sessionOpen && !gate.isStopped { webHost.start() }
        case "web_sites":
            webHost.updateSites(m["sites"] as? [String] ?? [], hosts: m["hosts"] as? [String] ?? [])
        case "web_agent_stop":
            webHost.stopLocal(notifyServer: false)
        case "linkup_answer":
            answer = m["content"] as? String
            answerSources = m["sources"] as? [[String: String]] ?? []
        case "answer":
            answer = m["content"] as? String
            answerSources = []
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
            if !helpers.isEmpty {
                UserDefaults.standard.set(helpers.map { ["id": $0.id, "name": $0.name, "relation": $0.relation] },
                                          forKey: Self.helpersKey)
            } else if !Self.cachedHelpers().isEmpty {
                sendProfile()
            }
        case "tickets_changed":
            if showRequests { Task { await refreshRequests() } }
        case "lessons_changed":
            Task {
                await refreshLessons()
                if let t = m["title"] as? String { showNotice("Nouvel automate : « \(t) »") }
            }
        case "guard_rules":
            GuardSignals.rules = m
        case "alert":
            narration.context(assistance: sessionOpen, speakingAllowed: false)
            // Le gardien a reconnu une situation : le support est prévenu en même temps.
            // Un avertissement (`blocked:false`) n'arrête ni l'assistance ni un automate.
            if (m["blocked"] as? Bool) ?? true {
                webHost.stopLocal()
                gate.raise()
            }
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
            // Poste d'entreprise : le support vient de l'organisation, aucune liaison manuelle.
            // Quelqu'un qui tape un code de liaison est refusé sans rien afficher.
            guard let req = (m["req"] as? String) ?? (m["req"] as? Int).map(String.init) else { return }
            client.send(["type": "pair_decision", "req": req, "accept": false])
        case "ticket_queued":
            // Aucun support disponible : la demande attend, retour à l'accueil.
            let suggestions = (m["suggestions"] as? [[String: Any]] ?? []).compactMap { suggestion -> QueuedSuggestion? in
                guard let id = suggestion["id"] as? String, let title = suggestion["title"] as? String else { return nil }
                return QueuedSuggestion(id: id, title: title)
            }
            queued = QueuedTicket(ticket: m["ticket"] as? String ?? "", number: m["number"] as? Int ?? 0,
                                  task: m["task"] as? String ?? task, rdv: nil, suggestions: suggestions,
                                  suggestionLancee: m["suggestion_lancee"] as? String)
            queuedShown = true
            state = nil
            screen = .home
            applyLevel()
        case "ticket_exists", "ticket_solved":
            // La demande a déjà son ticket : rien de nouveau n'est ouvert.
            let sol = m["solution"] as? [String: Any] ?? [:]
            existing = ExistingTicket(
                solved: m["type"] as? String == "ticket_solved",
                ticket: m["ticket"] as? String ?? "", number: m["number"] as? Int ?? 0,
                task: m["task"] as? String ?? task, asked: task,
                status: m["status"] as? String ?? "",
                rdv: (m["rdv"] as? Double).map { Date(timeIntervalSince1970: $0) },
                note: sol["note"] as? String ?? "", by: sol["by"] as? String ?? "",
                at: (sol["at"] as? Double).map { Date(timeIntervalSince1970: $0) },
                steps: sol["steps"] as? [String] ?? [])
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
        planApproved = m["plan_approved"] as? Bool ?? false
        executionState = m["state"] as? String
        stoppedBy = m["stopped_by"] as? String
        sessionWhere = m["where"] as? String
        if let b = m["blocked"] as? [String: Any], automationRun != nil {
            automationRun?.step = b["step"] as? Int
            automationRun?.reason = b["reason"] as? String
        }
        if let asked = m["support_requested"] as? Bool, asked { automationRun?.asked = true }
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
        func reply(_ text: String, refused: Bool, blocked: String? = nil) {
            var message: [String: Any] = ["type": "result", "req": req, "result": text, "refused": refused]
            if let blocked { message["blocked"] = blocked }
            client.send(message)
        }
        if gate.isStopped || guardAlert != nil { reply("Assistance arrêtée ou alerte du gardien en attente.", refused: true); return }
        guard planApproved && ["active", "awaiting_helper"].contains(executionState ?? "") else {
            reply("Action refusée : aucun plan validé par le support.", refused: true)
            return
        }
        let said = describeAction(name, args)
        currentAction = said
        if actions.last != said { actions.append(said) }
        do {
            let r = try await Actuator.run(name: name, args: args, gate: gate, protected: protectedRect())
            reply(r, refused: false)
        } catch ActionError.stopped {
            reply("Arrêt demandé par l’utilisateur.", refused: true)
        } catch ActionError.protectedZone {
            reply("Action refusée par PapAI : cette zone appartient à PapAI. Ne réessaie pas : appelle ask_helper pour que le support s'en occupe.", refused: false, blocked: "sensitive")
        } catch ActionError.sensitive(let reason) {
            reply("Action refusée par PapAI : \(reason). Ne réessaie pas : appelle ask_helper pour que le support s'en occupe.", refused: false, blocked: "sensitive")
        } catch ActionError.noAccessibility {
            reply("Autorisation Accessibilité manquante sur cet ordinateur.", refused: true)
        } catch ActionError.unknownKey(let k) {
            reply("Touche inconnue : \(k)", refused: false)
        } catch {
            reply("échec : \(error.localizedDescription)", refused: true)
        }
    }

    /// Plan de rangement validé par le support : les garde-fous de `Tidy` revérifient tout.
    private func doTidy(_ req: String, _ m: [String: Any]) {
        func reply(_ text: String, refused: Bool, _ r: TidyResult = TidyResult()) {
            client.send(["type": "result", "req": req, "result": text, "refused": refused,
                         "moved": r.moved, "renamed": r.renamed, "skipped": r.skipped])
        }
        if gate.isStopped || guardAlert != nil { reply("Assistance arrêtée ou alerte du gardien en attente.", refused: true); return }
        guard planApproved && executionState == "active" else {
            reply("Rangement refusé : aucun plan validé par le support.", refused: true)
            return
        }
        guard let scan = tidyScan, (m["folder"] as? String) == scan.folder.rawValue else {
            reply("Rangement refusé : ce dossier n'a pas été demandé sur cet ordinateur.", refused: true)
            return
        }
        let moves = ((m["moves"] as? [[String: Any]]) ?? []).compactMap { d -> TidyMove? in
            guard let from = d["from"] as? String, let to = d["to"] as? String else { return nil }
            return TidyMove(from: from, to: to)
        }
        currentAction = "Holo range vos fichiers dans \(scan.folder.label)"
        actions.append(currentAction ?? "")
        let stop = gate.pin()
        do {
            let r = try Tidy.execute(scan.folder, moves: moves, allowed: Set(scan.files),
                                     home: FileManager.default.homeDirectoryForCurrentUser,
                                     journal: .standard, shouldStop: { stop.isStopped })
            lastTidy = TidyJournal.standard.last
            tidyScan = nil
            reply(r.text, refused: r.stopped, r)
        } catch {
            reply(error.localizedDescription, refused: true)
        }
    }

    func undoTidy() {
        do {
            let r = try Tidy.undo(home: FileManager.default.homeDirectoryForCurrentUser, journal: .standard)
            var text = "Rangement annulé : \(r.restored) fichier\(r.restored > 1 ? "s" : "") remis à leur place."
            if r.renamed > 0 { text += " \(r.renamed) renommé\(r.renamed > 1 ? "s" : "") avec « (2) », la place étant prise." }
            if r.missing > 0 { text += " \(r.missing) introuvable\(r.missing > 1 ? "s" : "") (déplacé\(r.missing > 1 ? "s" : "") depuis)." }
            showNotice(text)
        } catch {
            showNotice(error.localizedDescription)
        }
        lastTidy = TidyJournal.standard.last
    }

    // MARK: Automates

    func runShortcut(_ l: Lesson) {
        if !(l.actions ?? []).isEmpty { runAutomation(l); return }
        guard let sc = l.shortcut else { openLesson(l); return }
        Task {
            let r = await Shortcuts.open(sc)
            if r.ok {
                showRunStatus(l.id, "C'est ouvert")
            } else {
                automationStopped(l, step: 1, detail: r.detail)
            }
        }
    }

    /// Un automate importé par un support, lancé en un clic. Pas de
    /// validation à chaque fois : le support l'a validé à l'import.
    func runSuggestedAutomation(_ suggestion: QueuedSuggestion, ticket: String) {
        guard queued?.ticket == ticket,
              queued?.suggestions.contains(where: { $0.id == suggestion.id }) == true,
              let lesson = lessons.first(where: { $0.id == suggestion.id }) else { return }
        queuedShown = false
        runAutomation(lesson, ticket: ticket)
    }

    func runAutomation(_ l: Lesson, ticket: String? = nil) {
        var launchTicket = ticket
        if let ticket, (queued?.ticket != ticket
                        || !(queued?.suggestions.contains(where: { $0.id == l.id }) ?? false)) {
            launchTicket = nil
        }
        let acts = l.actions ?? []
        if let p = l.platforms, !p.contains("mac") {
            showNotice("Cet automate est prévu pour un autre ordinateur.")
            return
        }
        // Ni accord ni support en direct : l'automate a été validé par le support à sa création.
        let holo = acts.first { $0.kind == "holo" }
        // Un automate tourne directement chez l'utilisateur, sans écran d'accord :
        // il a été validé par le support. Seule une demande d'assistance passe par un ticket.
        _ = holo
        if let launchTicket {
            client.send(["type": "ticket_automate_launched", "ticket": launchTicket, "lesson": l.id])
            if queued?.ticket == launchTicket { queued?.suggestionLancee = l.id }
        }
        gate.reset()
        automationRun = nil
        showRunStatus(l.id, "En cours…", enCours: true)
        Task {
            let r = await Automations.play(l, base: httpBase, gate: gate)
            if gate.isStopped { showRunStatus(l.id, "Arrêté"); return }
            guard r.ok else {
                automationStopped(l, step: r.step, detail: r.detail)
                return
            }
            guard let holo else {
                showRunStatus(l.id, "C'est fait")
                if !r.detail.isEmpty { showNotice(r.detail) }
                return
            }
            runStatus = nil
            homeTimer?.cancel()
            automationRun = AutomationRun(id: l.id, title: l.title)
            task = holo.goal ?? l.title
            plan = []; planStep = nil; question = nil; answer = nil; answerSources = []; currentAction = nil; actions = []
            sessionHelper = nil
            state = .planning
            screen = .session
            applyLevel()
            client.send(["type": "run_automation", "id": l.id])
        }
    }

    /// Une action locale a échoué : on s'arrête là, sans rien tenter d'autre et sans
    /// appeler personne. Le serveur ouvre un ticket qui garde l'étape.
    private func automationStopped(_ l: Lesson, step: Int, detail: String) {
        runStatus = nil
        automationRun = AutomationRun(id: l.id, title: l.title, step: step, reason: detail, local: true,
                                      unsent: !connected)
        showNotice("« \(l.title) » s'est arrêté à l'étape \(step)\(detail.isEmpty ? "" : " : \(detail)").")
        client.send(["type": "automation_failed", "id": l.id, "step": step, "title": l.title, "detail": detail])
    }

    /// Bouton discret, en haut à droite : seule façon de faire venir le support sur un automate.
    func askAutomationSupport() {
        guard canAskAutomationSupport, let t = automationRun?.ticket else { return }
        client.send(["type": "support_request", "ticket": t])
    }

    func openLesson(_ l: Lesson) {
        lesson = l
        screen = .lesson
    }

    func showRunStatus(_ id: String, _ text: String, enCours: Bool = false) {
        runStatus = RunStatus(id: id, text: text, enCours: enCours)
        runStatusTask?.cancel()
        guard !enCours else { return }
        runStatusTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { runStatus = nil }
        }
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
