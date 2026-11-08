import SwiftUI

/// Feuille Mac : en-tête bleu, corps, barre de boutons en bas.
struct SupportSheet<Corps: View, Bas: View>: View {
    let titre: String
    var sousTitre: String? = nil
    var width: CGFloat = 640
    var height: CGFloat = 560
    @ViewBuilder var corps: Corps
    @ViewBuilder var bas: Bas

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(titre).font(rounded(28, .bold))
                if let sousTitre { Text(sousTitre).font(rounded(16, .medium)).opacity(0.92).fixedSize(horizontal: false, vertical: true) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { corps }
                    .padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack(spacing: 12) { bas }
                .padding(.horizontal, 26).padding(.vertical, 16)
        }
        .foregroundStyle(T.ink)
        .frame(width: width, height: height).background(T.bg)
    }
}

private func sheetLabel(_ s: String) -> some View {
    Text(s).font(rounded(14, .semibold)).foregroundStyle(T.muted)
}

// MARK: - Préciser, Modifier

struct SupportRefineSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dictation = Dictation()
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SupportSheet(titre: "Préciser le plan",
                     sousTitre: "Dites ou écrivez à Holo ce qu’il doit changer. Il proposera un nouveau plan.") {
            SupportDictationField(text: $text, placeholder: "Par exemple : le dossier est dans Documents > Comptabilité 2025",
                                  dictation: dictation, httpBase: model.baseHTTP)
        } bas: {
            Spacer()
            Button("Annuler") { dictation.stop(); dismiss() }
                .buttonStyle(supportSecondary(50)).keyboardShortcut(.cancelAction)
            Button("Envoyer à Holo") {
                let t = trimmed
                if !t.isEmpty { model.refinePlan(t); dismiss() }
            }
            .buttonStyle(PillStyle(height: 50, icone: "arrow.up"))
            .disabled(trimmed.isEmpty || dictation.phase != .idle)
        }
        .onDisappear { dictation.stop() }
    }
}

struct SupportStepEditSheet: View {
    let model: HelperModel
    let step: EditedStepMac
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dictation = Dictation()
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SupportSheet(titre: "Modifier l’étape \(step.index + 1)",
                     sousTitre: "Corrigez le texte, ou dites la nouvelle étape. Holo proposera un nouveau plan, que vous validerez.") {
            SupportDictationField(text: $text, placeholder: "La nouvelle étape", dictation: dictation,
                                  httpBase: model.baseHTTP, replacing: step.text)
            if trimmed != step.text {
                VStack(alignment: .leading, spacing: 4) {
                    sheetLabel("Avant")
                    Text(step.text).font(rounded(16)).foregroundStyle(T.muted).strikethrough()
                }
            }
        } bas: {
            Spacer()
            Button("Annuler") { dictation.stop(); dismiss() }
                .buttonStyle(supportSecondary(50)).keyboardShortcut(.cancelAction)
            Button("Envoyer à Holo") {
                let t = trimmed
                guard !t.isEmpty, t != step.text else { return }
                model.refinePlan(step.instruction(t)); dismiss()
            }
            .buttonStyle(PillStyle(height: 50, icone: "arrow.up"))
            .disabled(trimmed.isEmpty || trimmed == step.text || dictation.phase != .idle)
        }
        .onAppear { text = step.text }
        .onDisappear { dictation.stop() }
    }
}

// MARK: - Liaison

/// « Relier ce Mac » : code à 6 chiffres (ou lien d'invitation collé), prénom, lien avec la personne.
struct SupportPairSheet: View {
    @Bindable var model: HelperModel
    @State var link: PairLink
    @State private var name = ""
    @State private var relation = ""
    @State private var code = ""
    @State private var pasted = ""
    @State private var pastedError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if model.pairDone { done } else { form }
    }

    private var form: some View {
        SupportSheet(titre: "Relier ce Mac",
                     sousTitre: "Vous serez prévenu dès qu’une demande d’aide arrive sur l’ordinateur de l’utilisateur. Rien ne bouge sans votre accord.",
                     width: 680, height: 640) {
            if link.isManual {
                sheetLabel("Code affiché sur l’ordinateur de l’utilisateur")
                TextField("000000", text: $code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(10)
                    .multilineTextAlignment(.center)
                    .padding(16).champ(actif: code.count == 6)
                    .onChange(of: code) { _, v in
                        let f = String(v.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        if f != v { code = f }
                        if !f.isEmpty { model.pairNeedsNew = false }
                    }
                sheetLabel("Ou collez le lien d’invitation reçu")
                HStack(spacing: 10) {
                    TextField("https://…/p/123456 ou papai://pair?…", text: $pasted)
                        .textFieldStyle(.plain).font(rounded(16)).padding(14).champ()
                        .onSubmit(usePasted)
                    Button("Utiliser") { usePasted() }.buttonStyle(supportSecondary(48))
                        .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let pastedError {
                    Text(pastedError).font(rounded(14, .semibold)).foregroundStyle(T.danger)
                }
            } else {
                Pastille(texte: link.token != nil ? "Lien d’invitation reconnu" : "Code \(link.code ?? "") reconnu",
                         icone: "link", ton: .bleu, taille: 15)
            }
            sheetLabel("Votre prénom")
            TextField("Claire", text: $name).textFieldStyle(.plain).font(rounded(18)).padding(14).champ()
            if model.pairBusy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("En attente de l'accord sur l'ordinateur…").font(rounded(17, .semibold))
                }
                Text("Demandez à l’utilisateur d'appuyer sur Accepter sur son ordinateur (2 min).")
                    .font(rounded(16))
            }
            if let e = model.pairError {
                if model.pairRefused {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Demande refusée").font(rounded(20, .bold))
                        Text(verbatim: e).font(rounded(15))
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).carte()
                } else {
                    Text(verbatim: e).font(rounded(15, .semibold)).foregroundStyle(T.danger)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if link.isOfficial {
                    Text("Serveur PapAI officiel").font(rounded(17, .bold))
                } else {
                    Label("Serveur inconnu : ne continuez que si l’utilisateur vous a donné ce lien lui-même",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(rounded(17, .bold)).foregroundStyle(T.danger)
                }
                Text(link.host).font(rounded(13)).foregroundStyle(T.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(link.isOfficial ? T.mint : T.danger.opacity(0.08)))
        } bas: {
            Spacer()
            Button("Annuler") { dismiss() }.buttonStyle(supportSecondary(50))
                .keyboardShortcut(.cancelAction).disabled(model.pairBusy)
            Button {
                Task { await model.submitPair(link, code: code, name: name, relation: relation) }
            } label: {
                HStack(spacing: 8) {
                    if model.pairBusy { ProgressView().controlSize(.small).tint(.white) }
                    Text("Rejoindre")
                }
            }
            .buttonStyle(PillStyle(height: 50, icone: model.pairBusy ? nil : "link"))
            .keyboardShortcut(.defaultAction)
            .disabled(model.pairBusy || model.pairNeedsNew || (link.isManual && code.count != 6))
        }
        .onAppear { if name.isEmpty { name = model.helperName ?? "" } }
        .onChange(of: model.pairNeedsNew) { _, n in if n { code = "" } }
        .interactiveDismissDisabled(model.pairBusy)
    }

    private func usePasted() {
        let t = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un lien d'organisation (service IT) ajoute tous ses postes.
        if Orgs.parse(t, officialHost: PairServer.officialHost) != nil {
            Task { if await model.addOrg(t) { dismiss() } else { pastedError = model.orgError } }
            return
        }
        guard let l = PairLink.parse(t) else { pastedError = PairServer.refusal; return }
        pastedError = nil
        link = l
        if let c = l.code { code = c }
    }

    private var done: some View {
        SupportSheet(titre: "Vous êtes relié à \(model.senior)", width: 680, height: 420) {
            HStack(spacing: 16) {
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(T.leaf)
                    .frame(width: 72, height: 72).background(Circle().fill(T.mint))
                VStack(alignment: .leading, spacing: 8) {
                    if model.connected {
                        Text("Connecté. Vous serez prévenu dès qu’une demande d’aide arrive.").font(rounded(18, .semibold))
                    } else if let e = model.linkError {
                        Text(e).font(rounded(17, .semibold)).foregroundStyle(T.danger)
                    } else {
                        HStack { ProgressView().controlSize(.small); Text("Connexion au serveur…").font(rounded(17)) }
                    }
                    Text("Gardez PapAI ouvert sur ce Mac : les demandes s’affichent en notification.")
                        .font(rounded(15)).foregroundStyle(T.muted)
                }
            }
        } bas: {
            Spacer()
            Button("Terminer") { model.sheet = nil }.buttonStyle(PillStyle(height: 50)).keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Premier lancement du mode support

struct SupportWelcome: View {
    @Bindable var model: HelperModel
    @State private var pasted = ""
    @State private var error: String?

    var body: some View {
        Panneau {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relier PapAI à la personne que vous aidez").font(rounded(32, .bold))
                    Text("Vous recevrez ses demandes ici, validerez le plan de Holo et suivrez l’assistance en direct.")
                        .font(rounded(18, .medium)).opacity(0.92)
                }
                Spacer(minLength: 0)
                Mascotte(humeur: .joyeuse, anime: false).frame(width: 80, height: 80)
            }
        } corps: {
            HStack(alignment: .top, spacing: 34) {
                VStack(alignment: .leading, spacing: 16) {
                    etape(1, "Sur l’ordinateur de l’utilisateur, ouvrez Réglages › Mon support › Ajouter un support.")
                    etape(2, "Un code à 6 chiffres s’affiche, avec un QR code et un lien à envoyer.")
                    etape(3, "Tapez ce code ici, ou collez le lien reçu. L’utilisateur accepte sur son écran.")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    Button("Entrer le code à 6 chiffres") {
                        if let l = model.manualPairLink() { model.openPair(l) }
                    }
                    .buttonStyle(PillStyle(height: 58, icone: "number", plein: true))
                    Text("Ou collez le lien d’invitation, ou le lien d’organisation de votre service informatique")
                        .font(rounded(14, .semibold)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    TextField("https://…", text: $pasted).textFieldStyle(.plain).font(rounded(16)).padding(14).champ()
                        .onSubmit(open)
                    Button("Ouvrir le lien") { open() }.buttonStyle(supportSecondary(50, icone: "link"))
                        .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty || model.orgBusy)
                    if let error { Text(error).font(rounded(14, .semibold)).foregroundStyle(T.danger).fixedSize(horizontal: false, vertical: true) }
                    Button("Réglage à la main…") { model.sheet = .settings }
                        .buttonStyle(.plain).font(rounded(14, .medium)).foregroundStyle(T.muted)
                }
                .frame(width: 360)
            }
        }
    }

    private func etape(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(rounded(17, .bold)).foregroundStyle(T.leaf)
                .frame(width: 36, height: 36).background(Circle().fill(T.mint))
            Text(t).font(rounded(18)).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
    }

    private func open() {
        let t = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if Orgs.parse(t, officialHost: PairServer.officialHost) != nil {
            Task { if !(await model.addOrg(t)) { error = model.orgError } }
            return
        }
        guard let l = PairLink.parse(t) else { error = PairServer.refusal; return }
        error = nil
        model.openPair(l)
    }
}

// MARK: - Réglages

struct SupportSettings: View {
    @Bindable var model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var key = ""
    @State private var org = ""
    @State private var confirmRole = false

    var body: some View {
        SupportSheet(titre: "Réglages", sousTitre: model.helperName.map { "Support : \($0)" }, width: 640, height: 640) {
            Text("Liaison").font(rounded(20, .bold))
            Text("Le plus simple : tapez le code à 6 chiffres affiché sur l’ordinateur de \(model.senior) (Mon support › Ajouter un support).")
                .font(rounded(15)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if let l = model.manualPairLink() {
                Button("Entrer le code à 6 chiffres") { model.openPair(l) }.buttonStyle(PillStyle(height: 50, icone: "number"))
            }
            Text("Service informatique").font(rounded(20, .bold)).padding(.top, 6)
            Text("Collez le lien d’organisation donné par l’IT : tous les postes s’ajoutent, sans code.")
                .font(rounded(15)).foregroundStyle(T.muted)
            HStack(spacing: 10) {
                TextField("https://…/o/sup-…", text: $org).textFieldStyle(.plain).font(rounded(16)).padding(14).champ()
                Button(model.orgBusy ? "Ajout…" : "Ajouter les postes") {
                    Task { if await model.addOrg(org) { dismiss() } }
                }
                .buttonStyle(supportSecondary(48))
                .disabled(org.trimmingCharacters(in: .whitespaces).isEmpty || model.orgBusy)
            }
            if let e = model.orgError { Text(e).font(rounded(14, .semibold)).foregroundStyle(T.danger) }
            Text("À la main").font(rounded(20, .bold)).padding(.top, 6)
            sheetLabel("Adresse du serveur")
            TextField("https://…/k/<clé de l'espace>", text: $server).textFieldStyle(.plain).font(rounded(16)).padding(14).champ()
            sheetLabel("Clé support")
            TextField("demo", text: $key).textFieldStyle(.plain).font(rounded(16)).padding(14).champ()
            HStack(spacing: 8) {
                Circle().fill(model.connected ? Color(hex: 0x12A15E) : (model.linkError == nil ? T.muted : T.danger))
                    .frame(width: 8, height: 8)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(model.isConfigured ? SupportConnection.line(model, now: ctx.date) : "Non configuré")
                        .font(rounded(14)).foregroundStyle(T.muted)
                }
            }
            if let g = model.lastGood, g.server != model.serverURL || g.key != model.helperKey {
                Button("Revenir au dernier réglage qui marchait") {
                    server = g.server; key = g.key
                    model.applySettings(server: g.server, key: g.key)
                }
                .buttonStyle(.plain).font(rounded(15, .semibold)).foregroundStyle(T.leaf)
            }
            if let e = model.pairError { Text(e).font(rounded(14, .semibold)).foregroundStyle(T.danger) }
            HStack(spacing: 10) {
                Button("Enregistrer et se connecter") {
                    if model.applySettings(server: server, key: key) { dismiss() }
                }
                .buttonStyle(PillStyle(height: 48))
                .disabled(server.trimmingCharacters(in: .whitespaces).isEmpty || key.trimmingCharacters(in: .whitespaces).isEmpty)
                if model.isConfigured {
                    Button("Réessayer maintenant") { model.reconnect() }.buttonStyle(supportSecondary(48))
                }
            }
        } bas: {
            Button("Changer de rôle") { confirmRole = true }
                .buttonStyle(.plain).font(rounded(15, .medium)).foregroundStyle(T.muted)
                .confirmationDialog("Changer de rôle ?", isPresented: $confirmRole) {
                    Button("Changer et relancer PapAI") { AppRole.forgetAndRelaunch() }
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("PapAI se relance et vous demande si vous vous faites aider ou si vous aidez quelqu'un. Vos liaisons sont gardées.")
                }
            Spacer()
            Button("Fermer") { dismiss() }.buttonStyle(PillStyle(height: 50)).keyboardShortcut(.cancelAction)
        }
        .onAppear { server = model.serverURL; key = model.helperKey }
    }
}
