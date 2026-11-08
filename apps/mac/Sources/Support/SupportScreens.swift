import SwiftUI

// Les écrans du support, un par état de l'assistance (`HelperModel.screen`),
// repris de l'app iPhone et mis en page pour une fenêtre Mac.

// MARK: - Rien à signaler

struct SupportIdle: View {
    let model: HelperModel
    var body: some View {
        Panneau {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.connected {
                        Text("Rien à signaler pour \(model.senior)").font(rounded(30, .bold))
                        Text("Vous serez prévenu dès qu’une demande d’aide arrive, même si PapAI est en arrière-plan.")
                            .font(rounded(17, .medium)).opacity(0.92)
                    } else {
                        Text("Connexion interrompue").font(rounded(30, .bold))
                        Text("Impossible de recevoir les demandes d’aide de \(model.senior) pour le moment.")
                            .font(rounded(17, .medium)).opacity(0.92)
                    }
                }
                Spacer(minLength: 0)
                if model.connected {
                    Mascotte(humeur: .calme, anime: false).frame(width: 64, height: 64)
                }
            }
        } corps: {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if let online = model.seniorOnline {
                        Pastille(texte: online ? "L’ordinateur de \(model.senior) est allumé" : "L’ordinateur de \(model.senior) est éteint",
                                 icone: online ? "desktopcomputer" : "moon.zzz", ton: online ? .vert : .gris, taille: 15)
                    }
                    if let live = model.liveDictation {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(model.seniorTitle) est en train de parler", systemImage: "waveform")
                                .font(rounded(14, .semibold)).foregroundStyle(T.leaf)
                            Text("« \(live) »").font(rounded(22, .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.mint))
                    }
                    if let a = model.lastAlert {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.title).font(rounded(17, .semibold))
                            Text(a.detail).font(rounded(15)).foregroundStyle(T.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.field))
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").font(rounded(18, .semibold)).foregroundStyle(T.accent)
                        Text("Derniers automates").font(rounded(20, .bold))
                        Spacer()
                        Button("Actualiser") { Task { await model.loadLessons() } }
                            .buttonStyle(.plain).font(rounded(14, .semibold)).foregroundStyle(T.leaf)
                    }
                    if model.lessons.isEmpty {
                        Text("Aucun automate pour l’instant. Après une assistance, « Garder comme automate » permet à \(model.senior) de la relancer d’un clic.")
                            .font(rounded(16)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.lessons.prefix(8).enumerated()), id: \.element.id) { i, l in
                                if i > 0 { Rectangle().fill(T.line).frame(height: 1).padding(.leading, 58) }
                                HStack(spacing: 14) {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(T.leaf)
                                        .frame(width: 38, height: 38)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(T.mint))
                                    Text(l.title).font(rounded(17, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                    Pastille(texte: "\(l.steps?.count ?? 0) étapes", ton: .gris, taille: 13)
                                }
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - En attente

struct SupportWaiting: View {
    let model: HelperModel
    let text: String
    var body: some View {
        Panneau { RequestHead(model: model) } corps: {
            VStack(spacing: 18) {
                Spacer()
                Mascotte(humeur: .reflechit, anime: false).frame(width: 88, height: 88)
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(text).font(rounded(20, .semibold))
                }
                Text("Le plan de Holo s’affichera ici. Rien ne se fait sans votre accord.")
                    .font(rounded(16)).foregroundStyle(T.muted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Plan à valider

struct SupportApproval: View {
    @Bindable var model: HelperModel
    @State private var refine = false
    @State private var confirmRefuse = false
    @State private var zoom = false
    @State private var editing: EditedStepMac?

    var body: some View {
        Panneau { RequestHead(model: model) } corps: {
            VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Écran de \(model.senior)").font(rounded(15, .semibold)).foregroundStyle(T.muted)
                    Button { zoom = true } label: { SupportCapture(model: model) }
                        .buttonStyle(.plain).disabled(model.frame == nil)
                        .accessibilityLabel("Agrandir la dernière capture")
                    if model.frame != nil {
                        Text("Cliquez sur la capture pour l’agrandir.").font(rounded(13)).foregroundStyle(T.muted)
                    }
                }
                .frame(width: 250)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Plan proposé par Holo").font(rounded(21, .bold))
                        Spacer()
                        Pastille(texte: "\(model.plan.count) étape\(model.plan.count > 1 ? "s" : "")", ton: .bleu, taille: 14)
                    }
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(model.plan.enumerated()), id: \.offset) { i, raw in
                                HStack(alignment: .top) {
                                    StepRow(index: i, raw: raw)
                                    Button { edit(i, raw) } label: {
                                        Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.leaf)
                                            .frame(width: 38, height: 38).background(Circle().fill(T.mint))
                                    }
                                    .buttonStyle(.plain).disabled(model.planBusy)
                                    .help("Modifier cette étape")
                                    .accessibilityLabel("Modifier l’étape \(i + 1)")
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line)))
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
                    HStack(spacing: 12) {
                        Button { model.approvePlan() } label: {
                            HStack(spacing: 10) {
                                if model.planBusy { ProgressView().controlSize(.small).tint(.white) }
                                Text("Valider le plan")
                            }
                        }
                        .buttonStyle(PillStyle(height: 56, icone: model.planBusy ? nil : "checkmark"))
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.planBusy)
                        Button("Préciser") { refine = true }
                            .buttonStyle(supportSecondary(56, icone: "pencil")).disabled(model.planBusy)
                        Button("Refuser") { confirmRefuse = true }
                            .buttonStyle(supportSecondary(56, icone: "xmark")).disabled(model.planBusy)
                        Spacer(minLength: 0)
                        Text("Rien ne se fait sans votre accord.").font(rounded(14)).foregroundStyle(T.muted)
                    }
            }
        }
        .sheet(isPresented: $refine) { SupportRefineSheet(model: model) }
        .sheet(item: $editing) { e in SupportStepEditSheet(model: model, step: e) }
        .sheet(isPresented: $zoom) { SupportZoom(image: model.frame) }
        .confirmationDialog("Refuser ce plan ?", isPresented: $confirmRefuse) {
            Button("Refuser le plan", role: .destructive) { model.refusePlan() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Rien ne sera fait, et l’ordinateur de \(model.senior) l’indiquera.") }
    }

    private func edit(_ i: Int, _ raw: String) {
        guard !model.planBusy else { return }
        editing = EditedStepMac(index: i, text: raw, plan: model.plan)
    }
}

/// Une étape à modifier : la consigne envoyée à Holo est celle de l'iPhone (`refine_plan`).
struct EditedStepMac: Identifiable {
    let index: Int
    let text: String
    let plan: [String]
    var id: Int { index }
    func instruction(_ new: String) -> String {
        let current = plan.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ; ")
        return "Étape \(index + 1) : remplacer « \(text) » par « \(new) ». "
            + "Plan actuel : \(current). Garde les autres étapes telles quelles et propose le plan corrigé."
    }
}

// MARK: - Holo agit

struct SupportActive: View {
    let model: HelperModel
    private var caption: String {
        if model.seniorPaused { return "Aide en pause" }
        if let n = model.planStep, !model.plan.isEmpty { return "Étape \(min(n, model.plan.count)) sur \(model.plan.count)" }
        return "Holo agit"
    }
    var body: some View {
        Panneau {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if !model.seniorPaused { ProgressView().controlSize(.small).tint(.white) }
                    Text(caption).font(rounded(15, .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
                Text(model.webLive
                     ? "Holo travaille dans \(model.webBrowserTitle)"
                     : model.seniorPaused
                         ? "\(model.seniorTitle) a mis l’aide en pause. Holo attend la reprise."
                         : (model.doing ?? "Holo regarde l’écran de \(model.senior)…"))
                    .font(rounded(24, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: model.doing)
            }
        } corps: {
            HStack(alignment: .top, spacing: 26) {
                SupportCapture(model: model).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 16) {
                    if !model.task.isEmpty {
                        Text("« \(model.task) »").font(rounded(16, .semibold)).foregroundStyle(T.muted)
                    }
                    ScrollView { SupportPlanProgress(plan: model.plan, current: model.planStep) }
                    Button(model.pausing ? "Pause demandée…" : "Mettre en pause") { model.pause() }
                        .buttonStyle(supportSecondary(52, icone: "pause.fill")).disabled(model.pausing)
                }
                .frame(width: 290)
            }
        }
    }
}

// MARK: - Holo a besoin du support

struct SupportHelperView: View {
    @Bindable var model: HelperModel
    @State private var reply = ""
    @State private var dictation = Dictation()

    private var headline: String {
        if model.webLive { return "Holo a une question" }
        if model.questionToSenior { return "Question posée à \(model.senior) sur son écran. Vous pouvez aussi répondre." }
        return "\(model.seniorTitle) a besoin de vous"
    }

    var body: some View {
        Panneau {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline).font(rounded(15, .semibold)).opacity(0.92)
                Text(model.question?.text ?? "Holo attend votre aide.").font(rounded(26, .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } corps: {
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.webLive {
                        Text("\(model.webBrowserTitle) : Holo agit seulement dans le navigateur. Répondez à ses questions ici.")
                            .font(rounded(14)).foregroundStyle(T.muted)
                    }
                    SupportCapture(model: model, aimable: !model.webLive)
                }
                .frame(maxWidth: .infinity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.aiming { aimPanel } else {
                            answerPanel
                            if !model.webLive { handPanel }
                        }
                    }
                }
                .frame(width: 340)
            }
        }
        .onDisappear { dictation.stop() }
    }

    @ViewBuilder private var answerPanel: some View {
        if let q = model.question, !q.options.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(q.options, id: \.self) { o in
                    Button { model.answer(o) } label: {
                        Text(o).font(rounded(16, .semibold)).foregroundStyle(T.leaf)
                            .padding(.horizontal, 16).frame(minHeight: 42)
                            .background(Capsule().fill(T.mint))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        SupportDictationField(text: $reply, placeholder: "Votre réponse à Holo…", dictation: dictation, httpBase: model.baseHTTP)
        HStack(spacing: 10) {
            Button("Envoyer") { sendReply() }
                .buttonStyle(PillStyle(height: 50, icone: "arrow.up"))
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dictation.phase != .idle)
            if !reply.isEmpty {
                Button("Effacer") { reply = "" }.buttonStyle(supportSecondary(50))
            }
        }
    }

    private var handPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(T.line).frame(height: 1).padding(.vertical, 4)
            Button("Prendre la main") { model.setAiming(true) }
                .buttonStyle(supportSecondary(50, icone: "cursorarrow.click"))
            Text("Vous pouvez cliquer vous-même sur l’écran de \(model.senior).")
                .font(rounded(14)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aimPanel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let age = model.frameAt.map { ctx.date.timeIntervalSince($0) } ?? .infinity
            let stale = age >= HelperModel.frameTTL
            VStack(alignment: .leading, spacing: 14) {
                Text(model.target == nil
                     ? "Cliquez sur l’écran de \(model.senior) à l’endroit où il faut cliquer."
                     : "Ajustez si besoin, puis confirmez.")
                    .font(rounded(18, .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(stale ? "Cette capture est trop ancienne : l’écran a pu changer."
                     : "Capture d’il y a \(Int(age)) s, valable encore \(Int(HelperModel.frameTTL) - Int(age)) s.")
                    .font(rounded(14)).foregroundStyle(stale ? T.ink : T.muted)
                if stale {
                    Button("Rafraîchir") { model.refresh() }.buttonStyle(.plain)
                        .font(rounded(15, .semibold)).foregroundStyle(T.leaf)
                }
                Button(model.sending ? "Envoi…" : "Cliquer ici") { model.confirmClick() }
                    .buttonStyle(PillStyle(height: 52, icone: "cursorarrow.rays"))
                    .disabled(model.target == nil || stale || model.sending)
                Button("Annuler") { model.setAiming(false) }.buttonStyle(supportSecondary(48))
            }
        }
    }

    private func sendReply() {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        dictation.stop()
        if !t.isEmpty { model.answer(t); reply = "" }
    }
}

// MARK: - Terminé

struct SupportDone: View {
    @Bindable var model: HelperModel
    @State private var zoom: PlatformImageBox?

    var body: some View {
        Panneau {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Terminé", systemImage: "checkmark.circle.fill").font(rounded(15, .semibold)).opacity(0.92)
                    if !model.task.isEmpty { Text("« \(model.task) »").font(rounded(17, .medium)).opacity(0.92) }
                    Text(model.doneAnswer ?? "Holo a terminé.").font(rounded(26, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Mascotte(humeur: .bravo, anime: false).frame(width: 72, height: 72)
            }
        } corps: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let saved = model.savedTitle {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 34, height: 34).background(Circle().fill(Color(hex: 0x12A15E)))
                            Text("Automate « \(saved) » enregistré. \(model.seniorTitle) le retrouve dans « Mes automates ».")
                                .font(rounded(18, .semibold))
                        }
                    } else if model.hasDraft {
                        draft
                    } else {
                        Button { model.requestLesson() } label: {
                            HStack(spacing: 10) {
                                if model.lessonBusy { ProgressView().controlSize(.small).tint(.white) }
                                Text(model.lessonBusy ? "Rédaction en cours…" : "Garder comme automate")
                            }
                        }
                        .buttonStyle(PillStyle(height: 56, icone: model.lessonBusy ? nil : "square.and.arrow.down"))
                        .disabled(model.lessonBusy)
                        Text("Holo transforme cette assistance en automate que \(model.senior) pourra relancer sans aide.")
                            .font(rounded(15)).foregroundStyle(T.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $zoom) { z in SupportZoom(image: z.image) }
    }

    private var draft: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Brouillon de l’automate").font(rounded(20, .bold))
            TextField("Titre", text: $model.draftTitle).textFieldStyle(.plain)
                .font(rounded(19, .semibold)).padding(14).champ()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder").font(.system(size: 16, weight: .semibold)).foregroundStyle(T.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("La tuile ouvrira").font(rounded(13, .semibold)).foregroundStyle(T.muted)
                    Text(model.draftTarget ?? "Aucun dossier : \(model.senior) aura seulement les étapes.")
                        .font(rounded(16, .semibold))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach($model.draftSteps) { $s in
                    VStack(alignment: .leading, spacing: 10) {
                        Pastille(texte: "Étape \((model.draftSteps.firstIndex { $0.id == s.id } ?? 0) + 1)", ton: .bleu, taille: 13)
                        TextField("Instruction", text: $s.instruction, axis: .vertical).textFieldStyle(.plain)
                            .font(rounded(16))
                        if let c = s.checkpoint {
                            Text("\(model.seniorTitle) doit voir : \(c)").font(rounded(13)).foregroundStyle(T.muted)
                        }
                        if let p = s.preview {
                            Button { zoom = PlatformImageBox(image: p) } label: {
                                Image(platformImage: p).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Agrandir la capture")
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line)))
                }
            }
            Button("Valider l’automate") { model.approveLesson() }.buttonStyle(PillStyle(height: 54, icone: "checkmark"))
        }
    }
}

struct PlatformImageBox: Identifiable {
    let id = UUID()
    let image: PlatformImage
}

// MARK: - Arrêt

struct SupportStopped: View {
    let model: HelperModel
    var body: some View {
        Panneau(alerte: model.stoppedBy == "gardien") {
            Text(model.stoppedBy == "gardien" ? "PapAI a arrêté l'assistance : démarche suspecte"
                 : model.iRefusedPlan ? "Vous avez refusé le plan" : "\(model.seniorTitle) a arrêté l’assistance")
                .font(rounded(28, .bold))
        } corps: {
            VStack(spacing: 14) {
                Spacer()
                if model.stoppedBy == "gardien" {
                    Image(systemName: "exclamationmark.shield.fill").font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(T.danger).frame(width: 72, height: 72).background(Circle().fill(T.danger.opacity(0.1)))
                } else {
                    Mascotte(humeur: .calme, anime: false).frame(width: 80, height: 80)
                }
                Text("L'assistance reste arrêtée. Toute nouvelle aide demande votre accord.")
                    .font(rounded(18)).foregroundStyle(T.muted)
                Text("Appelez \(model.senior) à son numéro habituel.").font(rounded(20, .semibold))
                Spacer()
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Alerte du gardien

struct SupportGuardView: View {
    @Bindable var model: HelperModel
    @State private var confirmDismiss = false

    var body: some View {
        ZStack {
            T.ink.opacity(0.35).ignoresSafeArea()
            Panneau(alerte: true) {
                HStack(spacing: 16) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 26, weight: .semibold))
                        .frame(width: 58, height: 58).background(Circle().fill(.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.lastAlert?.title ?? "Démarche à vérifier").font(rounded(28, .bold))
                        Text("PapAI a arrêté l'assistance : démarche suspecte").font(rounded(17, .semibold)).opacity(0.95)
                    }
                }
            } corps: {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.guardTask.isEmpty {
                        Text("« \(model.guardTask) »").font(rounded(21, .semibold))
                    }
                    Text(instructions).font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    if model.guardAcknowledged {
                        Label("Un support a vu l'alerte et s'en occupe", systemImage: "checkmark.circle.fill")
                            .font(rounded(17, .semibold))
                    }
                    Spacer(minLength: 0)
                    if confirmDismiss {
                        Text("Vous connaissez cette démarche ? Cela ferme l'alerte, sans relancer l'assistance.")
                            .font(rounded(17))
                        HStack(spacing: 12) {
                            Button("Confirmer : c'est normal") { model.dismissGuardAlert() }
                                .buttonStyle(PillStyle(height: 54)).disabled(!model.connected)
                            Button("Retour") { confirmDismiss = false }.buttonStyle(supportSecondary(54))
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button("Je m'en occupe") { model.acknowledgeGuardAlert() }
                                .buttonStyle(PillStyle(height: 54))
                                .disabled(!model.connected || model.guardAcknowledged)
                            Button("C'est normal") { confirmDismiss = true }
                                .buttonStyle(supportSecondary(54)).disabled(!model.connected)
                        }
                    }
                    if !model.connected {
                        Text("Reconnectez-vous pour répondre à cette alerte.").font(rounded(15)).foregroundStyle(T.muted)
                    }
                }
            }
            .frame(width: 680, height: 520)
        }
    }

    private var instructions: String {
        let detail = model.lastAlert?.detail ?? ""
        guard !model.guardTask.isEmpty else { return detail }
        return detail.replacingOccurrences(of: "\nDemande : « \(model.guardTask) »", with: "")
    }
}
