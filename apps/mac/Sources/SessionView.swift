import SwiftUI

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
                    Text(sub).font(rounded(22)).foregroundStyle(T.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Text("Retour").frame(maxWidth: .infinity)
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
        case .awaiting_approval: "Quentin vérifie le plan"
        case .active: "Holo s'en occupe"
        case .awaiting_helper: "Quentin vous aide"
        case .done: "C'est terminé"
        case .stopped: "L'assistance est arrêtée."
        }
    }

    private var subtitle: String? {
        switch state {
        case .planning: "Un instant, je prépare ce qu'il faut faire."
        case .awaiting_approval: "Rien ne se passera sur votre écran avant son accord."
        case .active: model.currentAction ?? "Je regarde l'écran…"
        case .awaiting_helper: model.question ?? "Quentin prend la main, restez là."
        case .done: nil
        case .stopped: "Votre écran n'est plus partagé."
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .awaiting_approval where !model.plan.isEmpty:
            VStack(spacing: 12) {
                ForEach(Array(model.plan.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 16) {
                        Text("\(i + 1)").font(rounded(18, .semibold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Circle().fill(T.ink))
                        Text(step).font(rounded(20, .medium)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                }
            }
        case .done:
            Text(model.answer ?? "Voilà, c'est fait.")
                .font(rounded(24, .medium)).padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
        default:
            EmptyView()
        }
    }
}
