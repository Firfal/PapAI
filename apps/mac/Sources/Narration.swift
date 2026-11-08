import AVFoundation
import Observation

struct NarrationQueue {
    var enabled = true { didSet { if !enabled { pending.removeAll() } } }
    var dictating = false { didSet { if dictating { pending.removeAll() } } }
    private(set) var assistance = false
    private var speakingAllowed = false
    private var seen: Set<String> = []
    private(set) var pending: [String] = []

    var canRead: Bool { enabled && !dictating && speakingAllowed && assistance }

    mutating func context(assistance: Bool, speakingAllowed: Bool) {
        if assistance && !self.assistance { seen.removeAll() }
        self.assistance = assistance
        self.speakingAllowed = speakingAllowed
        if !canRead { pending.removeAll() }
    }

    mutating func enqueue(_ phrase: String) {
        let text = phrase.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard assistance, !text.isEmpty, seen.insert(text).inserted, canRead else { return }
        pending.append(text)
    }

    mutating func next() -> String? {
        guard canRead, !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}

@MainActor @Observable
final class LocalNarration: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = LocalNarration()

    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "readAloud")
            queue.enabled = enabled
            reconcile()
        }
    }
    @ObservationIgnored private var queue = NarrationQueue()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var current: AVSpeechUtterance?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "readAloud") as? Bool ?? false  // coupée par défaut
        super.init()
        queue.enabled = enabled
        synthesizer.delegate = self
    }

    func context(assistance: Bool, speakingAllowed: Bool) {
        queue.context(assistance: assistance, speakingAllowed: speakingAllowed)
        reconcile()
    }

    func setDictating(_ active: Bool) {
        queue.dictating = active
        reconcile()
    }

    func say(_ phrase: String) {
        queue.enqueue(phrase)
        reconcile()
    }

    private func reconcile() {
        guard queue.canRead else {
            current = nil
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        guard current == nil,
              let voice = AVSpeechSynthesisVoice(language: AppLangue.anglais ? "en-US" : "fr-FR"),
              let text = queue.next() else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        current = utterance
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.current === utterance else { return }
            self.current = nil
            self.reconcile()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.current === utterance else { return }
            self.current = nil
            self.reconcile()
        }
    }
}
