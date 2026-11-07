@preconcurrency import AVFoundation
import Speech
import SwiftUI

/// Dictée de l'aidant, comme sur le Mac (`apps/mac/Sources/Dictation.swift`).
///
/// Un seul flux micro (AVAudioEngine) sert à deux choses :
/// - la transcription en direct sur l'iPhone (SFSpeechRecognizer) : les mots
///   s'écrivent dans le champ pendant qu'on parle ;
/// - un wav 16 kHz mono, transcrit par Gladia via le serveur
///   (`POST /k/<clé>/transcribe`) pour le texte final.
/// Si Gladia ne répond pas, on garde le texte en direct de l'iPhone.
/// Rien ne part seul : le texte reste dans le champ, modifiable, jusqu'à l'envoi.
@MainActor @Observable
final class Dictation {
    enum Phase: Equatable { case idle, listening, transcribing }

    private(set) var phase: Phase = .idle
    private(set) var level: CGFloat = 0
    var message: String?

    /// Les mots ne bougent plus depuis ce délai : la phrase est finie.
    private let wordsStill: TimeInterval = 1.8
    /// Sans transcription en direct : silence après avoir parlé.
    private let quietAfterSpeech: TimeInterval = 1.8
    private let nothingHeard: TimeInterval = 8
    private let maxDuration: TimeInterval = 30

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var fileURL: URL?
    private var endpoint: URL?
    private var onLive: ((String) -> Void)?
    private var onText: ((String) -> Void)?
    private var live = ""
    private var liveFinal = false
    private var startedAt = Date()
    private var liveChangedAt: Date?
    private var voiceAt: Date?
    private var feeder: Task<Void, Never>?
    private var watch: Task<Void, Never>?

    var listening: Bool { phase == .listening }

    /// Adresse de la route de dictée, avec ou sans `/k/<clé>` déjà dans l'adresse du serveur.
    static func endpoint(server: String, key: String) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("/k/") {
            guard !k.isEmpty, let e = k.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
            s += "/k/" + e
        }
        return URL(string: s + "/transcribe")
    }

    /// Un appui pour parler, un appui pour arrêter. `onLive` reçoit les mots en direct,
    /// `onText` le texte final (Gladia, sinon le direct).
    func toggle(endpoint: URL?, onLive: @escaping (String) -> Void, onText: @escaping (String) -> Void) {
        switch phase {
        case .idle: Task { await start(endpoint: endpoint, onLive: onLive, onText: onText) }
        case .listening: stop()
        case .transcribing: break
        }
    }

    // MARK: Écoute

    private func start(endpoint: URL?, onLive: @escaping (String) -> Void, onText: @escaping (String) -> Void) async {
        message = nil
        #if DEBUG
        // Vérification sur simulateur sans micro : `-dictationFile /chemin/audio.wav`
        // ou la variable PAPAI_DICTATION_FILE (`SIMCTL_CHILD_PAPAI_DICTATION_FILE=…`).
        // Sur simulateur, un fichier `Documents/dictee-test.wav` de l'app sert aussi.
        var testFile = (ProcessInfo.processInfo.environment["PAPAI_DICTATION_FILE"]
                        ?? UserDefaults.standard.string(forKey: "dictationFile")).map { URL(fileURLWithPath: $0) }
        #if targetEnvironment(simulator)
        if testFile == nil,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let f = docs.appendingPathComponent("dictee-test.wav")
            if FileManager.default.fileExists(atPath: f.path) { testFile = f }
        }
        #endif
        #else
        let testFile: URL? = nil
        #endif
        if testFile == nil {
            guard await AVAudioApplication.requestRecordPermission() else {
                message = "Autorisez le micro dans Réglages > PapAI."
                return
            }
        }
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }

        var inFormat: AVAudioFormat
        var engine: AVAudioEngine?
        var source: AVAudioFile?
        if let testFile {
            guard let f = try? AVAudioFile(forReading: testFile) else { message = "Fichier audio illisible."; return }
            source = f; inFormat = f.processingFormat
        } else {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
                try session.setActive(true)
            } catch { message = "Je n’arrive pas à utiliser le micro."; return }
            let e = AVAudioEngine()
            engine = e; inFormat = e.inputNode.outputFormat(forBus: 0)
        }
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            message = "Je n’arrive pas à utiliser le micro."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papai-dictee.wav")
        try? FileManager.default.removeItem(at: url)
        guard let file = try? AVAudioFile(forWriting: url, settings: outFormat.settings,
                                         commonFormat: .pcmFormatInt16, interleaved: true) else {
            message = "Je n’arrive pas à utiliser le micro."
            return
        }

        // Transcription en direct, sur l'iPhone.
        var request: SFSpeechAudioBufferRecognitionRequest?
        if speechOK, let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.isAvailable {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            if rec.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
            request = r
            recognition = rec.recognitionTask(with: r) { [weak self] result, err in
                let text = result?.bestTranscription.formattedString
                let final = (result?.isFinal ?? false) || err != nil
                Task { @MainActor in self?.updateLive(text, final: final) }
            }
        }

        let liveRequest = request
        // Tourne sur le fil audio : ne touche qu'à des objets sûrs.
        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let process: @Sendable (AVAudioPCMBuffer) -> Void = { [weak self] buffer in
            liveRequest?.append(buffer)
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

        if let engine {
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { b, _ in process(b) }
            do {
                engine.prepare()
                try engine.start()
            } catch {
                engine.inputNode.removeTap(onBus: 0)
                recognition?.cancel(); recognition = nil
                message = "Je n’arrive pas à utiliser le micro."
                KeepAwake.shared.restart()
                return
            }
        }

        self.engine = engine; self.file = file; self.request = request
        self.fileURL = url; self.endpoint = endpoint
        self.onLive = onLive; self.onText = onText
        startedAt = Date(); liveChangedAt = nil; voiceAt = nil; live = ""; liveFinal = request == nil
        phase = .listening

        if let source {
            // Lecture du fichier au rythme réel, par tranches de 100 ms.
            feeder = Task.detached {
                let chunk = AVAudioFrameCount(source.processingFormat.sampleRate / 10)
                while !Task.isCancelled,
                      let b = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk),
                      (try? source.read(into: b, frameCount: chunk)) != nil, b.frameLength > 0 {
                    process(b)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        watch = Task { [weak self] in
            while let self, self.phase == .listening, !Task.isCancelled {
                self.checkEnd()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Les derniers mots arrivent parfois après l'arrêt du micro : on les garde.
    private func updateLive(_ text: String?, final: Bool) {
        guard phase != .idle else { return }
        if final { liveFinal = true }
        guard let text, text != live else { return }
        live = text
        liveChangedAt = Date()
        onLive?(text)
    }

    private func heard(_ db: Float) {
        guard phase == .listening else { return }
        level = CGFloat(max(0, min(1, (db + 50) / 50)))
        if db > -38 { voiceAt = Date() }
    }

    /// Fin de la phrase : les mots ne bougent plus, ou le silence revient après la voix,
    /// ou rien entendu depuis 8 s, ou 30 s en tout.
    private func checkEnd() {
        let now = Date()
        if !live.isEmpty, let t = liveChangedAt, now.timeIntervalSince(t) >= wordsStill { stop(); return }
        if live.isEmpty, request == nil, let v = voiceAt, now.timeIntervalSince(v) >= quietAfterSpeech { stop(); return }
        if live.isEmpty, now.timeIntervalSince(voiceAt ?? startedAt) >= nothingHeard { stop(); return }
        if now.timeIntervalSince(startedAt) >= maxDuration { stop(); return }
    }

    func stop() {
        guard phase == .listening else { return }
        watch?.cancel(); watch = nil
        feeder?.cancel(); feeder = nil
        let hadEngine = engine != nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        request?.endAudio()
        file = nil  // ferme le wav
        level = 0
        phase = .transcribing
        // Le son muet qui garde l'app éveillée reprend sa place.
        if hadEngine { KeepAwake.shared.restart() }
        Task {
            var text: String?
            if let url = fileURL {
                text = await viaServeur(url)
                try? FileManager.default.removeItem(at: url)
            }
            if text?.isEmpty ?? true {
                // Sans Gladia : le texte de l'iPhone, une fois ses derniers mots arrivés.
                for _ in 0..<20 where !liveFinal { try? await Task.sleep(for: .milliseconds(100)) }
                text = live.isEmpty ? nil : live
            }
            recognition?.cancel(); recognition = nil; request = nil
            phase = .idle
            live = ""
            if let text, !text.isEmpty { onText?(text) }
            else if message == nil { message = "Je n’ai rien entendu. Appuyez sur le micro et parlez." }
            onText = nil; onLive = nil
        }
    }

    /// Fermeture de la feuille : on coupe sans rien renvoyer.
    func cancel() {
        onText = nil; onLive = nil
        stop()
    }

    // MARK: Outils

    /// Niveau moyen d'un tampon, en dB (−80 à 0).
    nonisolated private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else { return -80 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<n { sum += ch[i] * ch[i] }
        } else if let ch = buffer.int16ChannelData?[0] {
            for i in 0..<n { let v = Float(ch[i]) / 32768; sum += v * v }
        } else { return -80 }
        let rms = (sum / Float(n)).squareRoot()
        return rms > 0 ? max(-80, 20 * log10(rms)) : -80
    }

    private func viaServeur(_ url: URL) async -> String? {
        guard let endpoint, let audio = try? Data(contentsOf: url), audio.count > 2000 else { return nil }
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

extension HelperModel {
    var transcribeURL: URL? { Dictation.endpoint(server: serverURL, key: helperKey) }
}

/// Le gros bouton micro des feuilles : un appui pour parler, un pour arrêter.
struct BigMicButton: View {
    let dictation: Dictation
    var size: CGFloat = 96
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    Circle().fill(Soin.accent.opacity(0.18))
                        .frame(width: size + 28 * dictation.level + 16, height: size + 28 * dictation.level + 16)
                        .opacity(dictation.listening ? 1 : 0)
                        .animation(.easeOut(duration: 0.12), value: dictation.level)
                    Circle().fill(dictation.listening ? Soin.accent : Soin.ink).frame(width: size, height: size)
                    if dictation.phase == .transcribing {
                        ProgressView().tint(.white).controlSize(.large)
                    } else {
                        Image(systemName: dictation.listening ? "stop.fill" : "mic.fill")
                            .font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: size + 46, height: size + 46)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(dictation.phase == .transcribing)
            .accessibilityLabel(dictation.listening ? "Arrêter la dictée" : "Dicter")
            Text(caption).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(dictation.listening ? Soin.accent : Soin.secondary)
            if let m = dictation.message, dictation.phase == .idle {
                Text(m).font(.system(size: 14)).foregroundStyle(Soin.ink).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var caption: String {
        switch dictation.phase {
        case .idle: "Appuyez et parlez"
        case .listening: "Je vous écoute… appuyez pour finir"
        case .transcribing: "J’écris ce que vous avez dit…"
        }
    }
}
