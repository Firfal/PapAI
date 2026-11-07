import SwiftUI
import AVFoundation

/// Adresse d'appairage : `https://…[/k/<clé>]/p/<code>`, éventuellement dans `papai://pair?u=…`.
struct PairLink: Identifiable, Equatable {
    let id = UUID()
    /// Tout ce qui précède `/p/<code>`, par exemple `https://hôte/k/<clé>`.
    var base: String
    /// nil : le code sera tapé à la main.
    var code: String?

    var host: String { URL(string: base)?.host ?? base }
    var origin: String {
        guard let c = URLComponents(string: base), let s = c.scheme, let h = c.host else { return base }
        return "\(s)://\(h)" + (c.port.map { ":\($0)" } ?? "")
    }

    /// Accepte `papai://pair?u=<url encodée>` et l'ancien `https://…/p/<code>`.
    static func parse(_ text: String) -> PairLink? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: t), let scheme = c.scheme?.lowercased() else { return nil }
        if scheme == "papai" {
            guard let inner = c.queryItems?.first(where: { $0.name == "u" })?.value,
                  !inner.lowercased().hasPrefix("papai:") else { return nil }
            return parse(inner)
        }
        guard scheme == "http" || scheme == "https", let host = c.host, !host.isEmpty,
              let m = c.path.wholeMatch(of: /(.*)\/p\/(\d{6})\/?/) else { return nil }
        let origin = "\(scheme)://\(host)" + (c.port.map { ":\($0)" } ?? "")
        return PairLink(base: origin + m.1, code: String(m.2))
    }
}

private let relations: [(label: String, value: String)] = [
    ("Fille", "sa fille"), ("Fils", "son fils"), ("Petite-fille", "sa petite-fille"),
    ("Petit-fils", "son petit-fils"), ("Proche", "un proche"), ("Voisin, voisine", "un voisin"),
]

/// « Rejoindre <prénom> » : prénom et lien, puis POST et réglage automatique.
struct PairSheet: View {
    @Bindable var model: HelperModel
    let link: PairLink
    @State private var name = ""
    @State private var relation = ""
    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.pairDone { done } else { form }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.pairBusy)
        .onAppear { if name.isEmpty { name = model.helperName ?? "" } }
    }

    @ViewBuilder private var form: some View {
        Text("Rejoindre \(model.senior)").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
        Text("Vous serez prévenu quand elle demande de l’aide sur son ordinateur. Rien ne bouge sans votre accord.")
            .font(.system(size: 15)).foregroundStyle(Soin.secondary)
        if link.code == nil {
            label("Code affiché sur l’ordinateur")
            TextField("000000", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.system(size: 28, weight: .semibold)).tracking(8).multilineTextAlignment(.center)
                .padding(16).soinCard(radius: 18)
                .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
        }
        label("Votre prénom")
        TextField("Claire", text: $name)
            .textContentType(.givenName).font(.system(size: 17)).padding(16).soinCard(radius: 18)
        label("Votre lien avec \(model.senior)")
        FlowLayout(spacing: 8) {
            ForEach(relations, id: \.value) { r in
                Button { relation = relation == r.value ? "" : r.value } label: {
                    Text(r.label).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(relation == r.value ? .white : Soin.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(relation == r.value ? Soin.ink : Soin.card, in: Capsule())
                }
            }
        }
        if let e = model.pairError {
            Text(e).font(.system(size: 15, weight: .semibold)).foregroundStyle(.red)
        }
        Text("Serveur : \(link.host)").font(.system(size: 13)).foregroundStyle(Soin.secondary)
        Button {
            Task { await model.submitPair(link, code: code, name: name, relation: relation) }
        } label: {
            if model.pairBusy { ProgressView().tint(.white) } else { Text("Rejoindre") }
        }
        .buttonStyle(CapsuleButtonStyle())
        .disabled(model.pairBusy)
        Button("Annuler") { dismiss() }
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.secondary)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var done: some View {
        Spacer(minLength: 40)
        Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Soin.accent)
            .frame(width: 72, height: 72).background(Soin.accentSoft, in: Circle())
            .frame(maxWidth: .infinity)
        Text("Vous êtes relié à \(model.senior)").font(.system(size: 26, weight: .bold)).foregroundStyle(Soin.ink)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        HStack(spacing: 8) {
            if model.connected {
                Circle().fill(Soin.accent).frame(width: 8, height: 8)
                Text("Connecté. Vous serez prévenu dès qu’elle demande de l’aide.")
            } else if let e = model.linkError {
                Text(e)
            } else {
                ProgressView().tint(Soin.accent)
                Text("Connexion au serveur…")
            }
        }
        .font(.system(size: 15)).foregroundStyle(Soin.secondary).multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        Spacer(minLength: 30)
        Button("Terminer") { model.sheet = nil }.buttonStyle(CapsuleButtonStyle())
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.secondary)
    }
}

// MARK: - Scanner

struct ScannerSheet: View {
    @Bindable var model: HelperModel
    @State private var problem: String?
    @State private var wrongCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scanner le QR de l’ordinateur").font(.system(size: 26, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Sur l’ordinateur de \(model.senior) : Proches › Ajouter un proche.")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
            ZStack {
                Soin.ink
                if let problem {
                    Text(problem).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(24)
                } else {
                    QRScannerView(onCode: found, onProblem: { problem = $0 })
                }
            }
            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            if wrongCode {
                Text("Ce QR n’est pas celui de PapAI.").font(.system(size: 15, weight: .semibold)).foregroundStyle(.red)
            }
            Spacer()
            if let l = model.manualPairLink() {
                Button("Entrer le code à 6 chiffres") { model.openPair(l) }
                    .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
            }
            Button("Annuler") { model.sheet = model.isConfigured ? nil : .settings }
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func found(_ text: String) -> Bool {
        guard let link = PairLink.parse(text) else { wrongCode = true; return false }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.openPair(link)
        return true
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    /// Renvoie true si le code est accepté (le scanner s'arrête alors).
    var onCode: (String) -> Bool
    var onProblem: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController(); c.onCode = onCode; c.onProblem = onProblem; return c
    }
    func updateUIViewController(_ c: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Bool = { _ in false }
    var onProblem: (String) -> Void = { _ in }
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var lastRejected: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { [weak self] in
                    ok ? self?.configure() : self?.onProblem("PapAI n’a pas accès à l’appareil photo. Autorisez-le dans Réglages › PapAI.")
                }
            }
        default:
            onProblem("PapAI n’a pas accès à l’appareil photo. Autorisez-le dans Réglages › PapAI.")
        }
    }

    private func configure() {
        guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            onProblem("Appareil photo indisponible sur cet appareil. Entrez le code à 6 chiffres.")
            return
        }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { onProblem("Appareil photo indisponible."); return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        p.frame = view.bounds
        view.layer.addSublayer(p)
        preview = p
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        MainActor.assumeIsolated {
            guard let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  text != lastRejected else { return }
            if onCode(text) {
                let s = session
                DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
            } else {
                lastRejected = text
            }
        }
    }
}
