import AppKit
import Observation
import SwiftUI

enum AppScreen { case home, consent, session, lesson }

struct Helper: Identifiable, Equatable {
    var id: String
    var name: String
    var relation: String
}

struct RemoteRequest: Equatable {
    var from: String
    var task: String
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
    var task = ""
    var plan: [String] = []
    /// Étape du plan validé que Holo exécute (à partir de 1). Absente d'un ancien serveur.
    var planStep: Int?
    var question: String?
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
    var onboarded = UserDefaults.standard.bool(forKey: "onboarded")
    /// Dans le modèle et non dans la vue : changer la taille du texte recrée
    /// toute la fenêtre (`.id(textScale)`), l'accueil doit garder son étape.
    var onboardingStep = 0
    var textScale = TextScale.current
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
    var showHelpers = false
    var pendingTask = ""
    var actions: [String] = []
    var guardAlert: GuardAlert?

    @ObservationIgnored let gate = StopGate()
    @ObservationIgnored let client = BridgeClient()
    @ObservationIgnored weak var window: NSWindow? { didSet { applyLevel() } }
    @ObservationIgnored private var started = false
    @ObservationIgnored private var autoSent = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var homeTimer: Task<Void, Never>?

    var sessionOpen: Bool { state?.isOpen ?? false }
    var serverURL: String {
        let stored = UserDefaults.standard.string(forKey: "server")?.trimmingCharacters(in: .whitespaces) ?? ""
        if !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["PAPAI_SERVER"], !env.isEmpty { return env }
        return "ws://localhost:8000/ws/bridge"
    }
    var httpBase: String {
        var s = serverURL
        s = s.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
        if s.hasSuffix("/ws/bridge") { s.removeLast("/ws/bridge".count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    var firstName: String {
        let n = UserDefaults.standard.string(forKey: "firstName")?.trimmingCharacters(in: .whitespaces) ?? ""
        return n
    }

    /// Qui aide : toujours au singulier pour accorder le verbe qui suit.
    var helperName: String {
        switch helpers.count {
        case 0: "votre proche"
        case 1: helpers[0].name
        case 2: "\(helpers[0].name) ou \(helpers[1].name)"
        default: "l'un de vos proches"
        }
    }
    var HelperName: String {
        let n = helperName
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    // MARK: Accueil et proches

    func setFirstName(_ name: String) {
        UserDefaults.standard.set(name.trimmingCharacters(in: .whitespaces), forKey: "firstName")
        sendProfile()
    }

    /// Le prénom réellement saisi (sans la valeur d'exemple), transmis au serveur
    /// pour que l'aidant lise « Vous allez aider Sophie » et non un nom figé.
    func sendProfile() {
        let n = UserDefaults.standard.string(forKey: "firstName")?.trimmingCharacters(in: .whitespaces) ?? ""
        if !n.isEmpty { client.send(["type": "profile", "name": n]) }
    }

    func setTextScale(_ v: Double) {
        TextScale.current = v
        textScale = v
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        onboarded = true
        permissionsDismissed = true
        stopPairing()
    }

    func startPairing(long: Bool = false) {
        pairAdded = nil
        client.send(long ? ["type": "pair_start", "long": true] : ["type": "pair_start"])
    }

    /// Le texte de l'invitation envoyée au proche, avec le lien d'appairage.
    var invitationText: String {
        let n = UserDefaults.standard.string(forKey: "firstName")?.trimmingCharacters(in: .whitespaces) ?? ""
        let who = n.isEmpty ? "Votre proche" : n
        return "\(who) aimerait que vous l'aidiez sur son ordinateur avec PapAI. Ouvrez ce lien sur votre téléphone pour vous relier (valable 24 heures) :"
    }

    func stopPairing() {
        pairCode = nil
        pairURL = nil
        pairAppURL = nil
        pairLong = false
    }

    /// `papai://pair?u=<url encodée>` : l'appareil photo de l'iPhone ouvre l'app, pas Safari.
    static func appPairingURL(_ url: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return "papai://pair?u=" + (url.addingPercentEncoding(withAllowedCharacters: allowed) ?? url)
    }

    func removeHelper(_ h: Helper) {
        client.send(["type": "remove_helper", "id": h.id])
    }

    /// Le proche propose une session : rien ne démarre sans ce clic.
    func acceptRemote() {
        guard let r = remoteRequest else { return }
        remoteRequest = nil
        let task = r.task.isEmpty ? "\(r.from) propose de m'aider sur l'ordinateur" : r.task
        askHelp(task: task, requestedBy: r.from)
    }

    func refuseRemote() {
        remoteRequest = nil
        client.send(["type": "remote_answer", "accepted": false])
    }

    // MARK: Démarrage

    func start() {
        guard !started else { return }
        started = true
        client.onMessage = { [weak self] m in self?.handle(m) }
        client.onConnection = { [weak self] ok in
            guard let self else { return }
            self.connected = ok
            if ok { self.sendProfile() }
            // Test : PAPAI_AUTOTASK lance une demande dès la connexion.
            if ok, !self.autoSent, let t = ProcessInfo.processInfo.environment["PAPAI_AUTOTASK"], !t.isEmpty {
                self.autoSent = true
                self.askHelp(task: t)
            }
        }
        reconnect()
        Task { await refreshLessons() }
        Task {
            while true {
                screenOK = Permissions.screenOK
                axOK = Permissions.accessibilityOK
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        if ProcessInfo.processInfo.environment["PAPAI_DEMO"] == nil {
            Task {
                while true {
                    try? await Task.sleep(nanoseconds: GuardSignals.period)
                    if connected { client.send(GuardSignals.collect(withURL: !sessionOpen)) }
                }
            }
        }
        // Mode capture d'écran : PAPAI_DEMO=awaiting_approval etc.
        if let demo = ProcessInfo.processInfo.environment["PAPAI_DEMO"] {
            permissionsDismissed = true
            connected = true
            if demo.hasPrefix("onboarding") { onboarded = false; return }
            onboarded = true
            helpers = [Helper(id: "1", name: "Claire", relation: "sa fille")]
            if demo == "remote" {
                remoteRequest = RemoteRequest(from: "Claire", task: "Mettre à jour votre ordinateur")
                return
            }
            let json = #"[{"id":"a","title":"Mes photos de Noël","shortcut":{"folder":"pictures"},"steps":[{"instruction":"Ouvrez le Finder"}]},{"id":"b","title":"Mes documents","shortcut":{"folder":"documents"}}]"#
            lessons = (try? JSONDecoder().decode([Lesson].self, from: Data(json.utf8))) ?? []
            if demo == "home" { return }
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
        guard let url = URL(string: serverURL) else { return }
        client.start(url: url)
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
        window?.level = sessionOpen ? .floating : .normal
    }

    /// Cadre de la fenêtre PapAI, en points écran, origine en haut à gauche.
    func protectedRect() -> CGRect? {
        guard let w = window, w.isVisible, !w.isMiniaturized else { return nil }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let f = w.frame
        return CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height).insetBy(dx: -4, dy: -4)
    }

    // MARK: Demande d'aide

    /// Étape 4 : la première fois, un écran qui dit ce qui va se passer.
    /// Ensuite la demande part directement : l'accord est déjà donné.
    func requestConsent(task: String) {
        if screenConsent { askHelp(task: task); return }
        pendingTask = task
        screen = .consent
    }

    func giveConsent() {
        UserDefaults.standard.set(true, forKey: "screenConsent")
        screenConsent = true
        askHelp(task: pendingTask)
    }

    func revokeConsent() {
        UserDefaults.standard.set(false, forKey: "screenConsent")
        screenConsent = false
    }

    func cancelConsent() {
        pendingTask = ""
        screen = .home
    }

    func askHelp(task: String, requestedBy: String? = nil) {
        gate.reset()
        homeTimer?.cancel()
        self.task = task
        pendingTask = ""
        plan = []; planStep = nil; question = nil; answer = nil; currentAction = nil; actions = []
        state = .planning
        screen = .session
        applyLevel()
        var msg: [String: Any] = ["type": "help_request", "task": task]
        if let requestedBy { msg["requested_by"] = requestedBy }
        client.send(msg)
    }

    /// Le verrou local passe d'abord, puis le serveur est prévenu.
    func stop() {
        gate.raise()
        client.send(["type": "stop"])
        state = .stopped
        currentAction = nil
        applyLevel()
    }

    func backHome() {
        homeTimer?.cancel()
        screen = .home
        state = nil
        applyLevel()
    }

    // MARK: Messages du serveur

    private func handle(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "capture":
            guard let req = m["req"] as? String else { return }
            Task { await doCapture(req) }
        case "execute":
            guard let req = m["req"] as? String, let action = m["action"] as? [String: Any] else { return }
            Task { await doExecute(req, action) }
        case "status":
            applyStatus(m)
        case "answer":
            answer = m["content"] as? String
        case "helpers":
            let list = (m["helpers"] as? [[String: Any]]) ?? []
            helpers = list.compactMap { d in
                guard let id = d["id"] as? String, let n = d["name"] as? String else { return nil }
                return Helper(id: id, name: n, relation: d["relation"] as? String ?? "")
            }
            if let added = m["added"] as? String {
                pairAdded = added
                stopPairing()
            }
        case "lessons_changed":
            Task {
                await refreshLessons()
                if let t = m["title"] as? String { showNotice("Nouveau tutoriel : « \(t) »") }
            }
        case "pair_code":
            pairCode = m["code"] as? String
            pairURL = m["url"] as? String
            pairAppURL = m["app_url"] as? String ?? pairURL.map(Self.appPairingURL)
            pairLong = m["long"] as? Bool ?? false
            pairExpires = m["expires_in"] as? Int ?? 600
        case "alert":
            // Le gardien a reconnu une situation : le proche est prévenu en même temps.
            guardAlert = GuardAlert(level: m["level"] as? String ?? "attention",
                                    title: m["title"] as? String ?? "",
                                    detail: m["detail"] as? String ?? "")
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        case "remote_request":
            guard !sessionOpen else { return }
            remoteRequest = RemoteRequest(from: m["from"] as? String ?? "Votre proche",
                                          task: m["task"] as? String ?? "")
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        default:
            break
        }
    }

    private func applyStatus(_ m: [String: Any]) {
        guard screen == .session else { return }
        if gate.isStopped { state = .stopped; applyLevel(); return }
        let before = state
        if let s = (m["state"] as? String).flatMap(SessionState.init(rawValue:)) { state = s }
        if state == .done, before != .done { scheduleHome() }
        if let t = m["task"] as? String, !t.isEmpty { task = t }
        plan = (m["plan"] as? [String]) ?? []
        planStep = m["plan_step"] as? Int
        question = (m["question"] as? [String: Any])?["question"] as? String
        if state != .active { currentAction = nil }
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
        if gate.isStopped { reply("Arrêt demandé par la personne aidée.", refused: true); return }
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

    // MARK: Automatismes

    func runShortcut(_ l: Lesson) {
        guard let sc = l.shortcut else { openLesson(l); return }
        let r = Shortcuts.open(sc)
        if r.ok {
            showNotice("C'est ouvert.")
        } else {
            showNotice("Je ne retrouve pas ce dossier. \(HelperName) a reçu un message pour s'en occuper.")
            client.send(["type": "automation_failed", "title": l.title, "detail": r.detail])
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
