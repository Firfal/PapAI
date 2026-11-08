import SwiftUI

struct RootView: View {
    @Bindable var model: HelperModel

    var body: some View {
        ZStack(alignment: .bottom) {
            SoinBackground()
            VStack(spacing: 0) {
                Header(name: model.helperName ?? model.orgTitle, onAvatar: { model.sheet = .settings })
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
                    .background { SoinHeaderBackground() }
                    .padding(.bottom, 14)
                if model.isConfigured && model.screen != .idle { PeopleRow(model: model) }
                if model.isConfigured && !model.connected {
                    LostBanner(model: model).padding(.horizontal, 20).padding(.bottom, 10)
                }
                if let reason = model.sensitiveRefusal {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(reason).font(.system(size: 17)).foregroundStyle(Soin.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Compris") { model.sensitiveRefusal = nil }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading).soinCard()
                    .padding(.horizontal, 20).padding(.bottom, 12)
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
        .sheet(item: $model.sheet) { _ in SettingsView(model: model) }
        .fullScreenCover(isPresented: Binding(get: { model.guardAlertId != nil }, set: { _ in })) {
            GuardRequestView(model: model).interactiveDismissDisabled()
        }
    }

    @ViewBuilder private var content: some View {
        if !model.orgConfigured {
            NoOrgView()
        } else if !model.isConfigured {
            NoPosteView(model: model)
        } else {
            switch model.screen {
            case .idle: SupportHome(model: model)
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
                    .frame(width: 48, height: 48).background(Soin.card, in: Circle())
            }
            .accessibilityLabel("Réglages")
            VStack(alignment: .leading, spacing: 0) {
                Text({ let h = Calendar.current.component(.hour, from: Date()); return (h >= 19 || h < 5) ? "Bonsoir" : "Bonjour" }())
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(name).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "bell").font(.system(size: 18, weight: .regular)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(.white.opacity(0.18), in: Circle())
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
                Button("Réessayer maintenant") { model.reconnect() }
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

/// Sans jeton d'organisation : rien à saisir, l'administrateur configure le téléphone.
struct NoOrgView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aucune organisation configurée").font(.system(size: 26, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Contactez votre administrateur : il installe la configuration du support de votre organisation sur ce téléphone.")
                .font(.system(size: 17)).foregroundStyle(Soin.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22).soinCard(radius: 24)
        .padding(.horizontal, 20)
        Spacer()
    }
}

/// Organisation configurée, mais aucun poste à suivre (pas encore lu, vide, ou serveur injoignable).
struct NoPosteView: View {
    let model: HelperModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.orgLoaded && model.orgError == nil {
                HStack(spacing: 10) {
                    ProgressView().tint(Soin.accent)
                    Text("Chargement des postes…").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                }
            } else {
                Text(model.orgError == nil ? "Aucun poste inscrit pour l’instant" : "Postes indisponibles")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Soin.ink)
                Text(model.orgError ?? "Les postes de l’organisation apparaissent ici dès que PapAI y est installé.")
                    .font(.system(size: 17)).foregroundStyle(Soin.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22).soinCard(radius: 24)
        .padding(.horizontal, 20)
        .refreshable { await model.refreshOrg() }
        Spacer()
    }
}

/// Réglages en lecture seule : tout vient de la configuration de l'organisation.
struct SettingsView: View {
    @Bindable var model: HelperModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Réglages").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Organisation").font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.secondary)
                    Text(model.orgConfigured ? model.orgTitle : "Aucune organisation configurée")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
                    if let o = model.org {
                        Text(URL(string: o.server)?.host ?? o.server).font(.system(size: 15)).foregroundStyle(Soin.secondary)
                        Text("\(model.people.count) poste\(model.people.count > 1 ? "s" : "")")
                            .font(.system(size: 15)).foregroundStyle(Soin.secondary)
                    }
                    if let e = model.orgError {
                        Text(e).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18).soinCard()
                Text(model.orgConfigured ? "Configuré par votre administrateur. Rien à régler sur ce téléphone."
                     : "Contactez votre administrateur : il installe la configuration du support sur ce téléphone.")
                    .font(.system(size: 15)).foregroundStyle(Soin.secondary).fixedSize(horizontal: false, vertical: true)
                if model.isConfigured {
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(model.connected ? Soin.online : (model.linkError == nil ? Soin.secondary : Soin.danger))
                            .frame(width: 8, height: 8).padding(.top, 5)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(ConnectionText.line(model, now: ctx.date))
                                .font(.system(size: 14)).foregroundStyle(Soin.secondary)
                        }
                    }
                    Button("Réessayer maintenant") { model.reconnect(); Task { await model.refreshOrg() } }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                }
                Button("Fermer") { dismiss() }.buttonStyle(CapsuleButtonStyle()).padding(.top, 8)
            }
            .padding(24)
        }
        .background { SoinBackground() }
        .presentationDetents([.large])
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
                    .padding(22).soinCard(Soin.accentSoft, radius: 24)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connexion interrompue").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                        Text("Impossible de recevoir les demandes d’aide de \(model.senior) pour le moment.")
                            .font(.system(size: 17, weight: .medium)).foregroundStyle(Soin.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22).soinCard(radius: 24)
                }
                }

                if let live = model.liveDictation {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(model.seniorTitle) est en train de parler", systemImage: "waveform")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.accent)
                        Text("« \(live) »").font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
                            .animation(.easeOut(duration: 0.15), value: live)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20).soinCard()
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
                    VStack(spacing: 0) {
                        ForEach(Array(model.lessons.prefix(5).enumerated()), id: \.element.id) { i, l in
                            if i > 0 { Rectangle().fill(Soin.hairline).frame(height: 1).padding(.leading, 64) }
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Soin.accent)
                                    .frame(width: 36, height: 36).background(Soin.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(l.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                StatusPill(text: "\(l.steps?.count ?? 0) étapes", tone: .gray)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).soinCard()
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
                    .padding(.horizontal, 18).padding(.vertical, 12).soinCard(radius: 18)
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
                    .frame(width: 64, height: 64).background(Soin.danger.opacity(0.1), in: Circle())
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
                Text(String(model.senior.prefix(1)).uppercased()).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Soin.primary, in: Circle())
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
        .soinCard(radius: 24)
    }
    private func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m < 1 ? "à l’instant" : "il y a \(m) min"
    }
}

/// Les postes de l'organisation : lequel suivre en détail, lequel demande une assistance.
struct PeopleRow: View {
    @Bindable var model: HelperModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.people) { p in chip(p) }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
        .accessibilityLabel("Postes")
    }

    private func chip(_ p: Person) -> some View {
        let here = model.isCurrent(p)
        let asking = !here && model.othersAsking[p.key] == true
        let name = People.title(p)
        let detail = People.detail(p)
        return Button { model.switchTo(p) } label: {
            HStack(spacing: 8) {
                Text(String(name.prefix(1)).uppercased()).font(.system(size: 15, weight: .bold)).foregroundStyle(Soin.accent)
                    .frame(width: 32, height: 32).background(here ? Soin.card : Soin.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(here ? Color.white : Soin.ink).lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(here ? Color.white.opacity(0.85) : Soin.secondary).lineLimit(1)
                    }
                }
                if !here {
                    Circle().fill(model.othersOnline[p.key] == true ? Soin.online : Soin.secondary).frame(width: 8, height: 8)
                    if asking {
                        Text("demande une assistance").font(.system(size: 12)).foregroundStyle(Soin.danger).lineLimit(1)
                    }
                }
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .background(here ? AnyShapeStyle(Soin.primary) : AnyShapeStyle(Soin.card), in: Capsule())
            .overlay(Capsule().strokeBorder(asking ? Soin.danger : here ? Color.clear : Soin.hairline, lineWidth: asking ? 2 : 1))
        }
        .accessibilityLabel([name, detail, asking ? "demande une assistance" : nil].compactMap { $0 }.joined(separator: ", "))
    }
}
