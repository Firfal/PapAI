import AVFoundation
import Speech
import SwiftUI

/// Dictée de l'aidant (préciser le plan de Holo) : les mots s'écrivent en direct
/// dans le champ, sur l'iPhone. Un appui pour parler, un appui pour arrêter ;
/// l'écoute s'arrête aussi seule après 2 s sans nouveau mot.
@MainActor @Observable
final class VoiceInput {
    private(set) var listening = false
    var error: String?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastChange = Date()
    private var watch: Task<Void, Never>?

    func toggle(base: String, onText: @escaping (String) -> Void) {
        if listening { stop() } else { Task { await start(base: base, onText: onText) } }
    }

    private func start(base: String, onText: @escaping (String) -> Void) async {
        error = nil
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            error = "Autorisez le micro et la reconnaissance vocale dans Réglages > PapAI."
            return
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.isAvailable else {
            error = "La dictée n’est pas disponible pour le moment."
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch { self.error = "Je n’arrive pas à utiliser le micro."; return }

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }
        let prefix = base.isEmpty ? "" : base + " "
        task = rec.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { onText(prefix + text); self.lastChange = Date() }
                if final || err != nil { self.stop() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0); task?.cancel(); task = nil
            self.error = "Je n’arrive pas à utiliser le micro."
            return
        }
        self.engine = engine; self.request = req
        listening = true; lastChange = Date()
        watch = Task { [weak self] in
            while let self, self.listening, !Task.isCancelled {
                if Date().timeIntervalSince(self.lastChange) > 2.2 { self.stop(); break }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func stop() {
        guard listening else { return }
        listening = false
        watch?.cancel(); watch = nil
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        request?.endAudio(); request = nil
        task?.finish(); task = nil
        // Le son muet qui garde l'app éveillée reprend sa place.
        KeepAwake.shared.restart()
    }
}

/// Le bouton micro rond, à côté d'un champ de texte.
struct MicButton: View {
    let voice: VoiceInput
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: voice.listening ? "stop.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(voice.listening ? .white : Soin.ink)
                .frame(width: 52, height: 52)
                .background(voice.listening ? Soin.accent : Soin.card, in: Circle())
                .symbolEffect(.pulse, isActive: voice.listening)
        }
        .accessibilityLabel(voice.listening ? "Arrêter la dictée" : "Dicter")
    }
}
