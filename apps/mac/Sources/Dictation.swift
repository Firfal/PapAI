import AVFoundation
import Speech
import SwiftUI

/// Dictée de la demande. Le Mac enregistre (wav 16 kHz mono), le serveur
/// transcrit avec Gladia ; s'il ne répond pas, le Mac transcrit lui-même.
@MainActor @Observable
final class Dictation {
    enum Phase: Equatable { case idle, listening, transcribing }

    private(set) var phase: Phase = .idle
    private(set) var level: CGFloat = 0
    var message: String?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var limit: Task<Void, Never>?
    private var onText: ((String) -> Void)?
    private var base = ""

    func toggle(httpBase: String, onText: @escaping (String) -> Void) {
        switch phase {
        case .idle: Task { await start(httpBase: httpBase, onText: onText) }
        case .listening: stop()
        case .transcribing: break
        }
    }

    private func start(httpBase: String, onText: @escaping (String) -> Void) async {
        message = nil
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            message = "Je n'ai pas accès au micro. Autorisez-le dans Réglages Système, Confidentialité."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("papai-dictee.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = r; fileURL = url; self.onText = onText; base = httpBase
            phase = .listening
            meter()
            limit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { self?.stop() }
            }
        } catch {
            message = "Je n'arrive pas à utiliser le micro pour le moment."
        }
    }

    private func meter() {
        Task { [weak self] in
            while let self, self.phase == .listening {
                self.recorder?.updateMeters()
                let db = self.recorder?.averagePower(forChannel: 0) ?? -60
                self.level = CGFloat(max(0, min(1, (db + 50) / 50)))
                try? await Task.sleep(for: .milliseconds(80))
            }
            self?.level = 0
        }
    }

    func stop() {
        guard phase == .listening else { return }
        limit?.cancel()
        recorder?.stop(); recorder = nil
        guard let url = fileURL else { phase = .idle; return }
        phase = .transcribing
        Task {
            let text = await transcribe(url)
            try? FileManager.default.removeItem(at: url)
            phase = .idle
            if let text, !text.isEmpty { onText?(text) }
            else if message == nil { message = "Je n'ai pas compris. Touchez le micro et redites-le, ou écrivez." }
        }
    }

    // MARK: Transcription

    private func transcribe(_ url: URL) async -> String? {
        if let t = await viaServeur(url) { return t }
        return await viaMac(url)
    }

    private func viaServeur(_ url: URL) async -> String? {
        guard let endpoint = URL(string: base + "/transcribe"),
              let audio = try? Data(contentsOf: url) else { return nil }
        var req = URLRequest(url: endpoint, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        guard let (data, resp) = try? await URLSession.shared.upload(for: req, from: audio),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Secours sur l'appareil : rien ne quitte le Mac.
    private func viaMac(_ url: URL) async -> String? {
        let status = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else {
            message = "La dictée n'est pas autorisée. Vous pouvez l'activer dans Réglages Système, ou écrire votre demande."
            return nil
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.isAvailable else {
            message = "La dictée n'est pas disponible pour le moment. Écrivez votre demande."
            return nil
        }
        let req = SFSpeechURLRecognitionRequest(url: url)
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        return await withCheckedContinuation { c in
            var done = false
            rec.recognitionTask(with: req) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true; c.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    done = true; c.resume(returning: nil)
                }
            }
        }
    }
}
