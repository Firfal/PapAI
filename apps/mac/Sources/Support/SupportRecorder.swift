import AppKit
import AVFoundation
import ScreenCaptureKit
import Speech
import SwiftUI
import UniformTypeIdentifiers

/// Enregistrement fait par le support sur SON poste, pour créer un automate.
/// Pas de vidéo : une capture toutes les 2 s, gardée seulement si l'écran a
/// changé, et la transcription de sa voix s'il le souhaite. Tout reste sur ce
/// Mac jusqu'à ce qu'il relise les captures et choisisse de les envoyer.
@MainActor
@Observable
final class SupportRecorder {
    struct Shot: Identifiable { let id = UUID(); let image: CGImage; var kept = true }

    var recording = false
    var shots: [Shot] = []
    var narration = ""
    var withVoice = true
    var error: String?
    var seconds = 0

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastPrint: [UInt8] = []
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var speechReq: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var speechTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var spokenBefore = ""
    @ObservationIgnored var onStop: (() -> Void)?

    static let maxShots = 40

    func start() {
        guard !recording else { return }
        error = nil; shots = []; narration = ""; spokenBefore = ""; lastPrint = []; seconds = 0
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            error = "Autorisez PapAI dans Réglages Système › Confidentialité › Enregistrement de l'écran, puis réessayez."
            return
        }
        recording = true
        showPanel()
        NSApp.windows.filter { $0 !== panel && $0.isVisible }.forEach { $0.miniaturize(nil) }
        if withVoice { startVoice() }
        loop = Task { [weak self] in
            while let self, self.recording, !Task.isCancelled {
                await self.grab()
                try? await Task.sleep(for: .seconds(2))
                self.seconds += 2
            }
        }
    }

    func stop() {
        guard recording else { return }
        recording = false
        loop?.cancel(); loop = nil
        stopVoice()
        panel?.close(); panel = nil
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.filter { $0.isMiniaturized }.forEach { $0.deminiaturize(nil) }
        Task { await grab(force: true) }  // l'écran final, toujours
        onStop?()
    }

    // MARK: Captures

    private func grab(force: Bool = false) async {
        guard let img = try? await Self.captureImage() else { return }
        let fp = Self.fingerprint(img)
        if !force, !lastPrint.isEmpty, Self.distance(fp, lastPrint) < 6 { return }
        lastPrint = fp
        if shots.count >= Self.maxShots { shots.remove(at: shots.count / 2) }
        shots.append(Shot(image: img))
    }

    static func captureImage() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { throw ScreenGrabber.CaptureError(message: "Aucun écran") }
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let w = min(1280, display.width)
        config.width = w
        config.height = max(1, Int((Double(display.height) * Double(w) / Double(display.width)).rounded()))
        config.showsCursor = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Empreinte 32×20 en niveaux de gris : assez pour savoir si l'écran a changé.
    static func fingerprint(_ img: CGImage) -> [UInt8] {
        let w = 32, h = 20
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return px }
        ctx.interpolationQuality = .low
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }

    static func distance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count, !a.isEmpty else { return 255 }
        var sum = 0
        for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
        return sum / a.count
    }

    /// Les captures retenues pour Holo : 5 au plus, réparties, la dernière incluse.
    func selected() -> [CGImage] {
        let kept = shots.filter(\.kept).map(\.image)
        guard kept.count > 5 else { return kept }
        return (0..<5).map { kept[Int((Double($0) * Double(kept.count - 1) / 4).rounded())] }
    }

    static func jpegB64(_ img: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: img)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])?.base64EncodedString()
    }

    // MARK: Voix (facultative, transcrite sur ce Mac)

    private func startVoice() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { self.error = "Dictée non autorisée : l'enregistrement continue sans la voix."; return }
                guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.isAvailable else { return }
                let req = SFSpeechAudioBufferRecognitionRequest()
                req.shouldReportPartialResults = true
                if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
                self.speechReq = req
                let input = self.engine.inputNode
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
                self.engine.prepare()
                guard (try? self.engine.start()) != nil else { self.error = "Micro indisponible : l'enregistrement continue sans la voix."; return }
                self.speechTask = rec.recognitionTask(with: req) { result, err in
                    Task { @MainActor in
                        if let result {
                            let t = result.bestTranscription.formattedString
                            self.narration = [self.spokenBefore, t].filter { !$0.isEmpty }.joined(separator: " ")
                            // La reconnaissance s'arrête d'elle-même après ~1 min : on enchaîne.
                            if result.isFinal, self.recording { self.spokenBefore = self.narration; self.restartVoice() }
                        } else if err != nil, self.recording {
                            self.spokenBefore = self.narration; self.restartVoice()
                        }
                    }
                }
            }
        }
    }

    private func restartVoice() { stopVoice(); if recording { startVoice() } }

    private func stopVoice() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        speechReq?.endAudio(); speechTask?.cancel()
        speechReq = nil; speechTask = nil
    }

    // MARK: Encart pendant l'enregistrement

    private func showPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        p.titleVisibility = .hidden; p.titlebarAppearsTransparent = true
        p.level = .floating; p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: RecorderPanel(rec: self))
        if let s = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: s.maxX - 320, y: s.minY + 20))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

private struct RecorderPanel: View {
    let rec: SupportRecorder
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(T.danger).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enregistrement").font(rounded(15, .semibold))
                Text("\(rec.shots.count) capture\(rec.shots.count > 1 ? "s" : "")\(rec.withVoice ? " · voix" : "") · \(rec.seconds / 60):\(String(format: "%02d", rec.seconds % 60))")
                    .font(rounded(12)).foregroundStyle(T.muted)
            }
            Spacer()
            Button("Arrêter") { rec.stop() }.buttonStyle(PillStyle(height: 38))
        }
        .foregroundStyle(T.ink)
        .padding(.horizontal, 16).frame(width: 300, height: 76).background(T.bg)
    }
}

/// Relecture avant envoi : le support retire les captures qui montrent des
/// données sensibles, corrige la transcription, puis demande le brouillon.
struct RecorderReview: View {
    @Bindable var rec: SupportRecorder
    var analyze: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Relire l'enregistrement").font(rounded(22, .bold))
            Label("Retirez toute capture qui montre un mot de passe, un mail ou un document personnel : seules les captures cochées partent vers Holo (5 au plus).",
                  systemImage: "eye.slash")
                .font(rounded(14)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach($rec.shots) { $s in
                        Button { s.kept.toggle() } label: {
                            Image(decorative: s.image, scale: 1).resizable().scaledToFit()
                                .frame(width: 150, height: 94)
                                .opacity(s.kept ? 1 : 0.3)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: s.kept ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 18)).foregroundStyle(s.kept ? T.accent : T.danger).padding(4)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 104)
            Text("Ce que vous avez dit (modifiable)").font(rounded(14, .semibold)).foregroundStyle(T.muted)
            TextEditor(text: $rec.narration).font(rounded(15)).frame(minHeight: 70)
                .scrollContentBackground(.hidden).padding(8).champ()
            HStack {
                Text("\(rec.shots.filter(\.kept).count) capture(s) cochée(s)").font(rounded(14)).foregroundStyle(T.muted)
                Spacer()
                Button("Annuler") { cancel() }.buttonStyle(PillStyle(filled: false, height: 44))
                Button("Analyser avec Holo") { analyze() }
                    .buttonStyle(PillStyle(height: 44, icone: "sparkles"))
                    .disabled(rec.shots.allSatisfy { !$0.kept })
            }
        }
        .padding(16).champ(T.r)
    }
}
