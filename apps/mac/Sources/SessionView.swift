import SwiftUI

/// Étape 4 : avant tout partage, ce qui va se passer, en clair.
struct ConsentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Votre demande").font(rounded(18, .semibold)).foregroundStyle(T.accent)
                Text("« \(model.pendingTask) »").font(rounded(30, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("PapAI va regarder votre écran").font(rounded(44, .semibold)).tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                promise("eye.fill", "Holo voit votre écran pour comprendre le problème.")
                promise("hand.raised.fill", "Rien ne bouge avant l'accord de \(model.helperName).")
                promise("stop.circle.fill", "Le bouton Arrêter reste visible : vous pouvez tout arrêter à tout moment.")
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.ink).padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))

            HStack(spacing: 14) {
                Button { model.cancelConsent() } label: { Text("Annuler").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(filled: false, height: 78))
                    .keyboardShortcut(.cancelAction)
                Button { model.askHelp(task: model.pendingTask) } label: {
                    Text("D'accord, je partage mon écran").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 78))
                .keyboardShortcut(.defaultAction)
                .disabled(!model.connected)
            }
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(T.accent).frame(width: 34)
            Text(text).font(rounded(21, .medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SessionView: View {
    @Environment(AppModel.self) private var model

    private var state: SessionState { model.state ?? .planning }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                if model.sessionOpen { sharedBanner }
                Text(title).font(rounded(40, .semibold)).tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = subtitle {
                    Text(sub).font(rounded(24, .medium)).foregroundStyle(state == .active ? T.ink : T.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.25), value: sub)
                }
                ScrollView(showsIndicators: false) { content }
                Spacer(minLength: 0)
                if !model.task.isEmpty && state != .stopped && state != .awaiting_approval {
                    Text("Votre demande : \(model.task)")
                        .font(rounded(16)).foregroundStyle(T.muted).lineLimit(2)
                }
            }
            .foregroundStyle(T.ink)
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))

            if model.sessionOpen {
                Button { model.stop() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "stop.fill").font(.system(size: 20))
                        Text("Arrêter").font(rounded(26, .semibold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 70)
                    .background(Capsule().fill(T.ink))
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Arrêter l'assistance (Échap)")
            } else {
                Button { model.backHome() } label: {
                    Text("Retour à l'accueil").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 70))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var sharedBanner: some View {
        HStack(spacing: 10) {
            Circle().fill(T.accent).frame(width: 10, height: 10)
            Text("Écran partagé").font(rounded(16, .semibold))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Capsule().fill(T.card))
    }

    private var title: String {
        switch state {
        case .planning: "Holo regarde votre écran…"
        case .awaiting_approval: "\(model.HelperName) vérifie le plan"
        case .active: "Holo s'en occupe"
        case .awaiting_helper: "\(model.HelperName) vous aide"
        case .done: "C'est fait !"
        case .stopped: "L'assistance est arrêtée."
        }
    }

    private var subtitle: String? {
        switch state {
        case .planning: "Un instant, je prépare ce qu'il faut faire."
        case .awaiting_approval: "Rien ne se passera sur votre écran avant son accord."
        case .active: model.currentAction ?? "Je regarde l'écran…"
        case .awaiting_helper: "Holo a une question. \(model.HelperName) a reçu une image de votre écran et va répondre. Restez là, ne touchez à rien."
        case .done: nil
        case .stopped: "Votre écran n'est plus partagé."
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .awaiting_approval where !model.plan.isEmpty:
            planList(done: nil)
        case .active:
            VStack(alignment: .leading, spacing: 16) {
                if !model.actions.isEmpty { history }
                if !model.plan.isEmpty { planList(done: nil, compact: true) }
            }
        case .awaiting_helper:
            if let q = model.question {
                VStack(alignment: .leading, spacing: 8) {
                    Text("La question de Holo").font(rounded(16, .semibold)).foregroundStyle(T.muted)
                    Text(q).font(rounded(24, .medium)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
            }
        case .done:
            VStack(alignment: .leading, spacing: 16) {
                Text(model.answer ?? "Voilà, c'est fait.")
                    .font(rounded(26, .medium)).padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                endNote("lock.fill", "Votre écran n'est plus partagé.")
                endNote("book.fill", "\(model.HelperName) peut en faire un tutoriel. Vous le retrouverez dans « Mes tutoriels » pour le refaire sans aide.")
            }
        default:
            EmptyView()
        }
    }

    private func planList(done: Int?, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if compact { Text("Le plan validé").font(rounded(16, .semibold)).foregroundStyle(T.muted) }
            ForEach(Array(model.plan.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 16) {
                    Text("\(i + 1)").font(rounded(compact ? 15 : 18, .semibold)).foregroundStyle(.white)
                        .frame(width: compact ? 30 : 38, height: compact ? 30 : 38).background(Circle().fill(T.ink))
                    Text(step).font(rounded(compact ? 18 : 20, .medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(compact ? 10 : 12)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
            }
        }
    }

    /// Ce que Holo a déjà fait, la dernière action en premier plan.
    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce que j'ai fait").font(rounded(16, .semibold)).foregroundStyle(T.muted)
            ForEach(Array(model.actions.suffix(4).enumerated()), id: \.offset) { i, a in
                let last = i == min(model.actions.count, 4) - 1
                HStack(spacing: 12) {
                    Image(systemName: last ? "circle.dotted" : "checkmark.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(T.accent)
                    Text(a).font(rounded(18, last ? .semibold : .regular))
                        .foregroundStyle(last ? T.ink : T.muted)
                }
            }
        }
    }

    private func endNote(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(T.accent).frame(width: 28)
            Text(text).font(rounded(19)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
