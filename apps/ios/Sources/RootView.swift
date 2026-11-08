import SwiftUI

struct RootView: View {
    @Bindable var model: HelperModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Soin.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Header(name: model.helperName ?? "Support", onAvatar: { model.sheet = .settings })
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                if model.isConfigured { PeopleRow(model: model) }
                if model.isConfigured && !model.connected {
                    LostBanner(model: model).padding(.horizontal, 20).padding(.bottom, 10)
                }
                content
            }
            if let t = model.toast {
                Text(verbatim: t)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Soin.ink, in: Capsule())
                    .padding(.bottom, 110).padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
        .animation(.spring(duration: 0.35), value: model.screen)
        .sheet(item: $model.sheet, onDismiss: {
            if !model.isConfigured && model.sheet == nil { model.sheet = .settings }
        }) { s in
            switch s {
            case .settings: SettingsView(model: model)
            case .scanner: ScannerSheet(model: model)
            case .pair(let l): PairSheet(model: model, link: l)
            }
        }
        .onAppear { if !model.isConfigured && model.sheet == nil { model.sheet = .settings } }
        .fullScreenCover(isPresented: Binding(get: { model.guardAlertId != nil }, set: { _ in })) {
            GuardRequestView(model: model).interactiveDismissDisabled()
        }
    }

    @ViewBuilder private var content: some View {
        if !model.isConfigured {
            Spacer()
        } else {
            switch model.screen {
            case .idle: IdleView(model: model)
            case .waiting: WaitingView(model: model, text: "En attente de l’autorisation de \(model.senior)")
            case .planning: WaitingView(model: model, text: "Holo regarde l’écran…")
            case .approval: ApprovalView(model: model)
            case .active: ActiveView(model: model)
            case .helper: HelperView(model: model)
            case .done: DoneView(model: model)
            case .stopped: StoppedView(model: model)
            }
        }
    }
}

struct Header: View {
    var name: String
    var onAvatar: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAvatar) {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: 20, weight: .bold)).foregroundStyle(Soin.accent)
                    .frame(width: 48, height: 48).background(Soin.accentSoft, in: Circle())
            }
            .accessibilityLabel("Réglages")
            VStack(alignment: .leading, spacing: 0) {
                Text({ let h = Calendar.current.component(.hour, from: Date()); return (h >= 19 || h < 5) ? "Bonsoir" : "Bonjour" }())
                    .font(.system(size: 14)).foregroundStyle(Soin.secondary)
                Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
            }
            Spacer()
            Image(systemName: "bell").font(.system(size: 18, weight: .regular)).foregroundStyle(Soin.ink)
                .frame(width: 48, height: 48).background(Soin.card, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// État de la connexion quand elle ne marche pas : la vraie raison, pas un « reconnexion » muet.
struct LostBanner: View {
    let model: HelperModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if model.linkError == nil || model.retryAt != nil {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14))
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ConnectionText.line(model, now: ctx.date))
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if model.linkError != nil {
                Button("Vérifier les réglages") { model.sheet = .settings }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.white.opacity(0.18), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Soin.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

enum ConnectionText {
    @MainActor static func line(_ m: HelperModel, now: Date) -> String {
        if m.connected { return "Connecté à \(m.displayHost)" }
        guard let e = m.linkError else { return "Connexion à \(m.displayHost)…" }
        guard let at = m.retryAt else { return e }
        let n = Int(at.timeIntervalSince(now).rounded(.up))
        return n > 0 ? "\(e), nouvel essai dans \(n) s" : "\(e), nouvel essai…"
    }
}

struct SettingsView: View {
    @Bindable var model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var key = ""
    @State private var org = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connexion").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                Text("Le plus simple : scannez le QR code affiché sur l’ordinateur de \(model.senior) (Mon support › Ajouter un support).")
                    .font(.system(size: 15)).foregroundStyle(Soin.secondary)
                Button("Scanner le QR code de l’ordinateur") { model.sheet = .scanner }
                    .buttonStyle(CapsuleButtonStyle(fill: Soin.accent))
                if let l = model.manualPairLink() {
                    Button("Entrer le code à 6 chiffres") { model.openPair(l) }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                }
                Text("Service informatique").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink).padding(.top, 8)
                Text("Collez le lien d’organisation donné par l’IT : tous les postes s’ajoutent, sans code.")
                    .font(.system(size: 15)).foregroundStyle(Soin.secondary)
                field("Lien d’organisation", text: $org, prompt: "https://…/o/sup-…")
                if let e = model.orgError {
                    Text(e).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.danger)
                }
                Button(model.orgBusy ? "Ajout…" : "Ajouter les postes") {
                    Task { if await model.addOrg(org) { dismiss() } }
                }
                    .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                    .disabled(org.trimmingCharacters(in: .whitespaces).isEmpty || model.orgBusy)
                Text("Ou à la main").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink).padding(.top, 8)
                field("Adresse du serveur", text: $server, prompt: "https://…/k/<clé de l'espace>")
                field("Clé support", text: $key, prompt: "demo")
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(model.connected ? Soin.accent : (model.linkError == nil ? Soin.secondary : Soin.danger))
                        .frame(width: 8, height: 8).padding(.top, 5)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(model.isConfigured ? ConnectionText.line(model, now: ctx.date) : "Non configuré")
                            .font(.system(size: 14)).foregroundStyle(Soin.secondary)
                    }
                }
                if let g = model.lastGood, g.server != model.serverURL || g.key != model.helperKey {
                    Button("Revenir au dernier réglage qui marchait") {
                        server = g.server; key = g.key
                        model.applySettings(server: g.server, key: g.key)
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.accent)
                }
                if let error = model.pairError {
                    Text(error).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.danger)
                }
                Button("Enregistrer et se connecter") {
                    if model.applySettings(server: server, key: key) { dismiss() }
                }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(server.trimmingCharacters(in: .whitespaces).isEmpty || key.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
                if model.isConfigured {
                    Button("Réessayer maintenant") { model.reconnect() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled(!model.isConfigured)
        .onAppear { server = model.serverURL; key = model.helperKey }
    }
    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.secondary)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .font(.system(size: 17)).padding(16).soinCard(radius: 18)
        }
    }
}

// MARK: - Écrans simples

struct IdleView: View {
    let model: HelperModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.lastAlert == nil && model.guardAlertId == nil {
                // Hors connexion, on ne sait rien : pas de « Rien à signaler » ni de mascotte sereine.
                if model.connected {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rien à signaler pour \(model.senior)").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Vous serez prévenu dès qu’une demande d’aide arrive.").font(.system(size: 16)).foregroundStyle(Soin.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Mascotte(humeur: .calme).frame(width: Mascotte.Taille.carte, height: Mascotte.Taille.carte)
                    }
                    .padding(22).soinCard(Soin.accentSoft, radius: 28)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Liaison interrompue").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                        Text("Impossible de recevoir les demandes d’aide de \(model.senior) pour le moment.")
                            .font(.system(size: 17, weight: .medium)).foregroundStyle(Soin.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22).soinCard(radius: 28)
                }
                }

                if let live = model.liveDictation {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(model.seniorTitle) est en train de parler", systemImage: "waveform")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.accent)
                        Text("« \(live) »").font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
                            .animation(.easeOut(duration: 0.15), value: live)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20).soinCard(.white, radius: 24)
                }

                if let a = model.lastAlert {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                        Text(a.detail).font(.system(size: 14)).foregroundStyle(Soin.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).soinCard()
                }

                Text("Derniers automates").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                if model.lessons.isEmpty {
                    Text("Aucun automate pour l’instant.").font(.system(size: 15)).foregroundStyle(Soin.secondary)
                } else {
                    ForEach(model.lessons.prefix(5)) { l in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Soin.accent)
                                .frame(width: 32, height: 32).background(Soin.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                                Text("\(l.steps?.count ?? 0) étapes").font(.system(size: 13)).foregroundStyle(Soin.secondary)
                            }
                            Spacer()
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .refreshable { await model.loadLessons() }
    }
}

struct WaitingView: View {
    let model: HelperModel
    let text: String
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RequestCard(model: model)
                VStack(spacing: 12) {
                    Mascotte(humeur: .reflechit).frame(width: Mascotte.Taille.attente, height: Mascotte.Taille.attente)
                    HStack(spacing: 10) {
                        ProgressView().tint(Soin.accent)
                        Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                    }
                }.padding(.top, 20)
            }.padding(.horizontal, 20)
        }
    }
}

struct StoppedView: View {
    let model: HelperModel
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            if model.stoppedBy == "gardien" {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Soin.danger)
                    .frame(width: 64, height: 64).background(Soin.card, in: Circle())
            } else {
                Mascotte(humeur: .calme).frame(width: Mascotte.Taille.arret, height: Mascotte.Taille.arret)
            }
            Text(model.stoppedBy == "gardien" ? "PapAI a arrêté l'assistance : démarche suspecte"
                 : model.iRefusedPlan ? "Vous avez refusé le plan" : "\(model.seniorTitle) a arrêté l’assistance")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Soin.ink)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Text("L'assistance reste arrêtée. Toute nouvelle aide demande votre accord.")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Text("Appelez \(model.senior) à son numéro habituel.")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer(); Spacer()
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Carte demande

struct RequestCard: View {
    let model: HelperModel
    var onThumb: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("J").font(.system(size: 20, weight: .bold)).foregroundStyle(Soin.accent)
                    .frame(width: 48, height: 48).background(Soin.card, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    TimelineView(.periodic(from: .now, by: 20)) { _ in
                        Text("Demande de \(model.senior) · \(ago(model.requestStart))")
                            .font(.system(size: 13)).foregroundStyle(Soin.secondary).lineLimit(1)
                    }
                    Text(model.seniorTitle).font(.system(size: 20, weight: .bold)).foregroundStyle(Soin.ink)
                }
            }
            Text("« \(model.task) »")
                .font(.system(size: 21, weight: .semibold)).foregroundStyle(Soin.ink)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let img = model.frame, let onThumb {
                Button(action: onThumb) {
                    HStack(spacing: 8) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 38, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text("Écran de \(model.senior)").font(.system(size: 13, weight: .medium)).foregroundStyle(Soin.ink)
                    }
                    .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
                    .background(Soin.card, in: Capsule())
                }.accessibilityLabel("Agrandir la dernière capture")
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .soinCard(Soin.accentSoft, radius: 28)
    }
    private func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m < 1 ? "à l’instant" : "il y a \(m) min"
    }
}

/// Mes personnes aidées : qui suivre en détail, qui demande une assistance, ajouter ou retirer.
struct PeopleRow: View {
    @Bindable var model: HelperModel
    @State private var forget: Person?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.people) { p in chip(p) }
                Button { model.sheet = .settings } label: {
                    Text("+ Ajouter une personne").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.accent)
                        .lineLimit(1).padding(.horizontal, 16).padding(.vertical, 12).background(Soin.card, in: Capsule())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
        .alert("Retirer \(forget.map { $0.name.isEmpty ? "cette personne" : $0.name } ?? "") ?",
               isPresented: Binding(get: { forget != nil }, set: { if !$0 { forget = nil } })) {
            Button("Retirer", role: .destructive) { if let p = forget { model.forget(p) }; forget = nil }
            Button("Annuler", role: .cancel) { forget = nil }
        } message: {
            Text("Ses demandes n’arriveront plus sur ce téléphone. Vous pourrez la rajouter avec un nouveau code.")
        }
    }

    private func chip(_ p: Person) -> some View {
        let here = model.isCurrent(p)
        let asking = !here && model.othersAsking[p.key] == true
        let name = p.name.isEmpty ? "Personne aidée" : p.name
        return Button { model.switchTo(p) } label: {
            HStack(spacing: 8) {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold)).foregroundStyle(Soin.accent)
                    .frame(width: 32, height: 32).background(Soin.accentSoft, in: Circle())
                Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(here ? Color.white : Soin.ink).lineLimit(1)
                if !here {
                    Circle().fill(model.othersOnline[p.key] == true ? Soin.accent : Soin.secondary).frame(width: 8, height: 8)
                    if asking {
                        Text("demande une assistance").font(.system(size: 12)).foregroundStyle(Soin.danger).lineLimit(1)
                    }
                }
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .background(here ? Soin.ink : Soin.card, in: Capsule())
            .overlay(Capsule().stroke(asking ? Soin.danger : Color.clear, lineWidth: 2))
        }
        .contextMenu { Button("Retirer", role: .destructive) { forget = p } }
        .accessibilityLabel(asking ? "\(name), demande une assistance" : name)
    }
}
