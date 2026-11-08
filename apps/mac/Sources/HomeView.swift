import SwiftUI

/// Accueil : à gauche (60 %) une barre pour demander, avec un petit micro, puis
/// les automates ; à droite (40 %) les applications récentes.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var request = ""
    @State private var warning: String?
    @State private var trouves: [Lesson] = []
    @State private var prepare = false
    @State private var proposition: PropositionAutomate?
    @State private var question: QuestionHolo?
    @FocusState private var focused: Bool
    @State private var dictation = Dictation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var micro: MicPresence { .shared }
    private var usage: AppUsage { .shared }

    var body: some View {
        GeometryReader { geo in
            let place = geo.size.width - Self.ecart
            // 60 / 40, sans jamais couper le texte de la barre ; trop étroit, la droite passe dessous.
            let gauche = max(place * 0.6, Self.gaucheMin * CGFloat(TextScale.current))
            let droite = place - gauche
            let deux = droite >= Self.droiteMin
            VStack(alignment: .leading, spacing: 24) {
                // En-tête bleu sur toute la largeur ; la barre de demande garde la largeur de la colonne gauche.
                // L'encadré bleu (bonjour + demande) reste sur l'onglet Accueil seulement.
                if model.homeTab == 0 { enTete(barre: deux ? gauche - Self.marge : nil) }
                if model.homeTab == 2 {
                    UserTickets().padding(.bottom, 24).frame(maxHeight: .infinity, alignment: .top)
                } else if model.homeTab == 1 {
                    automates(titre: false, tous: true).padding(.bottom, 24)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if deux {
                    // Les deux colonnes partent de la même ligne : titres de section alignés, contenu en haut.
                    HStack(alignment: .top, spacing: Self.ecart) {
                        // Seule la liste défile : le titre de section reste en place.
                        VStack(alignment: .leading, spacing: 14) {
                            titreSection("sparkles", "Derniers automates")
                            automates(titre: false).padding(.bottom, 24)
                        }
                        .frame(width: gauche)
                        VStack(alignment: .leading, spacing: 14) {
                            titreSection("clock.arrow.circlepath", "Applications récentes")
                            applications(titre: false).padding(.bottom, 24)
                        }
                        .frame(width: droite)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            automates()
                            applications()
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            // Laisse respirer les ombres des cartes sans décaler les colonnes.
            .scrollClipDisabled()
        }
        .foregroundStyle(T.ink)
        .onAppear { ouvrirDemande() }
        .onChange(of: micro.demande) { _, _ in ouvrirDemande() }
        .onChange(of: dictation.message) { _, m in if let m { warning = m; dictation.message = nil } }
    }

    private static let droiteMin: CGFloat = 280
    /// 540 pt de barre + la marge de l'en-tête bleu, pour ne pas couper son texte.
    private static let gaucheMin: CGFloat = 540 + marge + 22
    private static let ecart: CGFloat = 24
    /// Marge intérieure de l'en-tête bleu.
    private static let marge: CGFloat = 28

    /// L'en-tête de l'accueil, comme « My ticket » : dégradé bleu, salutation en
    /// blanc et barre de demande intégrée.
    private func enTete(barre largeur: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            accueil
            VStack(alignment: .leading, spacing: 10) {
                barre.frame(maxWidth: largeur ?? .infinity)
                if let etat = etatDictee {
                    Text(etat).font(rounded(17, .semibold)).foregroundStyle(.white)
                        .padding(.leading, 18)
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(rounded(17, .semibold)).foregroundStyle(T.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                }
                if !trouves.isEmpty || prepare || proposition != nil || question != nil {
                    ResultatsRecherche(trouves: trouves, prepare: prepare, proposition: proposition, fermer: fermerRecherche,
                                       question: question, repondre: preciser)
                        .frame(maxWidth: largeur ?? .infinity)
                }
                if let q = model.queued, !model.queuedShown {
                    Button { model.queuedShown = true } label: {
                        Label(q.rdv.map { "Demande n° \(q.number) · rendez-vous \(rdvText($0))" } ?? "Demande n° \(q.number) en attente",
                              systemImage: "person.wave.2.fill")
                            .font(rounded(17, .semibold)).foregroundStyle(Pastille.Ton.orange.texte)
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(Capsule().fill(Pastille.Ton.orange.fond))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(Self.marge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.header)
                .shadow(color: T.accent.opacity(0.28), radius: 20, y: 10)
        }
    }

    /// Titre de section, identique dans les deux colonnes pour qu'ils tombent sur la même ligne.
    private func titreSection(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(rounded(20, .semibold)).foregroundStyle(T.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text).font(rounded(22, .bold))
        }
        .frame(minHeight: 32)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Demande

    private var accueil: some View {
        HStack(alignment: .center, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                Mascotte(humeur: humeur).frame(width: Mascotte.Taille.accueil, height: Mascotte.Taille.accueil)
                Mascotte(humeur: humeur).frame(width: Mascotte.Taille.accueilReduite, height: Mascotte.Taille.accueilReduite)
            }
            .padding(6)
            .background(Circle().fill(.white.opacity(0.92)))
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.everyMinute) { ctx in
                    let hello = Greeting.word(at: ctx.date)
                    Text(model.firstName.isEmpty ? hello : "\(hello) \(model.firstName) !")
                        .font(rounded(34, .bold)).tracking(-0.6)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text("Que voulez-vous faire ?").font(rounded(19, .medium)).foregroundStyle(.white.opacity(0.92))
            }
            .foregroundStyle(.white)
        }
    }

    private var barre: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(rounded(16, .semibold)).foregroundStyle(T.muted)
                .accessibilityHidden(true)
            TextField(micro.microPresent ? "Écrivez ou dites ce que vous voulez faire" : "Écrivez ce que vous voulez faire",
                      text: $request)
                .textFieldStyle(.plain).font(rounded(18)).focused($focused)
                .focusEffectDisabled()
                .onSubmit(submit)
                .accessibilityLabel("Ma demande")
            if micro.microPresent { micButton }
            Button(action: submit) {
                Text("Envoyer").font(rounded(16, .semibold)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Capsule().fill(T.primary).shadow(color: T.accent.opacity(0.3), radius: 8, y: 4))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(dictation.phase != .idle)
        }
        .padding(.leading, 18).padding(.trailing, 4).padding(.vertical, 4)
        .frame(minHeight: 52)
        .background {
            // Bord dessiné par deux capsules pleines : un trait de Capsule laisse des traces sur les côtés.
            let actif = focused || dictation.phase == .listening
            ZStack {
                Capsule().fill(actif ? Color(hex: 0xBFD5FF) : .white.opacity(0.0))
                Capsule().fill(T.card).padding(actif ? 3 : 0)
                    .shadow(color: T.ombre.opacity(0.18), radius: 10, y: 4)
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
                    .frame(width: 36, height: 36)
                    .scaleEffect(listening && !reduceMotion && pulse ? 1.08 : 1)
                if dictation.phase == .transcribing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(rounded(14, .semibold))
                        .foregroundStyle(listening ? .white : T.leaf)
                }
            }
            .frame(width: 44, height: 44)
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
        warning = nil
        proposition = nil
        question = nil
        // D'abord les automates de l'utilisateur : ils se lancent sans autorisation ni support en direct.
        trouves = RechercheAutomates.chercher(text, dans: model.lessons)
        if !trouves.isEmpty { return }
        // Rien ne correspond : Holo propose un plan, à envoyer au support IT dans un ticket.
        prepare = true
        Task {
            afficher(await PropositionAutomate.preparer(text, base: model.httpBase))
        }
    }

    /// Réponse de Holo : une question sur une demande floue, ou le plan à envoyer au support IT.
    private func afficher(_ r: Result<ReponseHolo, PropositionAutomate.Erreur>) {
        prepare = false
        switch r {
        case .success(.question(let q)): question = q; request = ""
        case .success(.plan(let p)): proposition = p; request = ""
        case .failure(let e): warning = e.texte
        }
    }

    /// Réponse de l'utilisateur à la question de Holo (nil : « Envoyer quand même »).
    private func preciser(_ reponse: String?) {
        guard let q = question else { return }
        question = nil
        prepare = true
        let precisions = reponse.map { q.precisions + [["q": q.question, "a": $0]] } ?? q.precisions
        Task {
            afficher(await PropositionAutomate.preparer(q.demande, precisions: precisions,
                                                        envoyerQuandMeme: reponse == nil, base: model.httpBase))
        }
    }

    private func fermerRecherche() {
        trouves = []; proposition = nil; prepare = false; question = nil
        request = ""
    }

    // MARK: Automates

    /// Les automates enregistrés (`GET /lessons`), qui deviendront les fichiers `.papi`.
    private func automates(titre: Bool = true, tous: Bool = false) -> some View {
        // Accueil : les 5 plus récents ; onglet Automates : tous.
        let liste = tous ? model.lessons : Array(model.lessons.prefix(Self.derniers))
        return VStack(alignment: .leading, spacing: 14) {
            if titre { titreSection("sparkles", "Derniers automates") }
            if let n = model.notice {
                Label(n, systemImage: "info.circle.fill").font(rounded(17, .medium))
                    .foregroundStyle(T.leaf)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.mint))
            }
            Group {
                if model.lessons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aucun automate pour l'instant.").font(rounded(18, .semibold))
                        Text("Un automate est une tâche toute prête. Quand \(model.helperName) en enregistre un pour vous, il apparaît ici et se lance d'un clic.")
                            .font(rounded(17)).foregroundStyle(T.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Deux colonnes : la carte blanche reste en place, seule la liste
                    // défile à l'intérieur et se coupe sur ses bords.
                    Defilant(actif: !titre || tous) {
                        VStack(spacing: 0) {
                            ForEach(liste) { l in
                                tuile(l)
                                if l.id != liste.last?.id {
                                    Rectangle().fill(T.line).frame(height: 1).padding(.leading, 64)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .carte(T.rBig)
            if !tous && model.lessons.count > Self.derniers {
                Button("Voir les \(model.lessons.count) automates") { model.homeTab = 1 }
                    .buttonStyle(.plain).font(rounded(16, .semibold)).foregroundStyle(T.leaf)
            }
        }
    }

    private static let derniers = 5

    private func tuile(_ l: Lesson) -> some View {
        HStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.18)) { model.docLesson = l } } label: {
                HStack(spacing: 12) {
                    Circle().fill(T.mint).frame(width: 40, height: 40)
                        .overlay(Image(systemName: l.shortcut == nil && !(l.actions ?? []).isEmpty ? "wand.and.stars" : Shortcuts.symbol(for: l.shortcut?.folder))
                            .font(rounded(18)).foregroundStyle(T.accent))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.title).font(rounded(18, .semibold)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let p = l.publisher, !p.isEmpty {
                            Text("Fourni par \(p)").font(rounded(14)).foregroundStyle(T.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Voir l'automate \(l.title)")
            // Le lancement ne se fait que par ce bouton ; la ligne ouvre la fiche.
            // Après un lancement, le résultat (« C'est fait ») prend sa place sur la ligne.
            if let st = model.runStatus, st.id == l.id {
                HStack(spacing: 6) {
                    if st.enCours { ProgressView().controlSize(.small) }
                    else { Image(systemName: st.text == "Arrêté" ? "stop.circle.fill" : "checkmark.circle.fill") }
                    Text(st.text)
                }
                .font(rounded(15, .semibold))
                .foregroundStyle(st.enCours ? T.leaf : st.text == "Arrêté" ? Pastille.Ton.gris.texte : Pastille.Ton.vert.texte)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(st.enCours ? T.mint : st.text == "Arrêté" ? Pastille.Ton.gris.fond : Pastille.Ton.vert.fond))
                .transition(.opacity)
                .accessibilityLabel(st.text)
            } else {
            Button { model.runShortcut(l) } label: {
                Text("Exécuter").font(rounded(15, .semibold)).foregroundStyle(T.leaf)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5).frame(minHeight: 44)
                    .background(Capsule().fill(T.mint))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Exécuter \(l.title)")
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.runStatus)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

extension HomeView {
    // MARK: Applications récentes

    /// Les 6 applications passées le plus récemment au premier plan, ouvertes d'un clic.
    fileprivate func applications(titre: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if titre { titreSection("clock.arrow.circlepath", "Applications récentes") }
            Defilant(actif: !titre) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(usage.recent) { app in
                    let name = app.name, bundle = app.bundle
                    Button { openApp(bundle) } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.field)
                                .frame(width: 72, height: 72)
                                .overlay(Image(nsImage: icon(bundle)).resizable().frame(width: 48, height: 48))
                            Text(name).font(rounded(16, .medium))
                                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Ouvrir \(name)")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 18)
            }
            .carte(T.rBig)
        }
    }

    private func openApp(_ bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            model.showNotice("Cette application n'est pas disponible sur cet ordinateur.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func icon(_ bundle: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
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

/// Une liste qui défile à l'intérieur de sa carte quand la place manque ; sinon
/// la carte épouse son contenu. La carte elle-même ne bouge jamais.
struct Defilant<Contenu: View>: View {
    var actif: Bool
    @ViewBuilder var contenu: Contenu
    var body: some View {
        if actif {
            ViewThatFits(in: .vertical) {
                contenu
                // Coupé net sur les bords de la carte : l'accueil désactive le
                // découpage des défilements pour les ombres, on le rétablit ici.
                ScrollView(showsIndicators: true) { contenu }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollClipDisabled(false)
                    .clipShape(RoundedRectangle(cornerRadius: T.rBig, style: .continuous))
            }
        } else {
            contenu
        }
    }
}
