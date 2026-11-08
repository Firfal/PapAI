import CoreImage
import SwiftUI

/// Premier lancement : bienvenue, prénom, autorisations, puis ajout d'un
/// proche. La taille du texte se règle dans les réglages, pas ici. Une seule fois ; tout se modifie ensuite dans
/// les réglages.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    private var step: Int {
        get { model.onboardingStep }
        nonmutating set { model.onboardingStep = newValue }
    }
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private let count = 4

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 22) {
                dots
                Group {
                    switch step {
                    case 0: welcome
                    case 1: firstName
                    case 2: permissions
                    default:
                        ScrollView { HelpersPanel(onboarding: true) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .foregroundStyle(T.ink).padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(step == 0 ? T.peach : T.mint))

            HStack(spacing: 14) {
                if step > 0 {
                    Button("Retour") { step -= 1 }.buttonStyle(PillStyle(filled: false, height: 78))
                }
                Button(action: next) {
                    Text(nextLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 78))
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            let n = UserDefaults.standard.string(forKey: "firstName") ?? ""
            name = n
            // Captures d'écran : PAPAI_DEMO=onboarding4 ouvre directement l'étape 5.
            if let d = ProcessInfo.processInfo.environment["PAPAI_DEMO"], d.hasPrefix("onboarding"),
               let k = Int(d.dropFirst("onboarding".count)) {
                step = min(k, count - 1)
                if step == count - 1 {
                    model.helpers = [Helper(id: "1", name: "Claire", relation: "sa fille")]
                    model.pairCode = "482913"
                    model.pairURL = "http://192.168.1.20:8000/p/482913"
                    model.pairAppURL = AppModel.appPairingURL(model.pairURL!)
                }
            }
        }
    }

    private var nextLabel: String {
        switch step {
        case 0: "Commencer"
        case 2: model.screenOK && model.axOK ? "Continuer" : "Plus tard"
        case count - 1: model.helpers.isEmpty ? "Plus tard" : "Terminer"
        default: "Continuer"
        }
    }

    private func next() {
        if step == 1 {
            let n = name.trimmingCharacters(in: .whitespaces)
            if n.isEmpty { nameFocused = true; return }
            model.setFirstName(n)
        }
        if step >= count - 1 { model.finishOnboarding(); return }
        step += 1
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= step ? T.accent : T.card)
                    .frame(width: i == step ? 34 : 12, height: 12)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0), value: step)
        .accessibilityLabel("Étape \(step + 1) sur \(count)")
    }

    // MARK: Étapes

    /// Le décor cède la place avant le texte : mascotte réduite, promesses sans carte, puis mascotte masquée.
    private var welcome: some View {
        let s = CGFloat(model.textScale)
        return ViewThatFits(in: .vertical) {
            welcome(mascotte: 190 * s)
            welcome(mascotte: 110)
            welcome(mascotte: 110, cartes: false)
            welcome(mascotte: nil, cartes: false)
            welcome(mascotte: nil, cartes: false, titre: 44)
            ScrollView { welcome(mascotte: nil, cartes: false, titre: 44) }
        }
    }

    private func welcome(mascotte taille: CGFloat?, cartes: Bool = true, titre: CGFloat = 52) -> some View {
        VStack(alignment: .leading, spacing: cartes ? 22 : titre < 52 ? 10 : 12) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: cartes ? 18 : titre < 52 ? 10 : 12) {
                    Text("Bienvenue sur PapAI").font(rounded(titre, .bold)).tracking(-0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Quand quelque chose ne marche pas sur l'ordinateur, vous appuyez sur un bouton et vous expliquez avec vos mots. Votre support est prévenu et vous aide, avec Holo, un assistant qui sait se servir de l'ordinateur.")
                        .font(rounded(23)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let taille {
                    Mascotte(humeur: .joyeuse).frame(width: taille, height: taille)
                }
            }
            promise("hand.raised.fill", "Rien ne bouge sur votre écran sans l'accord de votre support.", carte: cartes)
            promise("stop.circle.fill", "Vous pouvez tout arrêter à tout moment.", carte: cartes)
            promise("lock.fill", "Votre écran n'est partagé que quand vous le demandez.", carte: cartes)
        }
    }

    private func promise(_ symbol: String, _ text: String, carte: Bool = true) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(T.leaf).frame(width: 34)
            Text(text).font(rounded(20, .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, carte ? 18 : 0).padding(.vertical, carte ? 12 : 0)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(carte ? T.card.opacity(0.8) : .clear))
    }

    private var firstName: some View {
        let s = CGFloat(model.textScale)
        return ViewThatFits(in: .vertical) {
            firstName(mascotte: 120 * s)
            firstName(mascotte: 72)
            firstName(mascotte: nil)
        }
    }

    private func firstName(mascotte taille: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 24) {
                if let taille {
                    Mascotte(humeur: .ecoute).frame(width: taille, height: taille)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Comment vous appelez-vous ?").font(rounded(44, .bold)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Votre prénom suffit. C'est ainsi que PapAI vous dira bonjour.")
                        .font(rounded(21)).foregroundStyle(T.muted)
                }
            }
            TextField("Votre prénom", text: $name)
                .textFieldStyle(.plain).font(rounded(30, .semibold))
                .focused($nameFocused)
                .padding(.horizontal, 26).padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                .onSubmit(next)
                .onAppear { nameFocused = true }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Deux autorisations, une seule fois").font(rounded(44, .bold)).tracking(-0.6)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text("macOS doit vous demander votre accord. Cliquez sur chaque bouton, puis cochez PapAI dans la liste qui s'ouvre.")
                .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            PermissionRow(ok: model.screenOK, title: "Voir mon écran",
                          detail: "Pour que Holo voie ce que vous voyez. Jamais sans votre demande.",
                          action: Permissions.requestScreen)
            PermissionRow(ok: model.axOK, title: "Utiliser la souris et le clavier",
                          detail: "Pour cliquer à votre place, uniquement après l'accord de votre support.",
                          action: Permissions.requestAccessibility)
        }
    }
}

/// Les proches : la liste, et l'ajout par QR code ou code à 6 chiffres.
/// Sert à l'accueil et dans les réglages.
struct HelpersPanel: View {
    @Environment(AppModel.self) private var model
    var onboarding = false
    @State private var copiedLink: String?

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                Text(onboarding ? "Qui va vous aider ?" : "Mon support")
                    .font(rounded(onboarding ? 44 : 34, .semibold)).tracking(-0.6)
                Text("Votre fille, votre fils, un ami… S'il est à côté de vous, il scanne le code avec son téléphone. Sinon, envoyez-lui le lien par SMS ou WhatsApp. Vous pouvez en ajouter plusieurs.")
                    .font(rounded(20)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                if let added = model.pairAdded {
                    Label("\(added) fait maintenant partie de votre support.", systemImage: "checkmark.circle.fill")
                        .font(rounded(19, .semibold)).foregroundStyle(T.accent)
                }
                ForEach(model.helpers) { h in
                    HStack(spacing: 14) {
                        Text(String(h.name.prefix(1)).uppercased())
                            .font(rounded(20, .semibold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46).background(Circle().fill(T.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name).font(rounded(21, .semibold))
                            if !h.relation.isEmpty {
                                Text(h.relation.prefix(1).uppercased() + h.relation.dropFirst())
                                    .font(rounded(16)).foregroundStyle(T.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        if !onboarding {
                            Button { model.removeHelper(h) } label: {
                                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                                    .frame(width: 36, height: 36).background(Circle().fill(T.bg))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Retirer \(h.name)")
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                }
                if model.pairCode == nil {
                    Button(model.helpers.isEmpty ? "Ajouter un support" : "Ajouter un autre support") {
                        model.startPairing()
                    }
                    .buttonStyle(PillStyle(filled: model.helpers.isEmpty, height: 60))
                    .disabled(!model.connected)
                    if !model.connected {
                        Text("Connexion au serveur en cours…").font(rounded(16)).foregroundStyle(T.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let code = model.pairCode {
                pairCard(code: code, qr: model.pairAppURL ?? model.pairURL ?? "", url: model.pairURL ?? "")
            }
        }
    }

    private func pairCard(code: String, qr qrText: String, url: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if let qr = QRCode.image(qrText) {
                    Image(nsImage: qr).interpolation(.none).resizable()
                        .frame(width: 110, height: 110)
                        .accessibilityLabel("QR code à scanner par votre support")
                }
                VStack(spacing: 8) {
                    Text("ou le code").font(rounded(16)).foregroundStyle(T.muted)
                    Text(code.prefix(3) + " " + code.suffix(3))
                        .font(rounded(28, .semibold))
                        .monospacedDigit().tracking(2)
                        .textSelection(.enabled)
                    Text(model.pairLong ? "Valable 24 heures" : "Valable 10 minutes").font(rounded(15)).foregroundStyle(T.muted)
                }.frame(maxWidth: .infinity)
            }
            if let link = URL(string: url) {
                ShareLink(item: link, subject: Text("Rejoignez-moi sur PapAI"),
                          message: Text(model.invitationText)) {
                    Label("Envoyer par SMS, WhatsApp, mail…", systemImage: "square.and.arrow.up")
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 64))
            }
            if !url.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(url, forType: .string) { copiedLink = url }
                } label: {
                    Label(copiedLink == url ? "Lien copié" : "Copier le lien",
                          systemImage: copiedLink == url ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(filled: false, height: 50))
                Text("Sans l'app PapAI : \(url)")
                    .font(rounded(13)).foregroundStyle(T.muted)
                    .multilineTextAlignment(.center).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Annuler") { copiedLink = nil; model.stopPairing() }
                .buttonStyle(.plain).font(rounded(17, .semibold)).foregroundStyle(T.muted)
                .frame(minHeight: 50)
        }
        .foregroundStyle(T.ink)
        .padding(12).frame(width: 350)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
        .onChange(of: url) { copiedLink = nil }
    }
}

enum QRCode {
    static func image(_ text: String) -> NSImage? {
        guard !text.isEmpty, let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

/// Un proche propose une session : la personne aidée accepte ou refuse.
struct RemoteRequestView: View {
    @Environment(AppModel.self) private var model
    let request: RemoteRequest

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 22) {
                    Text(String(request.from.prefix(1)).uppercased())
                        .font(rounded(40, .bold)).foregroundStyle(.white)
                        .frame(width: 88 * CGFloat(model.textScale), height: 88 * CGFloat(model.textScale))
                        .background(Circle().fill(T.accent))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Proposition d'aide").font(rounded(20, .semibold)).foregroundStyle(T.leaf)
                        Text("\(request.from) propose de vous aider").font(rounded(48, .bold)).tracking(-0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !request.task.isEmpty {
                    Text("« \(request.task) »").font(rounded(26, .medium))
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                }
                Text("Si vous acceptez, PapAI va regarder votre écran. Rien ne bouge avant l'accord de \(request.from), et vous pouvez arrêter à tout moment.")
                    .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.ink).padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))

            HStack(spacing: 14) {
                Button { model.refuseRemote() } label: { Text("Non merci").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(filled: false, height: 78))
                    .keyboardShortcut(.cancelAction)
                Button { model.acceptRemote() } label: { Text("Oui, j'accepte").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(height: 78))
                    .disabled(!model.connected)
            }
        }
    }
}
