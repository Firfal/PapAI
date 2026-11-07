import CoreImage
import SwiftUI

/// Premier lancement : bienvenue, prénom, taille du texte, autorisations,
/// puis ajout d'un proche. Une seule fois ; tout se modifie ensuite dans
/// les réglages.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    private var step: Int {
        get { model.onboardingStep }
        nonmutating set { model.onboardingStep = newValue }
    }
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private let count = 5

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 22) {
                dots
                Group {
                    switch step {
                    case 0: welcome
                    case 1: firstName
                    case 2: textSize
                    case 3: permissions
                    default: HelpersPanel(onboarding: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .foregroundStyle(T.ink).padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))

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
                }
            }
        }
    }

    private var nextLabel: String {
        switch step {
        case 0: "Commencer"
        case 3: model.screenOK && model.axOK ? "Continuer" : "Plus tard"
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

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Bienvenue sur PapAI").font(rounded(52, .semibold)).tracking(-0.8)
            Text("Quand quelque chose ne marche pas sur l'ordinateur, vous appuyez sur un bouton et vous expliquez avec vos mots. Un proche est prévenu et vous aide, avec Holo, un assistant qui sait se servir de l'ordinateur.")
                .font(rounded(23)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            promise("hand.raised.fill", "Rien ne bouge sur votre écran sans l'accord de votre proche.")
            promise("stop.circle.fill", "Vous pouvez tout arrêter à tout moment.")
            promise("lock.fill", "Votre écran n'est partagé que quand vous le demandez.")
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(T.accent).frame(width: 34)
            Text(text).font(rounded(20, .medium)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var firstName: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Comment vous appelez-vous ?").font(rounded(44, .semibold)).tracking(-0.6)
            Text("Votre prénom suffit. C'est ainsi que PapAI vous dira bonjour.")
                .font(rounded(21)).foregroundStyle(T.muted)
            TextField("Votre prénom", text: $name)
                .textFieldStyle(.plain).font(rounded(30, .semibold))
                .focused($nameFocused)
                .padding(.horizontal, 26).padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                .onSubmit(next)
                .onAppear { nameFocused = true }
        }
    }

    private var textSize: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("La taille du texte").font(rounded(44, .semibold)).tracking(-0.6)
            Text("Choisissez ce qui est le plus confortable à lire. Vous pourrez changer plus tard.")
                .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                ForEach(TextScale.options, id: \.value) { opt in
                    let on = abs(model.textScale - opt.value) < 0.01
                    Button { model.setTextScale(opt.value) } label: {
                        VStack(spacing: 10) {
                            Text("Aa").font(.system(size: 54 * opt.value, weight: .semibold, design: .rounded))
                            Text(opt.label).font(.system(size: 20 * opt.value, weight: .medium, design: .rounded))
                        }
                        .frame(maxWidth: .infinity).frame(height: 190)
                        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                        .overlay(RoundedRectangle(cornerRadius: T.r, style: .continuous)
                            .stroke(on ? T.accent : .clear, lineWidth: 4))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Deux autorisations, une seule fois").font(rounded(44, .semibold)).tracking(-0.6)
            Text("macOS doit vous demander votre accord. Cliquez sur chaque bouton, puis cochez PapAI dans la liste qui s'ouvre.")
                .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            PermissionRow(ok: model.screenOK, title: "Voir mon écran",
                          detail: "Pour que Holo voie ce que vous voyez. Jamais sans votre demande.",
                          action: Permissions.requestScreen)
            PermissionRow(ok: model.axOK, title: "Utiliser la souris et le clavier",
                          detail: "Pour cliquer à votre place, uniquement après l'accord de votre proche.",
                          action: Permissions.requestAccessibility)
        }
    }
}

/// Les proches : la liste, et l'ajout par QR code ou code à 6 chiffres.
/// Sert à l'accueil et dans les réglages.
struct HelpersPanel: View {
    @Environment(AppModel.self) private var model
    var onboarding = false

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                Text(onboarding ? "Qui va vous aider ?" : "Mes proches")
                    .font(rounded(onboarding ? 44 : 34, .semibold)).tracking(-0.6)
                Text("Votre fille, votre fils, un ami… Il ou elle scanne le code avec son téléphone et donne son prénom. Vous pouvez en ajouter plusieurs.")
                    .font(rounded(20)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                if let added = model.pairAdded {
                    Label("\(added) fait maintenant partie de vos proches.", systemImage: "checkmark.circle.fill")
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
                    Button(model.helpers.isEmpty ? "Ajouter un proche" : "Ajouter un autre proche") {
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
                pairCard(code: code, url: model.pairURL ?? "")
            }
        }
    }

    private func pairCard(code: String, url: String) -> some View {
        VStack(spacing: 10) {
            if let qr = QRCode.image(url) {
                Image(nsImage: qr).interpolation(.none).resizable()
                    .frame(width: 170, height: 170)
                    .accessibilityLabel("QR code à scanner par votre proche")
            }
            Text("ou le code").font(rounded(16)).foregroundStyle(T.muted)
            Text(code.prefix(3) + " " + code.suffix(3))
                .font(.system(size: 38 * CGFloat(TextScale.current), weight: .semibold, design: .rounded))
                .monospacedDigit().tracking(4)
                .textSelection(.enabled)
            Text("Valable 10 minutes").font(rounded(15)).foregroundStyle(T.muted)
            Button("Annuler") { model.stopPairing() }.buttonStyle(.plain).font(rounded(17, .semibold)).foregroundStyle(T.muted)
        }
        .foregroundStyle(T.ink)
        .padding(22)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
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
                HStack(spacing: 12) {
                    Image(systemName: "person.wave.2.fill").font(.system(size: 26)).foregroundStyle(T.accent)
                    Text("Proposition d'aide").font(rounded(20, .semibold)).foregroundStyle(T.accent)
                }
                Text("\(request.from) propose de vous aider").font(rounded(48, .semibold)).tracking(-0.7)
                    .fixedSize(horizontal: false, vertical: true)
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
