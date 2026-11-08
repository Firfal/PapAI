import AVFoundation
import Speech
import SwiftUI

/// Dictée de la demande.
///
/// Un seul flux micro (AVAudioEngine) sert à trois choses à la fois :
/// - le direct Gladia via le relais PapAI (Apple reste prêt en secours) ;
/// - la fin de phrase : quand les mots ne bougent plus, ou que le niveau
///   retombe au bruit de fond (`SilenceDetector`), la demande part seule ;
/// - un wav 16 kHz mono, transcrit par Gladia via le serveur pour le texte final.
/// Si Gladia ne répond pas, on garde le texte disponible sur le Mac.
@MainActor @Observable
final class Dictation {
    enum Phase: Equatable { case idle, listening, transcribing }

    private(set) var phase: Phase = .idle {
        didSet { LocalNarration.shared.setDictating(phase != .idle) }
    }
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
    private var feeder: Task<Void, Never>?
    private var liveClient: GladiaLive?
    private var liveAudio: GladiaLive.Audio.Continuation?
    private var transcript = DictationText()
    private var starting = false
    private var recordingID = UUID()

    func toggle(httpBase: String, onLive: ((String) -> Void)? = nil, onText: @escaping (String) -> Void) {
        switch phase {
        case .idle:
            guard !starting else { return }
            starting = true
            LocalNarration.shared.setDictating(true)
            Task {
                await start(httpBase: httpBase, onLive: onLive, onText: onText)
                starting = false
                if phase == .idle { LocalNarration.shared.setDictating(false) }
            }
        case .listening: stop()
        case .transcribing: break
        }
    }

    // MARK: Écoute

    private func start(httpBase: String, onLive: ((String) -> Void)?, onText: @escaping (String) -> Void) async {
        message = nil
        #if DEBUG
        let testFile = ProcessInfo.processInfo.environment["PAPAI_DICTATION_FILE"].map { URL(fileURLWithPath: $0) }
        #else
        let testFile: URL? = nil
        #endif
        if testFile == nil {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                message = String(localized: "Je n'ai pas accès au micro. Autorisez-le dans Réglages Système, Confidentialité.")
                return
            }
        }
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }

        var engine: AVAudioEngine?
        var source: AVAudioFile?
        let inFormat: AVAudioFormat
        if let testFile {
            guard let f = try? AVAudioFile(forReading: testFile) else { message = String(localized: "Fichier audio illisible."); return }
            source = f; inFormat = f.processingFormat
        } else {
            let e = AVAudioEngine()
            engine = e; inFormat = e.inputNode.outputFormat(forBus: 0)
        }
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                            channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            message = String(localized: "Je n'arrive pas à utiliser le micro pour le moment.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papai-dictee.wav")
        try? FileManager.default.removeItem(at: url)
        guard let file = try? AVAudioFile(forWriting: url, settings: outFormat.settings,
                                         commonFormat: .pcmFormatInt16, interleaved: true) else {
            message = String(localized: "Je n'arrive pas à utiliser le micro pour le moment.")
            return
        }

        // Reconnaissance locale conservée pour la fin de parole et le repli.
        let id = UUID()
        recordingID = id
        var request: SFSpeechAudioBufferRecognitionRequest?
        if speechOK, let rec = SFSpeechRecognizer(locale: Locale(identifier: AppLangue.anglais ? "en-US" : "fr-FR")), rec.isAvailable {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            if rec.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
            request = r
            recognition = rec.recognitionTask(with: r) { [weak self] result, _ in
                guard let text = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in
                    guard let self, self.recordingID == id else { return }
                    self.updateApple(text)
                }
            }
        }

        // Le tap tourne sur le fil audio : il ne touche qu'à des objets sûrs.
        let (audio, continuation) = GladiaLive.Audio.makeStream(bufferingPolicy: .bufferingOldest(128))
        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let liveRequest = request
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
                if err == nil, out.frameLength > 0 {
                    try? file.write(from: out)
                    let bytes = out.audioBufferList.pointee.mBuffers
                    if let data = bytes.mData {
                        let chunk = Data(bytes: data, count: Int(bytes.mDataByteSize))
                        if case .dropped = continuation.yield(chunk) {
                            continuation.finish(throwing: GladiaLive.Failure.overflow)
                        }
                    }
                }
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
                continuation.finish()
                recognition?.cancel(); recognition = nil
                message = String(localized: "Je n'arrive pas à utiliser le micro pour le moment.")
                return
            }
        }

        self.engine = engine; self.file = file; self.converter = converter
        self.request = request; self.fileURL = url
        self.onText = onText; self.onLive = onLive; self.base = httpBase
        detector = SilenceDetector(); startedAt = Date(); liveChangedAt = nil; live = ""
        lastEvent = .none
        transcript = DictationText()
        phase = .listening
        liveAudio = continuation
        guard !AppLangue.anglais else { return }
        let client = GladiaLive()
        liveClient = client
        client.start(transcribe: URL(string: httpBase + "/transcribe"), audio: audio, onText: { [weak self] text in
            guard let self, phase != .idle else { return }
            transcript.updateGladia(text)
            publishLive()
        }, onFallback: { [weak self] in
            guard let self, phase != .idle else { return }
            continuation.finish()
            transcript.fallback()
            publishLive()
        })
        if let source {
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

    private func updateApple(_ text: String) {
        guard phase != .idle else { return }
        if text != transcript.apple { liveChangedAt = Date() }
        transcript.updateApple(text)
        publishLive()
    }

    private func publishLive() {
        let text = transcript.displayed
        guard phase == .listening, text != live else { return }
        live = text
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
        if !transcript.apple.isEmpty, let t = liveChangedAt, now.timeIntervalSince(t) >= wordsStill { stop(); return }
        if lastEvent == .endOfSpeech { stop(); return }
        if !transcript.hasRecognizedSpeech, lastEvent == .nothingHeard { stop(); return }
        if now.timeIntervalSince(startedAt) >= maxDuration { stop(); return }
    }

    func stop() {
        guard phase == .listening else { return }
        watch?.cancel(); watch = nil
        feeder?.cancel(); feeder = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        liveAudio?.finish(); liveAudio = nil
        request?.endAudio()
        file = nil  // ferme le wav
        converter = nil
        level = 0
        phase = .transcribing
        Task {
            var text: String?
            if let url = fileURL {
                text = await viaServeur(url)
                try? FileManager.default.removeItem(at: url)
            }
            recognition?.cancel(); recognition = nil; request = nil
            if text?.isEmpty ?? true {
                await liveClient?.waitForCompletion()
                text = transcript.displayed
            }
            liveClient?.cancel(); liveClient = nil
            phase = .idle
            live = ""
            if let text, !text.isEmpty { onText?(text) }
            else if message == nil { message = String(localized: "Je n'ai rien entendu. Appuyez sur le micro et parlez.") }
        }
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
        // Gladia est réglé en français : en anglais, le texte d'Apple fait foi.
        guard !AppLangue.anglais, let endpoint = URL(string: base + "/transcribe"),
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
