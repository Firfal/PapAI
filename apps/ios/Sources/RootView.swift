import SwiftUI

struct RootView: View {
    @Bindable var model: HelperModel
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Soin.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Header(onAvatar: { showSettings = true })
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                if model.isConfigured && !model.connected { LostBanner().padding(.horizontal, 20).padding(.bottom, 10) }
                content
            }
            if let t = model.toast {
                Text(t)
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
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .onAppear { if !model.isConfigured { showSettings = true } }
    }

    @ViewBuilder private var content: some View {
        if !model.isConfigured {
            Spacer()
        } else {
            switch model.screen {
            case .idle: IdleView(model: model)
            case .waiting: WaitingView(model: model, text: "En attente de l’autorisation de Jeanne")
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
    var onAvatar: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAvatar) {
                Text("Q").font(.system(size: 20, weight: .bold)).foregroundStyle(Soin.accent)
                    .frame(width: 48, height: 48).background(Soin.accentSoft, in: Circle())
            }
            .accessibilityLabel("Réglages")
            VStack(alignment: .leading, spacing: 0) {
                Text("Bonjour").font(.system(size: 14)).foregroundStyle(Soin.secondary)
                Text("Quentin").font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
            }
            Spacer()
            Image(systemName: "bell").font(.system(size: 18, weight: .regular)).foregroundStyle(Soin.ink)
                .frame(width: 48, height: 48).background(Soin.card, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

struct LostBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white).scaleEffect(0.8)
            Text("Connexion perdue").font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("reconnexion…").font(.system(size: 13)).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Soin.ink, in: Capsule())
    }
}

struct SettingsView: View {
    @Bindable var model: HelperModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connexion").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Adresse du serveur PapAI et clé aidant affichée au démarrage du serveur.")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
            field("Adresse du serveur", text: $model.serverURL, prompt: "http://192.168.1.20:8000")
            field("Clé aidant", text: $model.helperKey, prompt: "demo")
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.connected ? Soin.accent : Soin.secondary).frame(width: 8, height: 8)
                Text(model.connected ? "Connecté" : "Non connecté").font(.system(size: 14)).foregroundStyle(Soin.secondary)
            }
            Button("Enregistrer") { model.saveSettings(); dismiss() }
                .buttonStyle(CapsuleButtonStyle())
                .disabled(model.serverURL.isEmpty || model.helperKey.isEmpty)
        }
        .padding(24)
        .background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled(!model.isConfigured)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tout va bien chez Jeanne").font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                    Text("Vous serez prévenu dès qu’elle demande de l’aide.").font(.system(size: 16)).foregroundStyle(Soin.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(22).soinCard(Soin.accentSoft, radius: 28)

                if let a = model.lastAlert {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                        Text(a.detail).font(.system(size: 14)).foregroundStyle(Soin.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).soinCard()
                }

                Text("Derniers automatismes").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                if model.lessons.isEmpty {
                    Text("Aucun automatisme pour l’instant.").font(.system(size: 15)).foregroundStyle(Soin.secondary)
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
                HStack(spacing: 10) {
                    ProgressView().tint(Soin.accent)
                    Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(Soin.secondary)
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
            Image(systemName: model.iRefusedPlan ? "xmark" : "pause")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(Soin.ink)
                .frame(width: 64, height: 64).background(Soin.card, in: Circle())
            Text(model.iRefusedPlan ? "Vous avez refusé le plan" : "Jeanne a arrêté l’assistance")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Rien n’a été fait sur son ordinateur.").font(.system(size: 15)).foregroundStyle(Soin.secondary)
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
                        Text("Demande de Mamie · \(ago(model.requestStart))")
                            .font(.system(size: 13)).foregroundStyle(Soin.secondary).lineLimit(1)
                    }
                    Text("Jeanne, 81 ans").font(.system(size: 20, weight: .bold)).foregroundStyle(Soin.ink)
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
                        Text("Écran de Jeanne").font(.system(size: 13, weight: .medium)).foregroundStyle(Soin.ink)
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
