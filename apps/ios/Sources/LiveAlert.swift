import ActivityKit
import AVFoundation
import Foundation
import os

/// Tient la grande alerte de l'écran verrouillé (Live Activity) à jour.
///
/// - Une Live Activity ne peut démarrer qu'avec l'app au premier plan : on la
///   lance dès que l'iPhone est lié à un proche, en mode « veille ».
/// - Quand le proche demande de l'aide, on la met à jour avec une alerte :
///   l'écran s'allume, la carte passe en grand et en sombre, avec un son.
/// - Pour recevoir la demande l'écran éteint sans serveur de push, l'app reste
///   éveillée en arrière-plan grâce à un son muet (`KeepAwake`). C'est un choix de
///   démo : en production, ce serait une notification push (APNs).
@MainActor
final class LiveAlert {
    static let shared = LiveAlert()
    private let log = Logger(subsystem: "com.quentin.papai.aidant", category: "live")

    private var activity: Activity<HelpActivityAttributes>?
    private var last: HelpActivityAttributes.ContentState?

    var isRunning: Bool { activity?.activityState == .active }

    /// À appeler à chaque changement d'état reçu du serveur.
    func update(senior: String, state: String?, task: String, question: String?,
                step: Int?, steps: Int, paused: Bool, linked: Bool) {
        guard linked else { end(); KeepAwake.shared.stop(); return }
        KeepAwake.shared.start()

        let phase: HelpActivityAttributes.ContentState.Phase
        switch state {
        case "planning": phase = .planning
        case "awaiting_approval": phase = .request
        case "awaiting_helper": phase = .needsYou
        case "active": phase = paused ? .paused : .working
        case "done": phase = .done
        default: phase = .watching
        }
        let keepTask = phase != .watching
        var next = HelpActivityAttributes.ContentState(
            phase: phase, senior: senior, task: keepTask ? task : "", detail: question ?? "",
            step: step ?? 0, steps: steps, since: Date())
        if let l = last, l.phase == phase { next.since = l.since }
        guard next != last else { return }
        let changed = last?.phase != phase
        last = next

        let content = ActivityContent(state: next, staleDate: nil, relevanceScore: next.urgent ? 100 : 10)
        if let a = activity, a.activityState == .active {
            let alert: AlertConfiguration? = changed && (next.urgent || phase == .done)
                ? AlertConfiguration(title: "\(next.headline)", body: "\(next.subline)", sound: .default)
                : nil
            Task { await a.update(content, alertConfiguration: alert) }
        } else {
            begin(content)
        }
    }

    /// Relance la carte si elle a disparu (fermée par l'utilisateur, ou limite de 8 h).
    /// Seulement possible au premier plan.
    func resume() {
        guard let l = last, !isRunning else { return }
        begin(ActivityContent(state: l, staleDate: nil, relevanceScore: l.urgent ? 100 : 10))
    }

    private func begin(_ content: ActivityContent<HelpActivityAttributes.ContentState>) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("Live Activities désactivées dans les réglages")
            return
        }
        // Une seule carte à la fois, même après un relancement de l'app.
        for a in Activity<HelpActivityAttributes>.activities where a.id != activity?.id {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            activity = try Activity.request(attributes: HelpActivityAttributes(), content: content)
            log.info("carte de l'écran verrouillé lancée")
        } catch {
            // Hors premier plan, iOS refuse : on réessaiera au retour dans l'app.
            log.error("carte non lancée : \(error.localizedDescription, privacy: .public)")
        }
    }

    func end() {
        last = nil
        for a in Activity<HelpActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }
}

/// Garde l'app éveillée écran éteint en jouant du silence, mélangé aux autres sons.
@MainActor
final class KeepAwake {
    static let shared = KeepAwake()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observer: NSObjectProtocol?

    func start() {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
        buffer.frameLength = buffer.frameCapacity   // déjà rempli de zéros : silence
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        do { try engine.start() } catch { return }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        self.engine = engine; self.player = player
        // Un appel ou une autre app coupe le son : on repart après.
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended { Task { @MainActor in self?.restart() } }
        }
    }

    func restart() { stop(); start() }

    func stop() {
        player?.stop(); engine?.stop()
        player = nil; engine = nil
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
    }
}
