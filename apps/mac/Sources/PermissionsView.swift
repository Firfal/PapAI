import SwiftUI

/// Premier lancement : deux autorisations, expliquées simplement.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                Text("Deux autorisations, une seule fois").font(rounded(40, .bold)).tracking(-0.6)
                    .lineLimit(2).minimumScaleFactor(0.8)
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Pour que \(model.helperName) puisse vous aider, macOS doit vous demander votre accord. Cliquez sur chaque bouton, puis cochez PapAI dans la liste qui s'ouvre.")
                        .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    row(ok: model.screenOK, title: "Voir mon écran",
                        detail: "Pour que Holo voie ce que vous voyez. Jamais sans votre demande.",
                        action: Permissions.requestScreen)
                    row(ok: model.axOK, title: "Utiliser la souris et le clavier",
                        detail: "Pour cliquer à votre place, uniquement après l'accord de \(model.helperName).",
                        action: Permissions.requestAccessibility)
                    Spacer(minLength: 0)
                }
            }
            Button { model.permissionsDismissed = true } label: {
                Text(model.screenOK && model.axOK ? "Continuer" : "Plus tard").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillStyle(height: 78, icone: "arrow.right.circle", plein: true))
        }
    }

    private func row(ok: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        PermissionRow(ok: ok, title: title, detail: detail, action: action)
    }
}

struct PermissionRow: View {
    var ok: Bool
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 30)).foregroundStyle(ok ? Pastille.Ton.vert.texte : T.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(rounded(22, .semibold))
                Text(detail).font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !ok {
                Button("Autoriser", action: action).buttonStyle(PillStyle(height: 48, icone: "lock.open"))
            }
        }
        .padding(20)
        .champ(T.r)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Réglages").font(rounded(30, .bold))
                if !model.orgName.isEmpty {
                    Text("Poste géré par \(model.orgName)").font(rounded(15, .medium)).foregroundStyle(.white.opacity(0.92))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.header)
            Onglets(options: [("Général", 0), ("Connexion", 1)], selection: $tab)
                .padding(.horizontal, 24).padding(.top, 8)
            if tab == 1 {
                ScrollView { ConnexionTab().padding(24).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Prénom", text: $name, prompt: "Votre prénom")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { model.realtimeProtection }, set: { model.setRealtimeProtection($0) })) {
                            Text("Protection en temps réel").font(rounded(22, .semibold))
                        }
                        .toggleStyle(.switch).tint(T.accent)
                        Text(model.realtimeProtection
                             ? "Activée. PapAI repère les arnaques à partir des applications ouvertes, du titre de la fenêtre et du site visité. Jamais l'écran, jamais vos mots de passe."
                             : "Coupée. Rien ne part de cet ordinateur en dehors d'une assistance, et les arnaques ne sont plus repérées.")
                            .font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mon support").font(rounded(22, .semibold))
                        if model.helpers.isEmpty {
                            Text("Reliez le téléphone de votre support à cet ordinateur : QR code, code à 6 chiffres ou lien à envoyer.")
                                .font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                            // Le bouton n'existe que tant qu'aucun support n'est relié : un seul à la fois.
                            Button("Ajouter un support") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.openSupportPairing() }
                            }.buttonStyle(PillStyle(height: 54, icone: "plus.circle"))
                        } else {
                            // Le support se gère depuis son téléphone : ici on l'affiche seulement.
                            ForEach(model.helpers) { h in
                                HStack(spacing: 14) {
                                    Image(systemName: "person.fill.checkmark")
                                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 46, height: 46).background(Circle().fill(T.accent))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Support IT").font(rounded(20, .semibold))
                                        Text(h.online ? "En ligne, relié à cet ordinateur" : "Relié à cet ordinateur")
                                            .font(rounded(15)).foregroundStyle(h.online ? T.leaf : T.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.line)))
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.buttonStyle(PillStyle(filled: false, height: 50))
                Button("Enregistrer") {
                    // L'adresse du serveur ne se règle plus ici : elle vient de l'installation.
                    model.setFirstName(name)
                    dismiss()
                }.buttonStyle(PillStyle(height: 50, icone: "checkmark.circle"))
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(T.ink)
        .frame(width: 560, height: 640).background(T.bg)
        .onAppear { name = model.firstName }
        .onDisappear { model.stopPairing() }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(rounded(15, .semibold)).foregroundStyle(T.muted)
            TextField(prompt, text: text).textFieldStyle(.plain).font(rounded(18))
                .padding(16).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.line)))
        }
    }
}

/// Onglet « Connexion » des Réglages : de quoi relier le téléphone du support
/// à cet ordinateur, sans passer par un autre écran. QR code, code à 6 chiffres
/// et lien à envoyer, valables 24 heures.
struct ConnexionTab: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Relier un support").font(rounded(22, .semibold))
            Text("Votre support scanne le QR code avec son téléphone, ou tape le code. S'il n'est pas à côté de vous, envoyez-lui le lien.")
                .font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if let h = model.helpers.first {
                Label(h.online ? "Un support est relié et en ligne" : "Un support est déjà relié à cet ordinateur",
                      systemImage: "person.fill.checkmark")
                    .font(rounded(16, .semibold)).foregroundStyle(h.online ? T.leaf : T.muted)
            }
            if let added = model.pairAdded {
                Label("\(added) est maintenant relié.", systemImage: "checkmark.circle.fill")
                    .font(rounded(17, .semibold)).foregroundStyle(T.leaf)
            }
            if !model.connected {
                Text("Connexion au serveur en cours…").font(rounded(16)).foregroundStyle(T.muted)
            } else if model.pairCode == nil && model.pairURL == nil {
                Button("Afficher le code de connexion") { model.startPairing() }
                    .buttonStyle(PillStyle(height: 54, icone: "qrcode"))
            } else {
                card
            }
        }
        .onAppear { if model.connected && model.pairCode == nil && model.pairURL == nil { model.startPairing() } }
        .onChange(of: model.connected) { _, ok in
            if ok && model.pairCode == nil && model.pairURL == nil { model.startPairing() }
        }
    }

    private var card: some View {
        let url = model.pairURL ?? ""
        let qrText = model.pairAppURL ?? url
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                if let qr = QRCode.image(qrText) {
                    Image(nsImage: qr).interpolation(.none).resizable()
                        .frame(width: 150, height: 150)
                        .accessibilityLabel("QR code à scanner par votre support")
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let code = model.pairCode {
                        Text("Code").font(rounded(15, .semibold)).foregroundStyle(T.muted)
                        Text(code.prefix(3) + " " + code.suffix(3))
                            .font(rounded(34, .semibold)).monospacedDigit().tracking(2)
                            .textSelection(.enabled)
                    }
                    Text(model.pairLong ? "Valable 24 heures" : "Valable 10 minutes")
                        .font(rounded(15)).foregroundStyle(T.muted)
                }
            }
            if !url.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lien").font(rounded(15, .semibold)).foregroundStyle(T.muted)
                    Text(url).font(rounded(14)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(url, forType: .string)
                    } label: {
                        Label(copied ? "Lien copié" : "Copier le lien", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillStyle(filled: false, height: 50))
                    if let link = URL(string: url) {
                        ShareLink(item: link, subject: Text("Rejoignez-moi sur PapAI"),
                                  message: Text(model.invitationText)) {
                            Label("Envoyer", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillStyle(height: 50))
                    }
                }
            }
            Button("Nouveau code") { copied = false; model.startPairing() }
                .buttonStyle(.plain).font(rounded(15, .semibold)).foregroundStyle(T.muted)
        }
        .padding(18)
        .champ(T.r)
        .onChange(of: url) { copied = false }
    }
}
