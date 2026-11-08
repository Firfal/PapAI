import SwiftUI
import AVFoundation

enum PairServer {
    static let refusal = "Ce lien n'est pas sûr. Demandez un nouveau QR code depuis l'ordinateur de la personne aidée (Réglages > Mon support)."
    static let officialHost = "papai-450417131702.europe-west1.run.app"
    static func needsNew(status: Int, refused: Bool) -> Bool {
        status == 408 || (status == 403 && refused)
    }

    static func allowed(_ text: String) -> Bool {
        guard let c = URLComponents(string: text), let host = c.host?.lowercased(),
              !host.isEmpty, c.user == nil, c.password == nil else { return false }
        if c.scheme?.lowercased() == "https" { return true }
        #if DEBUG
        guard c.scheme?.lowercased() == "http" else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ (Int($0) ?? 256) <= 255 }) else { return false }
        let octets = parts.map { Int($0)! }
        return octets[0] == 127 || octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
        #else
        return false
        #endif
    }

    static func normalized(_ text: String) -> String {
        guard var c = URLComponents(string: text) else { return text }
        c.scheme = c.scheme?.lowercased(); c.host = c.host?.lowercased()
        if (c.scheme == "https" && c.port == 443) || (c.scheme == "http" && c.port == 80) { c.port = nil }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        return c.string ?? text
    }

    static func sameOrigin(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = URLComponents(string: normalized(lhs)), let b = URLComponents(string: normalized(rhs)) else { return false }
        return a.scheme == b.scheme && a.host == b.host && a.port == b.port
    }
}

/// Adresse d'appairage : `https://…[/k/<clé>]/p/<code>`, éventuellement dans `papai://pair?u=…`.
struct PairLink: Identifiable, Equatable {
    let id = UUID()
    /// Tout ce qui précède `/p/<code>`, par exemple `https://hôte/k/<clé>`.
    var base: String
    /// nil : le code sera tapé à la main.
    var code: String?
    var senior: String?
    var token: String? = nil
    var isManual: Bool { code == nil && token == nil }
    func endpoint(code manual: String) -> String {
        if let token { return origin + "/i/" + token }
        return (isManual ? origin : base) + "/p/" + (code ?? manual)
    }

    var isOfficial: Bool {
        guard let url = URL(string: base), let h = url.host?.lowercased() else { return false }
        return url.scheme?.lowercased() == "https" && h == PairServer.officialHost && (url.port == nil || url.port == 443)
    }

    var host: String {
        guard let u = URL(string: base), let h = u.host else { return base }
        return u.port.map { "\(h):\($0)" } ?? h
    }
    var origin: String {
        guard let c = URLComponents(string: base), let s = c.scheme, let h = c.host else { return base }
        return "\(s)://\(h)" + (c.port.map { ":\($0)" } ?? "")
    }

    /// Accepte `papai://pair?u=<url encodée>` et l'ancien `https://…/p/<code>`.
    static func parse(_ text: String) -> PairLink? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: t), let scheme = c.scheme?.lowercased() else { return nil }
        if scheme == "papai" {
            guard c.host == "pair" else { return nil }
            guard let inner = c.queryItems?.first(where: { $0.name == "u" })?.value,
                  !inner.lowercased().hasPrefix("papai:") else { return nil }
            guard var link = parse(inner) else { return nil }
            link.senior = c.queryItems?.first(where: { $0.name == "n" })?.value ?? link.senior
            return link
        }
        guard PairServer.allowed(t), let host = c.host, !host.isEmpty else { return nil }
        let origin = "\(scheme)://\(host)" + (c.port.map { ":\($0)" } ?? "")
        if let m = c.path.wholeMatch(of: /\/i\/([A-Za-z0-9_-]{22,128})\/?/) {
            return PairLink(base: origin, code: nil, token: String(m.1))
        }
        guard let m = c.path.wholeMatch(of: /((?:\/k\/[^\/]+)?)\/p\/([0-9]{6})\/?/) else { return nil }
        return PairLink(base: origin + m.1, code: String(m.2))
    }
}

private let relations: [(label: String, value: String)] = [
    ("Fille", "sa fille"), ("Fils", "son fils"), ("Proche", "un proche"),
    ("Collègue", "un collègue"), ("Service informatique", "le service informatique"), ("Voisin, voisine", "un voisin"),
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
        Text("Relier ce téléphone").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
        Text("Vous serez prévenu dès qu’une demande d’aide arrive sur son ordinateur. Rien ne bouge sans votre accord.")
            .font(.system(size: 15)).foregroundStyle(Soin.secondary)
        if link.isManual {
            label("Code affiché sur l’ordinateur")
            TextField("000000", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.system(size: 28, weight: .semibold)).tracking(8).multilineTextAlignment(.center)
                .padding(16).soinCard(radius: 18)
                .onChange(of: code) { _, v in
                    code = String(v.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if !code.isEmpty { model.pairNeedsNew = false }
                }
        }
        label("Votre prénom")
        TextField("Claire", text: $name)
            .textContentType(.givenName).font(.system(size: 17)).padding(16).soinCard(radius: 18)
        label("Votre lien avec la personne aidée")
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
        if model.pairBusy {
            HStack {
                ProgressView()
                Text("En attente de l'accord sur l'ordinateur…")
                    .font(.system(size: 17)).foregroundStyle(Soin.ink)
            }
            Text("Demandez à la personne aidée d'appuyer sur Accepter sur son ordinateur (2 min).")
                .font(.system(size: 17)).foregroundStyle(Soin.ink)
        }
        if let e = model.pairError {
            if model.pairRefused {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Demande refusée").font(.system(size: 22, weight: .bold))
                    Text(verbatim: e).font(.system(size: 15))
                }
                .foregroundStyle(Soin.ink).frame(maxWidth: .infinity, alignment: .leading)
                .padding(18).soinCard()
            } else {
                Text(verbatim: e).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.danger)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            if link.isOfficial {
                Text("Serveur PapAI officiel")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(Soin.ink)
            } else {
                Label("Serveur inconnu : ne continuez que si la personne aidée vous a donné ce lien elle-même", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(Soin.danger)
            }
            Text(link.host).font(.system(size: 13)).foregroundStyle(Soin.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .soinCard(link.isOfficial ? Soin.accentSoft : Soin.danger.opacity(0.1))
        Button {
            Task { await model.submitPair(link, code: code, name: name, relation: relation) }
        } label: {
            if model.pairBusy { ProgressView().tint(.white) } else { Text("Rejoindre") }
        }
        .buttonStyle(CapsuleButtonStyle())
        .disabled(model.pairBusy || model.pairNeedsNew || (link.isManual && code.count != 6))
        .opacity(model.pairNeedsNew || (link.isManual && code.count != 6) ? 0.45 : 1)
        .onChange(of: model.pairNeedsNew) { _, needsNew in
            if needsNew { code = "" }
        }
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
                Text("Connecté. Vous serez prévenu dès qu’une demande d’aide arrive.")
            } else if let e = model.linkError {
                Text(e).foregroundStyle(Soin.danger)
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
            Text("Scanner le QR code de l’ordinateur").font(.system(size: 26, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Sur l’ordinateur de \(model.senior) : Mon support › Ajouter un support.")
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
                Text(PairServer.refusal).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.danger)
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
