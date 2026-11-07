import AVFoundation
import Speech
import SwiftUI

/// Dictée de la demande.
///
/// Un seul flux micro (AVAudioEngine) sert à trois choses à la fois :
/// - la transcription en direct sur le Mac (SFSpeechRecognizer) : les mots
///   s'affichent pendant que la personne parle ;
/// - la fin de phrase : quand les mots ne bougent plus, ou que le niveau
///   retombe au bruit de fond (`SilenceDetector`), la demande part seule ;
/// - un wav 16 kHz mono, transcrit par Gladia via le serveur pour le texte final.
/// Si Gladia ne répond pas, on garde le texte en direct du Mac.
@MainActor @Observable
final class Dictation {
    enum Phase: Equatable { case idle, listening, transcribing }

    private(set) var phase: Phase = .idle
    private(set) var level: CGFloat = 0
    /// Ce que la personne est en train de dire, mis à jour en direct.
    private(set) var live = ""
    var message: String?

    /// Les mots ne bougent plus depuis ce délai : la phrase est finie.
    private let wordsStill: TimeInterval = 1.6
    private let maxDuration: TimeInterval = 30

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var fileURL: URL?
    private var onText: ((String) -> Void)?
    private var onLive: ((String) -> Void)?
    private var base = ""
    private var detector = SilenceDetector()
    private var startedAt = Date()
    private var liveChangedAt: Date?
    private var watch: Task<Void, Never>?

    func toggle(httpBase: String, onLive: ((String) -> Void)? = nil, onText: @escaping (String) -> Void) {
        switch phase {
        case .idle: Task { await start(httpBase: httpBase, onLive: onLive, onText: onText) }
        case .listening: stop()
        case .transcribing: break
        }
    }

    // MARK: Écoute

    private func start(httpBase: String, onLive: ((String) -> Void)?, onText: @escaping (String) -> Void) async {
        message = nil
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            message = "Je n'ai pas accès au micro. Autorisez-le dans Réglages Système, Confidentialité."
            return
        }
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                            channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            message = "Je n'arrive pas à utiliser le micro pour le moment."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papai-dictee.wav")
        try? FileManager.default.removeItem(at: url)
        guard let file = try? AVAudioFile(forWriting: url, settings: outFormat.settings,
                                         commonFormat: .pcmFormatInt16, interleaved: true) else {
            message = "Je n'arrive pas à utiliser le micro pour le moment."
            return
        }

        // Transcription en direct, sur le Mac.
        var request: SFSpeechAudioBufferRecognitionRequest?
        if speechOK, let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.isAvailable {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            if rec.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
            request = r
            recognition = rec.recognitionTask(with: r) { [weak self] result, _ in
                guard let text = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in self?.updateLive(text) }
            }
        }

        // Le tap tourne sur le fil audio : il ne touche qu'à des objets sûrs.
        let ratio = outFormat.sampleRate / inFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            request?.append(buffer)
            let db = Self.decibels(buffer)
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            if let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) {
                var fed = false
                var err: NSError?
                converter.convert(to: out, error: &err) { _, status in
                    if fed { status.pointee = .noDataNow; return nil }
                    fed = true; status.pointee = .haveData; return buffer
                }
                if err == nil, out.frameLength > 0 { try? file.write(from: out) }
            }
            Task { @MainActor in self?.heard(db) }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            recognition?.cancel(); recognition = nil
            message = "Je n'arrive pas à utiliser le micro pour le moment."
            return
        }

        self.engine = engine; self.file = file; self.converter = converter
        self.request = request; self.fileURL = url
        self.onText = onText; self.onLive = onLive; self.base = httpBase
        detector = SilenceDetector(); startedAt = Date(); liveChangedAt = nil; live = ""
        phase = .listening
        watch = Task { [weak self] in
            while let self, self.phase == .listening, !Task.isCancelled {
                self.checkEnd()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func updateLive(_ text: String) {
        guard phase == .listening, text != live else { return }
        live = text
        liveChangedAt = Date()
        onLive?(text)
    }

    private var lastEvent: SilenceDetector.Event = .none
    private func heard(_ db: Float) {
        guard phase == .listening else { return }
        level = CGFloat(max(0, min(1, (db + 50) / 50)))
        lastEvent = detector.feed(db, at: Date())
    }

    /// Fin de la phrase : les mots ne bougent plus, ou le son retombe au bruit de
    /// fond après avoir parlé, ou plus rien depuis longtemps, ou 30 s.
    private func checkEnd() {
        let now = Date()
        if !live.isEmpty, let t = liveChangedAt, now.timeIntervalSince(t) >= wordsStill { stop(); return }
        if lastEvent == .endOfSpeech { stop(); return }
        if live.isEmpty, lastEvent == .nothingHeard { stop(); return }
        if now.timeIntervalSince(startedAt) >= maxDuration { stop(); return }
    }

    func stop() {
        guard phase == .listening else { return }
        watch?.cancel(); watch = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        request?.endAudio()
        file = nil  // ferme le wav
        converter = nil
        level = 0
        let spoken = live
        phase = .transcribing
        Task {
            var text: String?
            if let url = fileURL {
                text = await viaServeur(url)
                try? FileManager.default.removeItem(at: url)
            }
            recognition?.cancel(); recognition = nil; request = nil
            if text?.isEmpty ?? true { text = spoken.isEmpty ? nil : spoken }
            phase = .idle
            live = ""
            if let text, !text.isEmpty { onText?(text) }
            else if message == nil { message = "Je n'ai rien entendu. Appuyez sur le micro et parlez." }
        }
    }

    // MARK: Outils

    /// Niveau moyen d'un tampon, en dB (−80 à 0).
    nonisolated private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -80 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        return rms > 0 ? max(-80, 20 * log10(rms)) : -80
    }

    private func viaServeur(_ url: URL) async -> String? {
        guard let endpoint = URL(string: base + "/transcribe"),
              let audio = try? Data(contentsOf: url), audio.count > 2000 else { return nil }
        var req = URLRequest(url: endpoint, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        guard let (data, resp) = try? await URLSession.shared.upload(for: req, from: audio),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
