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
    var id: String { title }
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
    var pairDone = false

    // Session
    var state: String?
    var task = ""
    var plan: [String] = []
    /// Étape du plan validé que Holo exécute (à partir de 1). Absente d'un ancien serveur.
    var planStep: Int?
    var question: (text: String, options: [String])?
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
    var lastAlert: (title: String, detail: String)?

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
        // `-serverURL …` et `-helperKey …` au lancement (dépannage, démo) : on les garde.
        let args = ProcessInfo.processInfo.arguments
        for k in ["serverURL", "helperKey"] {
            if let i = args.firstIndex(of: "-" + k), i + 1 < args.count {
                let v = args[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { UserDefaults.standard.set(v, forKey: k) }
            }
        }
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        helperKey = UserDefaults.standard.string(forKey: "helperKey") ?? ""
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
    func applySettings(server: String, key: String) {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !k.isEmpty else { return }
        serverURL = s; helperKey = k
        UserDefaults.standard.set(s, forKey: "serverURL")
        UserDefaults.standard.set(k, forKey: "helperKey")
        reconnect()
    }

    func start() {
        guard runTask == nil, isConfigured else { return }
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
            connected = false; socket = nil
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
    /// Dans une phrase : « Tout va bien chez Sophie », sinon « chez votre proche ».
    var senior: String { seniorName.isEmpty ? "votre proche" : seniorName }
    /// En début de phrase : « Sophie a besoin de vous », sinon « Votre proche… ».
    var seniorTitle: String { seniorName.isEmpty ? "Votre proche" : seniorName }

    func setSenior(_ name: String?) {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != seniorName else { return }
        seniorName = n
        UserDefaults.standard.set(n, forKey: "seniorName")
    }

    func open(url: URL) {
        if let n = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "n" })?.value { setSenior(n) }
        guard let link = PairLink.parse(url.absoluteString) else { showToast("Lien PapAI non reconnu."); return }
        openPair(link)
    }

    func openPair(_ link: PairLink) {
        pairDone = false; pairError = nil; pairBusy = false
        sheet = .pair(link)
    }

    /// Saisie du code à la main : il faut déjà connaître le serveur.
    func manualPairLink() -> PairLink? {
        let s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : PairLink(base: baseHTTP, code: nil)
    }

    /// POST du prénom et du lien, puis réglage de l'app avec la réponse du serveur.
    func submitPair(_ link: PairLink, code: String?, name: String, relation: String) async {
        let c = (link.code ?? code ?? "").filter(\.isNumber)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.count == 6 else { pairError = "Le code fait 6 chiffres."; return }
        guard !n.isEmpty else { pairError = "Indiquez votre prénom."; return }
        guard let url = URL(string: link.base + "/p/" + c) else { pairError = "Adresse invalide."; return }
        pairBusy = true; pairError = nil
        defer { pairBusy = false }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": n, "relation": relation])
        do {
            let (d, _) = try await URLSession.shared.data(for: req)
            let r = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
            guard r["ok"] as? Bool == true else {
                pairError = r["error"] as? String ?? "Le serveur a refusé l’appairage."
                return
            }
            guard let key = r["key"] as? String, !key.isEmpty else {
                pairError = "Le serveur n’a pas renvoyé de clé : réglez la connexion à la main."
                return
            }
            var server = (r["server"] as? String) ?? link.origin
            while server.hasSuffix("/") { server.removeLast() }
            setSenior(r["senior"] as? String)
            helperName = r["name"] as? String ?? n
            UserDefaults.standard.set(helperName, forKey: "helperName")
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

        case "senior":
            setSenior(m["name"] as? String)

        case "status":
            let newState = m["state"] as? String
            let sid = "\(m["session"] ?? "")"
            if sid != sessionId {
                sessionId = sid; requestStart = Date(); iRefusedPlan = false
                doneAnswer = nil; hasDraft = false; savedTitle = nil; lessonBusy = false
                pausing = false; doneFresh = false
            }
            if newState != state {
                if newState == "awaiting_approval" || newState == "awaiting_helper" { notify(newState!) }
                if newState == "done" { doneFresh = true; Task { await loadLessons() } }
                if newState == "active" { pausing = false; planBusy = false }
                if newState != "awaiting_helper" { aiming = false; target = nil; sending = false }
                if newState == "awaiting_approval" { planBusy = false }
            }
            state = newState
            task = m["task"] as? String ?? task
            plan = m["plan"] as? [String] ?? []
            planStep = m["plan_step"] as? Int
            if let q = m["question"] as? [String: Any], let t = q["question"] as? String {
                question = (t, q["options"] as? [String] ?? [])
            } else if newState != "awaiting_helper" { question = nil }

        case "frame":
            if let b64 = m["png_b64"] as? String, let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
                frame = img; frameId = m["frame_id"] as? String; frameAt = Date()
                target = nil
            }

        case "question":
            if let t = m["question"] as? String { question = (t, m["options"] as? [String] ?? []) }

        case "answer":
            doneAnswer = m["content"] as? String

        case "alert":
            let t = m["title"] as? String ?? "Alerte", d = m["detail"] as? String ?? ""
            lastAlert = (t, d)
            notifyLocal(title: t, body: d)
            showToast(t)

        case "refused":
            showToast(m["reason"] as? String ?? "Refusé")
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

        default: break
        }
    }

    // MARK: Notifications

    private func notify(_ s: String) {
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
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: Actions

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
