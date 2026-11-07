import SwiftUI

/// Accueil : une barre pour demander (avec un petit micro) et les AutoMates.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var request = ""
    @State private var warning: String?
    @FocusState private var focused: Bool
    @State private var dictation = Dictation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var micro: MicPresence { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            accueil
            VStack(alignment: .leading, spacing: 10) {
                barre
                if let etat = etatDictee {
                    Text(etat).font(rounded(17, .semibold)).foregroundStyle(T.leaf)
                        .padding(.leading, 24)
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(rounded(17, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card))
                }
            }
            ScrollView(showsIndicators: false) {
                automates.padding(.bottom, 8)
            }
        }
        .foregroundStyle(T.ink)
        .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { ouvrirDemande() }
        .onChange(of: micro.demande) { _, _ in ouvrirDemande() }
        .onChange(of: dictation.message) { _, m in if let m { warning = m; dictation.message = nil } }
    }

    // MARK: Demande

    private var accueil: some View {
        HStack(alignment: .center, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                Mascotte(humeur: humeur).frame(width: Mascotte.Taille.accueil, height: Mascotte.Taille.accueil)
                Mascotte(humeur: humeur).frame(width: Mascotte.Taille.accueilReduite, height: Mascotte.Taille.accueilReduite)
            }
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.everyMinute) { ctx in
                    let hello = Greeting.word(at: ctx.date)
                    Text(model.firstName.isEmpty ? hello : "\(hello) \(model.firstName) !")
                        .font(rounded(34, .bold)).tracking(-0.6)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text("Que voulez-vous faire ?").font(rounded(19, .medium)).foregroundStyle(T.muted)
            }
        }
    }

    private var barre: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(rounded(20, .semibold)).foregroundStyle(T.muted)
                .accessibilityHidden(true)
            TextField(micro.microPresent ? "Écrivez ou dites ce que vous voulez faire" : "Écrivez ce que vous voulez faire",
                      text: $request)
                .textFieldStyle(.plain).font(rounded(20)).focused($focused)
                .focusEffectDisabled()
                .onSubmit(submit)
                .accessibilityLabel("Ma demande")
            if micro.microPresent { micButton }
            Button(action: submit) {
                Text("Envoyer").font(rounded(16, .semibold)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 20).frame(minHeight: 48)
                    .background(Capsule().fill(T.ink))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(dictation.phase != .idle)
        }
        .padding(.leading, 24).padding(.trailing, 10).padding(.vertical, 10)
        .frame(minHeight: 68)
        .background {
            // Bord dessiné par deux capsules pleines : un trait de Capsule laisse des traces sur les côtés.
            let actif = focused || dictation.phase == .listening
            ZStack {
                Capsule().fill(actif ? T.papaya : T.ink.opacity(0.14))
                Capsule().fill(T.card).padding(actif ? 2.5 : 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    /// Petit micro dans la barre : la même dictée qu'avant, juste plus discrète.
    private var micButton: some View {
        let listening = dictation.phase == .listening
        return Button(action: dicter) {
            ZStack {
                Circle().fill(listening ? T.accent : T.mint)
                    .scaleEffect(listening && !reduceMotion && pulse ? 1.08 : 1)
                if dictation.phase == .transcribing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(rounded(19, .semibold))
                        .foregroundStyle(listening ? .white : T.leaf)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(dictation.phase == .transcribing)
        .help(listening ? "Arrêter la dictée" : "Dicter ma demande")
        .accessibilityLabel(listening ? "Arrêter la dictée" : "Dicter ma demande")
        .onChange(of: listening) { _, on in
            if on, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            } else { withAnimation(.none) { pulse = false } }
        }
    }

    private var etatDictee: String? {
        switch dictation.phase {
        case .listening: "Je vous écoute… Touchez le carré quand vous avez fini."
        case .transcribing: "Je note…"
        case .idle: nil
        }
    }

    private var humeur: Mascotte.Humeur {
        switch dictation.phase {
        case .listening: .ecoute
        case .transcribing: .reflechit
        default: .joyeuse
        }
    }

    private func ouvrirDemande() {
        guard micro.demande else { return }
        micro.demande = false
        if micro.microPresent {
            if dictation.phase == .idle { dicter() }
        } else { focused = true }
    }

    private func dicter() {
        warning = nil
        let before = request.trimmingCharacters(in: .whitespacesAndNewlines)
        func joined(_ t: String) -> String { before.isEmpty ? t : before + " " + t }
        dictation.toggle(httpBase: model.httpBase, onLive: { t in
            // Les mots s'affichent pendant qu'elle parle, et partent chez l'aidant.
            request = joined(t)
            model.sendDictation(t)
        }) { text in
            request = joined(text)
            model.sendDictation(text, final: true)
            submit()
        }
    }

    private func submit() {
        guard dictation.phase == .idle else { return }
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { warning = "Dites en quelques mots ce que vous voulez faire."; focused = true; return }
        if !model.connected { warning = "Je ne joins pas \(model.helperName) pour le moment. Réessayez dans un instant."; return }
        warning = nil
        // L'accord de partage a été donné à l'inscription : la demande part directement.
        model.requestConsent(task: text)
        request = ""
    }

    // MARK: AutoMates

    /// Les automatismes enregistrés (`GET /lessons`), qui deviendront les fichiers `.papi`.
    private var automates: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let n = model.notice {
                Text(n).font(rounded(17, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.mint))
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(rounded(20, .semibold)).foregroundStyle(T.papaya)
                    .accessibilityHidden(true)
                Text("Mes AutoMates").font(rounded(22, .bold))
            }
            if model.lessons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aucun AutoMate pour l'instant.").font(rounded(18, .semibold))
                    Text("Un AutoMate est une tâche toute prête. Quand \(model.helperName) en enregistre une pour vous, elle apparaît ici et se lance d'un clic.")
                        .font(rounded(17)).foregroundStyle(T.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous)
                    .strokeBorder(T.muted.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], spacing: 12) {
                    ForEach(model.lessons) { l in tuile(l) }
                }
            }
        }
    }

    private func tuile(_ l: Lesson) -> some View {
        HStack(spacing: 10) {
            Button { model.runShortcut(l) } label: {
                HStack(spacing: 12) {
                    Circle().fill(T.mint).frame(width: 40, height: 40)
                        .overlay(Image(systemName: Shortcuts.symbol(for: l.shortcut?.folder))
                            .font(rounded(18)).foregroundStyle(T.accent))
                    Text(l.title).font(rounded(18, .semibold)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Lancer \(l.title)")
            if !(l.steps ?? []).isEmpty {
                Button { model.openLesson(l) } label: {
                    Text("Montrez-moi").font(rounded(15, .semibold)).foregroundStyle(T.leaf)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5).frame(minHeight: 44)
                        .background(Capsule().fill(T.mint))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}

/// « Bonsoir » à partir de 19 h et jusqu'à 5 h, « Bonjour » le reste du temps.
enum Greeting {
    static func word(at date: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: date)
        return (h >= 19 || h < 5) ? "Bonsoir" : "Bonjour"
    }
}
