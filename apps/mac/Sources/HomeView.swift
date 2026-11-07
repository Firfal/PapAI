import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var request = ""
    @State private var warning: String?
    @FocusState private var focused: Bool
    @State private var dictation = Dictation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var writing = false
    @State private var favoris = HomeShortcuts()
    @State private var ajoutVisible = false
    private var raccourcis: MicPresence { .shared }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            helpCard
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.lessons.isEmpty || model.notice != nil { shortcuts }
                    apps
                }
                    .padding(.bottom, 8)
            }
            .frame(width: 400)
        }
        .onAppear { ouvrirDemande(); favoris.actualiser() }
        .onChange(of: raccourcis.demande) { _, _ in ouvrirDemande() }
        .sheet(isPresented: $ajoutVisible, onDismiss: { favoris.actualiser() }) {
            AjouterRaccourci(favoris: favoris)
        }
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.everyMinute) { ctx in
                let hello = Greeting.word(at: ctx.date)
                Text(model.firstName.isEmpty ? hello : "\(hello) \(model.firstName) !")
                    .font(rounded(44, .bold)).tracking(-0.8)
            }
            HStack(alignment: .center, spacing: 26) {
                Mascotte(humeur: humeur).frame(width: 128 * CGFloat(model.textScale), height: 128 * CGFloat(model.textScale))
                Bulle {
                    Text(raccourcis.microPresent
                         ? "Un souci sur l'ordinateur ? Dites-le-moi simplement, je préviens \(model.helperName) tout de suite."
                         : "Un souci sur l'ordinateur ? Écrivez-le-moi, je préviens \(model.helperName) tout de suite.")
                        .font(rounded(19, .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            if raccourcis.microPresent {
                VStack(spacing: 12) {
                    micButton
                    Text(dictation.phase == .listening ? "Je vous écoute…" :
                         dictation.phase == .transcribing ? "Je note…" : "Parler à PapAI")
                        .font(rounded(22, .bold))
                    if !request.isEmpty && !writing {
                        Text(request).font(rounded(18)).lineLimit(3)
                    }
                }.frame(maxWidth: .infinity)
            }
            if writing || !raccourcis.microPresent {
                HStack(spacing: 10) {
                    TextField("Écrivez votre demande", text: $request)
                        .textFieldStyle(.plain).font(rounded(18)).focused($focused)
                        .onSubmit(submit)
                    Button(action: submit) {
                        Text("Envoyer").font(rounded(15, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(Capsule().fill(T.ink))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(dictation.phase != .idle)
                }
                .padding(18).background(RoundedRectangle(cornerRadius: 22).fill(T.card))
            } else if dictation.phase == .idle {
                Button { writing = true; focused = true } label: {
                    Label("Écrire plutôt", systemImage: "pencil").font(rounded(16, .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(T.card))
                        .contentShape(Capsule())
                }.buttonStyle(PressStyle()).frame(maxWidth: .infinity)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(rounded(17, .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(T.card))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(T.ink)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))
    }

    private var micButton: some View {
        let listening = dictation.phase == .listening
        return Button(action: dicter) {
                ZStack {
                    if listening {
                        Circle().fill(T.accent.opacity(0.25))
                            .frame(width: 166, height: 166)
                            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.08 : 0.94))
                    }
                    Circle().fill(listening ? T.accent : .white).frame(width: 148, height: 148)
                        .overlay(Circle().strokeBorder(listening ? Color.clear : T.papaya, lineWidth: 6))
                        .shadow(color: T.papaya.opacity(listening ? 0 : 0.25), radius: 14, y: 6)
                    if dictation.phase == .transcribing {
                        ProgressView()
                    } else {
                        Image(systemName: listening ? "stop.fill" : "mic.fill")
                            .foregroundStyle(listening ? .white : T.ink).font(rounded(48))
                    }
                }.frame(width: 180, height: 180)
        }
        .buttonStyle(PressStyle())
        .disabled(dictation.phase == .transcribing)
        .accessibilityLabel(listening ? "Arrêter la dictée" : "Dicter ma demande")
        .onChange(of: listening) { _, on in
            if on, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            } else { withAnimation(.none) { pulse = false } }
        }
        .onChange(of: dictation.message) { _, m in if let m { warning = m; dictation.message = nil } }
    }

    private var humeur: Mascotte.Humeur {
        switch dictation.phase {
        case .listening: .ecoute
        case .transcribing: .reflechit
        default: .joyeuse
        }
    }

    private func ouvrirDemande() {
        guard raccourcis.demande else { return }
        raccourcis.demande = false
        if raccourcis.microPresent {
            if dictation.phase == .idle { dicter() }
        } else { writing = true; focused = true }
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
        if text.isEmpty { warning = "Dites en quelques mots ce qui ne va pas."; focused = true; return }
        if !model.connected { warning = "Je ne joins pas \(model.helperName) pour le moment. Réessayez dans un instant."; return }
        warning = nil
        // L'accord de partage a été donné à l'inscription : la demande part directement.
        model.requestConsent(task: text)
        request = ""
    }

    // MARK: Droite

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let n = model.notice {
                Text(n).font(rounded(17, .medium))
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.mint))
            }
            if !model.lessons.isEmpty {
                Text("Mes tutoriels").font(rounded(22, .bold))
            }
            ForEach(model.lessons) { l in tile(l) }
        }
        .foregroundStyle(T.ink)
    }

    // Fiches héritées : la future tâche `.papi` les remplacera, on n'y investit pas.
    private func tile(_ l: Lesson) -> some View {
        HStack(spacing: 10) {
            Button { model.runShortcut(l) } label: {
                HStack(spacing: 10) {
                    Circle().fill(T.mint).frame(width: 36, height: 36)
                        .overlay(Image(systemName: Shortcuts.symbol(for: l.shortcut?.folder))
                            .font(rounded(18)).foregroundStyle(T.accent))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.title).font(rounded(18, .semibold)).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(l.title)
            if !(l.steps ?? []).isEmpty {
                Button { model.openLesson(l) } label: {
                    Text("Montrez-moi").font(rounded(15, .semibold)).foregroundStyle(T.leaf)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5).frame(minHeight: 44)
                        .background(Capsule().fill(T.mint))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mes raccourcis").font(rounded(22, .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(favoris.tuiles) { tuile in
                    Button { favoris.ouvrir(tuile, notice: model.showNotice) } label: {
                        VStack(spacing: 6) {
                            Group {
                                if case .application(let bundle) = tuile.cible,
                                   let image = icon(bundle) {
                                    Image(nsImage: image).resizable().frame(width: 40, height: 40)
                                } else {
                                    Image(systemName: symbole(tuile)).font(rounded(26))
                                        .foregroundStyle(T.leaf)
                                }
                            }
                            .frame(height: 42)
                            Text(tuile.titre).font(rounded(15, .medium)).multilineTextAlignment(.center)
                                .lineLimit(2).frame(minHeight: 24, alignment: .top)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card))
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Ouvrir \(tuile.titre)")
                    .contextMenu {
                        if tuile.ajoutee { Button("Retirer") { favoris.retirer(tuile) } }
                    }
                }
                Button { ajoutVisible = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(rounded(26)).foregroundStyle(T.muted).frame(height: 42)
                        Text("Ajouter").font(rounded(15, .medium)).frame(minHeight: 24, alignment: .top)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(T.muted.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                    .buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(T.ink)
    }

    private func symbole(_ tuile: HomeShortcuts.Tuile) -> String {
        if case .application(let bundle) = tuile.cible {
            switch bundle {
            case "com.apple.mail": return "envelope"
            case "com.apple.Photos": return "photo.on.rectangle"
            case "com.apple.Safari": return "safari"
            default: return "app"
            }
        }
        return tuile.symbole
    }

    private func icon(_ bundle: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

}

private struct AjouterRaccourci: View {
    @Environment(\.dismiss) private var fermer
    let favoris: HomeShortcuts
    @State private var albumVisible = false
    @State private var nom = ""
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ajouter un raccourci").font(rounded(26, .semibold))
            Text("Jusqu'à 4 raccourcis personnels, gardés sur ce Mac.").font(rounded(16))
            Button {
                let panneau = NSOpenPanel()
                panneau.canChooseDirectories = true
                panneau.canChooseFiles = false
                panneau.allowsMultipleSelection = false
                panneau.treatsFilePackagesAsDirectories = false
                panneau.prompt = "Ajouter"
                if panneau.runModal() == .OK, let url = panneau.url {
                    if favoris.ajouterDossier(url) { fermer() }
                    else { erreur = "Choisissez un dossier ordinaire. Si vous avez déjà 4 raccourcis personnels, retirez-en un d'abord." }
                }
            } label: { Label("Un dossier", systemImage: "folder") }
                .buttonStyle(PillStyle(filled: false, height: 50))
            Button { albumVisible = true; erreur = nil } label: {
                Label("Un album Photos", systemImage: "rectangle.stack")
            }.buttonStyle(PillStyle(filled: false, height: 50))
            if albumVisible {
                Text("Le nom de l'album dans Photos").font(rounded(17))
                TextField("Par exemple : Petits-enfants", text: $nom)
                    .textFieldStyle(.roundedBorder).font(rounded(18)).onSubmit(ajouterAlbum)
                Button("Ajouter cet album", action: ajouterAlbum)
                    .buttonStyle(PillStyle(height: 50))
            }
            if let erreur { Text(erreur).font(rounded(16)).foregroundStyle(T.danger) }
            Button("Fermer") { fermer() }.buttonStyle(.plain).font(rounded(17))
        }
        .foregroundStyle(T.ink).padding(32).frame(width: 520).background(T.mint)
    }

    private func ajouterAlbum() {
        if favoris.ajouterAlbum(nom) { fermer() }
        else { erreur = "Écrivez le nom de l'album. Si vous avez déjà 4 raccourcis personnels, retirez-en un d'abord." }
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
