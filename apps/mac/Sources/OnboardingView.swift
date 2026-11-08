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
            Panneau {
                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        dots
                        Text(titre).font(rounded(40, .bold)).tracking(-0.7)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // La place de la mascotte reste réservée à chaque étape : l'en-tête garde
                    // la même hauteur et rien ne bouge d'une page à l'autre.
                    ViewThatFits(in: .horizontal) {
                        Mascotte(humeur: humeurEnTete ?? .ecoute).frame(width: Mascotte.Taille.prenom, height: Mascotte.Taille.prenom)
                        Mascotte(humeur: humeurEnTete ?? .ecoute).frame(width: Mascotte.Taille.prenomReduite, height: Mascotte.Taille.prenomReduite)
                    }
                    .padding(8).background(Circle().fill(.white.opacity(0.92)))
                    .opacity(humeurEnTete == nil ? 0 : 1)
                    .accessibilityHidden(humeurEnTete == nil)
                }
            } corps: {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: firstName
                    case 2: permissions
                    default:
                        ScrollView { HelpersPanel(onboarding: true, titre: false) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 14) {
                if step > 0 {
                    Button("Retour") { step -= 1 }.buttonStyle(PillStyle(filled: false, height: 78))
                }
                Button(action: next) {
                    Text(nextLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 78, icone: step >= count - 1 ? "checkmark.circle" : "arrow.right.circle", plein: true))
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

    private var titre: String {
        switch step {
        case 0: "Bienvenue sur PapAI"
        case 1: "Comment vous appelez-vous ?"
        case 2: "Deux autorisations, une seule fois"
        default: "Qui va vous aider ?"
        }
    }

    private var humeurEnTete: Mascotte.Humeur? {
        switch step {
        case 0: .joyeuse
        case 1: .ecoute
        default: nil
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
                Capsule().fill(.white.opacity(i <= step ? 1 : 0.35))
                    .frame(width: i == step ? 34 : 12, height: 12)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0), value: step)
        .accessibilityLabel("Étape \(step + 1) sur \(count)")
    }

    // MARK: Étapes

    /// Les promesses passent en simple liste quand la place manque.
    private var welcome: some View {
        ViewThatFits(in: .vertical) {
            welcome(cartes: true)
            welcome(cartes: false)
            ScrollView { welcome(cartes: false) }
        }
    }

    private func welcome(cartes: Bool) -> some View {
        VStack(alignment: .leading, spacing: cartes ? 22 : 12) {
            Text("Quand quelque chose ne marche pas sur l'ordinateur, vous appuyez sur un bouton et vous expliquez avec vos mots. Votre support est prévenu et vous aide.")
                .font(rounded(23)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                promise("hand.raised.fill", "Rien ne bouge sur votre écran sans l'accord de votre support.", carte: cartes)
                promise("stop.circle.fill", "Vous pouvez tout arrêter à tout moment.", carte: cartes)
                promise("lock.fill", "Votre écran n'est partagé que quand vous le demandez.", carte: cartes)
            }
        }
    }

    private func promise(_ symbol: String, _ text: String, carte: Bool = true) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(T.accent)
                .frame(width: 38, height: 38).background(Circle().fill(T.mint))
            Text(text).font(rounded(20, .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, carte ? 18 : 0).padding(.vertical, carte ? 12 : 0)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(carte ? T.field : .clear))
    }

    private var firstName: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Votre prénom suffit. C'est ainsi que PapAI vous dira bonjour.")
                .font(rounded(21)).foregroundStyle(T.muted)
            HStack(spacing: 14) {
                Image(systemName: "person.fill").font(.system(size: 22)).foregroundStyle(T.muted)
                    .accessibilityHidden(true)
                TextField("Votre prénom", text: $name)
                    .textFieldStyle(.plain).font(rounded(30, .semibold))
                    .focused($nameFocused)
                    .onSubmit(next)
                    .onAppear { nameFocused = true }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .champ(T.r, actif: nameFocused)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
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
    var titre = true
    @State private var copiedLink: String?

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                if titre {
                    Text(onboarding ? "Qui va vous aider ?" : "Mon support")
                        .font(rounded(onboarding ? 44 : 34, .bold)).tracking(-0.6)
                }
                Text(model.helpers.isEmpty
                     ? "Votre support reçoit vos demandes d'aide et vous répond. S'il est à côté de vous, il scanne le code avec son téléphone. Sinon, envoyez-lui le lien par SMS ou WhatsApp."
                     : "Votre support reçoit vos demandes d'aide et vous répond. Il gère cette liaison depuis son téléphone.")
                    .font(rounded(20)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                if let added = model.pairAdded {
                    Label { Text(verbatim: "\(added) est maintenant support.") } icon: { Image(systemName: "checkmark.circle.fill") }
                        .font(rounded(19, .semibold)).foregroundStyle(T.leaf)
                }
                ForEach(model.helpers) { h in
                    HStack(spacing: 14) {
                        // On affiche le rôle, pas le prénom de la personne qui aide.
                        Image(systemName: "person.fill.checkmark")
                            .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46).background(Circle().fill(T.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Support IT").font(rounded(21, .semibold))
                            if h.online {
                                Pastille(texte: "En ligne", icone: "circle.fill", ton: .vert, taille: 14)
                            }
                            if !h.relation.isEmpty {
                                Text(h.relation.prefix(1).uppercased() + h.relation.dropFirst())
                                    .font(rounded(16)).foregroundStyle(T.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .champ(T.r)
                }
                // Un seul support à la fois.
                if model.helpers.isEmpty && model.pairCode == nil && model.pairURL == nil {
                    Button("Ajouter un support") {
                        model.startPairing()
                    }
                    .buttonStyle(PillStyle(filled: true, height: 60))
                    .disabled(!model.connected)
                    if !model.connected {
                        Text("Connexion au serveur en cours…").font(rounded(16)).foregroundStyle(T.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.pairCode != nil || model.pairURL != nil {
                pairCard(code: model.pairCode, qr: model.pairAppURL ?? model.pairURL ?? "", url: model.pairURL ?? "")
            }
        }
    }

    private func pairCard(code: String?, qr qrText: String, url: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if let qr = QRCode.image(qrText) {
                    Image(nsImage: qr).interpolation(.none).resizable()
                        .frame(width: 110, height: 110)
                        .accessibilityLabel("QR code à scanner par votre support")
                }
                VStack(spacing: 8) {
                    if let code {
                        Text("ou le code").font(rounded(16)).foregroundStyle(T.muted)
                        Text(code.prefix(3) + " " + code.suffix(3))
                            .font(rounded(28, .semibold))
                            .monospacedDigit().tracking(2)
                            .textSelection(.enabled)
                    } else {
                        Text("Lien d'invitation").font(rounded(20, .semibold))
                    }
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
        .champ(T.r)
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
            Panneau {
                HStack(alignment: .center, spacing: 22) {
                    Text(String(request.from.prefix(1)).uppercased())
                        .font(rounded(40, .bold)).foregroundStyle(T.leaf)
                        .frame(width: 88 * CGFloat(model.textScale), height: 88 * CGFloat(model.textScale))
                        .background(Circle().fill(.white))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Pastille(texte: request.rdv ? "C'est l'heure de votre rendez-vous" : request.ticket != nil ? "Votre demande en attente" : "Proposition d'aide", ton: .violet, taille: 17)
                        Text(request.ticket != nil ? "\(request.from) est disponible pour vous aider" : "\(request.from) propose de vous aider").font(rounded(44, .bold)).tracking(-0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    if !request.task.isEmpty {
                        Text("« \(request.task) »").font(rounded(26, .medium))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .champ(T.r)
                    }
                    Text("Si vous acceptez, PapAI va regarder votre écran. Rien ne bouge avant l'accord de \(request.from), et vous pouvez arrêter à tout moment.")
                        .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 14) {
                Button { model.refuseRemote() } label: { Text("Non merci").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(filled: false, height: 78))
                    .keyboardShortcut(.cancelAction)
                Button { model.acceptRemote() } label: { Text("Oui, j'accepte").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(height: 78, icone: "checkmark.circle", plein: true))
                    .disabled(!model.connected)
            }
        }
    }
}

func rdvText(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = "EEEE d MMMM 'à' HH:mm"
    return f.string(from: d)
}

/// La demande est partie mais aucun support n'est disponible : elle attend.
struct QueuedView: View {
    @Environment(AppModel.self) private var model
    let ticket: QueuedTicket

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                VStack(alignment: .leading, spacing: 12) {
                    Pastille(texte: "Demande n° \(ticket.number)", icone: "person.wave.2.fill", ton: .orange, taille: 17)
                    Text("Votre demande est partie").font(rounded(44, .bold)).tracking(-0.7)
                }
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    if !ticket.task.isEmpty {
                        Text("« \(ticket.task) »").font(rounded(24, .medium))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .champ(T.r)
                    }
                    if let rdv = ticket.rdv {
                        Text("Rendez-vous \(rdvText(rdv)). PapAI vous préviendra à l'heure dite.")
                            .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Personne n'est disponible pour l'instant. PapAI vous préviendra dès que \(model.helperName) sera là. Vous pouvez aussi fixer un rendez-vous.")
                            .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            ForEach([("Dans 1 heure", "1h"), ("Demain à 9 h", "demain9"), ("Demain à 14 h", "demain14")], id: \.1) { slot in
                                Button { model.scheduleTicket(slot.1) } label: { Text(slot.0) }
                                    .buttonStyle(PillStyle(filled: false, height: 56, icone: "calendar"))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Button { model.queuedShown = false } label: { Text("D'accord").frame(maxWidth: .infinity) }
                .buttonStyle(PillStyle(height: 78, icone: "checkmark.circle", plein: true))
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct PairRequestView: View {
    @Environment(AppModel.self) private var model
    let request: PairRequest

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                VStack(alignment: .leading, spacing: 12) {
                    Pastille(texte: "Nouveau support", icone: "person.wave.2.fill", ton: .bleu, taille: 17)
                    Text(verbatim: "\(request.name) veut devenir votre support").font(rounded(44, .bold)).tracking(-0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    if !request.relation.isEmpty {
                        Text(verbatim: request.relation).font(rounded(26, .medium))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .champ(T.r)
                    }
                    Text("Acceptez seulement si vous connaissez cette personne.")
                        .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Si quelqu'un vous a appelé ou écrit pour vous demander ce code, refusez.")
                        .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 14) {
                Button { model.answerPair(false) } label: { Text("Refuser").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(filled: false, height: 78))
                    .keyboardShortcut(.cancelAction)
                Button { model.answerPair(true) } label: { Text("Accepter").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(height: 78, icone: "checkmark.circle", plein: true))
                    .disabled(!model.connected)
            }
        }
    }
}
