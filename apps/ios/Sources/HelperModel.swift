import SwiftUI
import UserNotifications

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

@MainActor @Observable
final class HelperModel {
    // Réglages mémorisés
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var helperKey: String = UserDefaults.standard.string(forKey: "helperKey") ?? ""

    // Connexion
    var connected = false

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
    var hasDraft = false
    var savedTitle: String?
    var lessons: [Lesson] = []

    var toast: String?
    var lastAlert: (title: String, detail: String)?

    private var socket: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    static let frameTTL: Double = 30

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

    func saveSettings() {
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(helperKey, forKey: "helperKey")
        reconnect()
    }

    func start() {
        guard runTask == nil, isConfigured else { return }
        runTask = Task { await run() }
        Task { await loadLessons() }
    }

    func reconnect() {
        runTask?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        runTask = nil; connected = false
        start()
    }

    private func run() async {
        var delay = 1.0
        while !Task.isCancelled {
            guard let url = wsURL else { return }
            let t = URLSession.shared.webSocketTask(with: url)
            t.maximumMessageSize = 32 * 1024 * 1024
            socket = t
            t.resume()
            do {
                // Le serveur envoie `hello` dès l'ouverture : le premier message vaut connexion.
                while true { let m = try await t.receive(); connected = true; delay = 1; handle(m) }
            } catch {}
            connected = false; socket = nil
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 8)   // backoff jusqu'à 8 s
        }
    }

    func send(_ o: [String: Any]) {
        guard let socket, connected, let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else { showToast("Pas de connexion au serveur."); return }
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
                showToast("Clic transmis à l’ordinateur de Jeanne.")
            } else if m["what"] as? String == "pause" { pausing = true }

        case "lesson_pending": lessonBusy = true

        case "lesson_draft":
            lessonBusy = false
            if let l = m["lesson"] as? [String: Any] {
                draftTitle = l["title"] as? String ?? ""
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
        let who = "Jeanne"
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
    func approveLesson() {
        let steps = draftSteps.map { ["instruction": $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines)] }
        send(["type": "approve_lesson", "lesson": ["title": draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), "steps": steps]])
    }
}
