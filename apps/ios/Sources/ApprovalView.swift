import SwiftUI

struct ApprovalView: View {
    @Bindable var model: HelperModel
    @State private var showRefine = false
    @State private var confirmRefuse = false
    @State private var zoom = false
    @State private var editing: EditedStep?

    var body: some View {
        // Une List (et non une ScrollView) pour le geste « glisser vers la gauche ».
        List {
            Group {
                RequestCard(model: model, onThumb: { zoom = true })
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 9, trailing: 20))
                HStack {
                    Text("Plan proposé par Holo").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                    Spacer()
                    Text("\(model.plan.count) étape\(model.plan.count > 1 ? "s" : "")")
                        .font(.system(size: 13)).foregroundStyle(Soin.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Soin.card, in: Capsule())
                }
                .listRowInsets(EdgeInsets(top: 9, leading: 22, bottom: 6, trailing: 22))
                ForEach(Array(model.plan.enumerated()), id: \.offset) { i, raw in
                    stepRow(i, raw)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { edit(i, raw) } label: { Label("Modifier", systemImage: "pencil") }
                                .tint(Soin.accent)
                        }
                        .accessibilityAction(named: "Modifier") { edit(i, raw) }
                }
                if !model.plan.isEmpty {
                    Label("Glissez une étape vers la gauche pour la modifier.", systemImage: "hand.draw")
                        .font(.system(size: 13)).foregroundStyle(Soin.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 20, trailing: 20))
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showRefine) { RefineSheet(model: model) }
        .sheet(item: $editing) { e in StepEditSheet(model: model, step: e) }
        .confirmationDialog("Refuser ce plan ?", isPresented: $confirmRefuse, titleVisibility: .visible) {
            Button("Refuser le plan", role: .destructive) { model.refusePlan() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Rien ne sera fait, et l’ordinateur de \(model.senior) l’indiquera.") }
        .fullScreenCover(isPresented: $zoom) { ZoomView(image: model.frame) }
    }

    private func edit(_ i: Int, _ raw: String) {
        guard !model.planBusy else { return }
        editing = EditedStep(index: i, text: raw)
    }

    private func stepRow(_ i: Int, _ raw: String) -> some View {
        let s = PlanStep(id: i, raw: raw)
        return HStack(spacing: 14) {
            Text("\(i + 1)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                .frame(width: 38, height: 38).background(Soin.bg, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                if let d = s.detail { Text(d).font(.system(size: 14)).foregroundStyle(Soin.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading).soinCard()
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button { model.approvePlan() } label: {
                    HStack(spacing: 10) {
                        if model.planBusy { ProgressView().tint(.white) } else { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)) }
                        Text("Valider le plan")
                    }
                }
                .buttonStyle(CapsuleButtonStyle()).disabled(model.planBusy)
                Button { showRefine = true } label: {
                    Image(systemName: "pencil").font(.system(size: 18)).foregroundStyle(Soin.ink)
                }
                .buttonStyle(RoundIconButtonStyle()).disabled(model.planBusy).accessibilityLabel("Préciser")
                Button { confirmRefuse = true } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .medium)).foregroundStyle(Soin.ink)
                }
                .buttonStyle(RoundIconButtonStyle()).disabled(model.planBusy).accessibilityLabel("Refuser")
            }
            Text("Rien ne se fait sans votre accord.").font(.system(size: 13)).foregroundStyle(Soin.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Soin.bg)
    }
}

struct EditedStep: Identifiable {
    let index: Int
    let text: String
    var id: Int { index }

    /// La consigne envoyée à Holo par `refine_plan`.
    func instruction(_ new: String) -> String {
        "Étape \(index + 1) : remplacer « \(text) » par « \(new) ». Garde les autres étapes et propose le plan corrigé."
    }
}

/// Champ de texte et gros micro : les mots dictés s'écrivent dans le champ, modifiables.
/// `replacing` : le texte de départ (étape à corriger) est remplacé par la dictée
/// tant qu'il n'a pas été retouché ; sinon la dictée s'ajoute à la suite.
struct DictationField: View {
    @Binding var text: String
    let placeholder: String
    let dictation: Dictation
    let endpoint: URL?
    var replacing: String?
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 14) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...6).focused(focused)
                .font(.system(size: 17)).padding(16).soinCard(radius: 18)
                .disabled(dictation.phase == .transcribing)
            BigMicButton(dictation: dictation) {
                focused.wrappedValue = false
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = (t.isEmpty || t == replacing) ? "" : t + " "
                dictation.toggle(endpoint: endpoint,
                                 onLive: { text = prefix + $0 },
                                 onText: { text = prefix + $0 })
            }
        }
    }
}

struct RefineSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dictation = Dictation()
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Préciser le plan").font(.system(size: 24, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Dites ou écrivez à Holo ce qu’il doit changer. Il proposera un nouveau plan.")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
            DictationField(text: $text, placeholder: "Par exemple : les photos sont dans Images > Noël 2025",
                           dictation: dictation, endpoint: model.transcribeURL, focused: $focused)
            Spacer(minLength: 0)
            Button("Envoyer à Holo") {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                dictation.cancel()
                if !t.isEmpty { model.refinePlan(t); dismiss() }
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dictation.phase != .idle)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dictation.phase != .idle ? 0.4 : 1)
        }
        .padding(24).background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onDisappear { dictation.cancel() }
    }
}

/// « Modifier » une étape : feuille préremplie, corrigée au clavier ou à la voix,
/// envoyée à Holo comme une précision (`refine_plan`). Holo repropose un plan,
/// que l'aidant valide comme d'habitude.
struct StepEditSheet: View {
    let model: HelperModel
    let step: EditedStep
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dictation = Dictation()
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Modifier l’étape \(step.index + 1)").font(.system(size: 24, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Corrigez le texte, ou dites la nouvelle étape. Holo proposera un nouveau plan, que vous validerez.")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
            DictationField(text: $text, placeholder: "La nouvelle étape", dictation: dictation,
                           endpoint: model.transcribeURL, replacing: step.text, focused: $focused)
            if trimmed != step.text {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avant").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.secondary)
                    Text(step.text).font(.system(size: 15)).foregroundStyle(Soin.secondary).strikethrough()
                }
                .padding(.horizontal, 4)
            }
            Spacer(minLength: 0)
            Button("Envoyer à Holo") {
                let t = trimmed
                dictation.cancel()
                guard !t.isEmpty, t != step.text else { return }
                model.refinePlan(step.instruction(t)); dismiss()
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(trimmed.isEmpty || trimmed == step.text || dictation.phase != .idle)
            .opacity(trimmed.isEmpty || trimmed == step.text || dictation.phase != .idle ? 0.4 : 1)
        }
        .padding(24).background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { text = step.text }
        .onDisappear { dictation.cancel() }
    }
}

struct ZoomView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Soin.ink.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: .infinity) }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                    .frame(width: 44, height: 44).background(Soin.card, in: Circle())
            }.padding(20).accessibilityLabel("Fermer")
        }.onTapGesture { dismiss() }
    }
}
