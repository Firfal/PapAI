import AppKit
import Observation
import SwiftUI

enum AppScreen { case home, session, lesson }

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
    var question: String?
    var answer: String?
    var currentAction: String?
    var lessons: [Lesson] = []
    var notice: String?
    var lesson: Lesson?
    var screenOK = Permissions.screenOK
    var axOK = Permissions.accessibilityOK
    var permissionsDismissed = false
    var showSettings = false
    var captureError: String?

    @ObservationIgnored let gate = StopGate()
    @ObservationIgnored let client = BridgeClient()
    @ObservationIgnored weak var window: NSWindow? { didSet { applyLevel() } }
    @ObservationIgnored private var started = false
    @ObservationIgnored private var autoSent = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

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
        return n.isEmpty ? "Jeanne" : n
    }

    // MARK: Démarrage

    func start() {
        guard !started else { return }
        started = true
        client.onMessage = { [weak self] m in self?.handle(m) }
        client.onConnection = { [weak self] ok in
            guard let self else { return }
            self.connected = ok
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
        // Mode capture d'écran : PAPAI_DEMO=awaiting_approval etc.
        if let demo = ProcessInfo.processInfo.environment["PAPAI_DEMO"] {
            permissionsDismissed = true
            connected = true
            let json = #"[{"id":"a","title":"Mes photos de Noël","shortcut":{"folder":"pictures"},"steps":[{"instruction":"Ouvrez le Finder"}]},{"id":"b","title":"Mes documents","shortcut":{"folder":"documents"}}]"#
            lessons = (try? JSONDecoder().decode([Lesson].self, from: Data(json.utf8))) ?? []
            if demo == "home" { return }
            guard let s = SessionState(rawValue: demo) else { return }
            task = "Je ne retrouve plus mes photos de Noël"
            plan = ["Ouvrir le Finder", "Aller dans le dossier Images", "Ouvrir le dossier « Noël 2025 »"]
            answer = "Vos photos de Noël sont ouvertes dans le dossier Images."
            currentAction = "Clic sur l'icône du Finder"
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

    func askHelp(task: String) {
        gate.reset()
        self.task = task
        plan = []; question = nil; answer = nil; currentAction = nil
        state = .planning
        screen = .session
        applyLevel()
        client.send(["type": "help_request", "task": task])
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
        default:
            break
        }
    }

    private func applyStatus(_ m: [String: Any]) {
        guard screen == .session else { return }
        if gate.isStopped { state = .stopped; applyLevel(); return }
        if let s = (m["state"] as? String).flatMap(SessionState.init(rawValue:)) { state = s }
        if let t = m["task"] as? String, !t.isEmpty { task = t }
        plan = (m["plan"] as? [String]) ?? []
        question = (m["question"] as? [String: Any])?["question"] as? String
        if state != .active { currentAction = nil }
        applyLevel()
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
        currentAction = describeAction(name, args)
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
            showNotice("Je ne retrouve pas ce dossier. Quentin est prévenu, il va s'en occuper.")
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
