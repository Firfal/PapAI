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
                promise("checkmark.seal.fill", "On ne vous le redemandera pas. Vous pouvez retirer cet accord dans Réglages.")
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.ink).padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))

            HStack(spacing: 14) {
                Button { model.cancelConsent() } label: { Text("Annuler").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(filled: false, height: 78))
                    .keyboardShortcut(.cancelAction)
                Button { model.giveConsent() } label: {
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
    private var guardStopped: Bool { state == .stopped && model.stoppedBy == "gardien" }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                if model.sessionOpen { sharedBanner }
                Text(title).font(rounded(guardStopped ? 34 : 40, .semibold)).tracking(-0.6)
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
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(guardStopped ? T.card : T.mint))

            if model.sessionOpen {
                HStack(spacing: 14) {
                    if state == .active || state == .awaiting_helper || model.paused {
                        Button { model.togglePause() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.system(size: 20))
                                Text(model.paused ? "Reprendre" : "Pause").font(rounded(26, .semibold))
                            }
                            .foregroundStyle(T.ink).frame(maxWidth: .infinity).frame(height: 70)
                            .background(Capsule().fill(T.card))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(model.paused ? "Reprendre l'aide" : "Mettre l'aide en pause")
                    }
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
                }
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
        if model.paused && model.sessionOpen { return "L'aide est en pause" }
        switch state {
        case .planning: return "Holo regarde votre écran…"
        case .awaiting_approval: return "\(model.HelperName) vérifie votre demande"
        case .active: return "\(model.carer) s'en occupe"
        case .awaiting_helper: return "\(model.HelperName) vous aide"
        case .done: return "C'est fait !"
        case .stopped: return model.stoppedBy == "gardien"
            ? "PapAI a arrêté : cette démarche peut être une arnaque" : "L'assistance est arrêtée."
        }
    }

    private var subtitle: String? {
        if model.paused && model.sessionOpen {
            return "Vous pouvez utiliser votre ordinateur. Appuyez sur Reprendre quand vous voulez."
        }
        switch state {
        case .planning: return "Un instant, je prépare ce qu'il faut faire."
        case .awaiting_approval: return "Rien ne se passera sur votre écran avant son accord."
        case .active: return "Pendant l'aide, la souris et le clavier sont réservés à Holo. Pause ou Arrêter restent toujours possibles."
        case .awaiting_helper: return model.questionForMe
            ? "J'ai besoin d'une information que vous seul connaissez."
            : "\(model.HelperName) répond à une question de Holo. Restez là, ne touchez à rien."
        case .done: return nil
        case .stopped: return guardStopped ? nil : "Votre écran n'est plus partagé."
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .planning, .awaiting_approval, .active:
            Progress(fraction: fraction, phase: phase, helper: model.HelperName, carer: model.carer)
        case .awaiting_helper:
            if model.questionForMe, let q = model.question {
                SeniorQuestion(question: q, options: model.questionOptions) { model.answerSenior($0) }
            } else {
                Progress(fraction: fraction, phase: 2, helper: model.HelperName, carer: model.carer)
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
        case .stopped where guardStopped:
            VStack(alignment: .leading, spacing: 20) {
                Text("Ne payez rien et ne donnez aucun code.")
                Text("Appelez \(model.helpers.first?.name ?? "votre support") à son numéro habituel.")
                if model.guardAcknowledged {
                    Text("Votre support a vu l'alerte et s'en occupe")
                }
            }
            .font(rounded(23, .medium))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    /// Où en est le traitement, sans détailler les étapes de Holo : la personne
    /// aidée n'a pas besoin du plan, seulement de savoir que ça avance.
    private var phase: Int {
        switch state {
        case .planning: 0
        case .awaiting_approval: 1
        default: 2
        }
    }

    private var fraction: Double {
        switch state {
        case .planning: return 0.15
        case .awaiting_approval: return 0.35
        case .active, .awaiting_helper:
            if let step = model.planStep, !model.plan.isEmpty {
                return 0.45 + 0.5 * Double(max(step - 1, 0)) / Double(model.plan.count)
            }
            return 0.5
        case .done: return 1
        case .stopped: return 0
        }
    }

    private func endNote(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(T.accent).frame(width: 28)
            Text(text).font(rounded(19)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Avancement du traitement : une barre et trois temps, rien de technique.
private struct Progress: View {
    let fraction: Double
    let phase: Int
    let helper: String
    let carer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.card)
                    Capsule().fill(T.accent).frame(width: max(18, g.size.width * fraction))
                        .animation(.easeInOut(duration: 0.6), value: fraction)
                }
            }
            .frame(height: 18)
            .accessibilityElement()
            .accessibilityLabel("Avancement")
            .accessibilityValue("\(Int(fraction * 100)) %")

            step(0, "Holo regarde votre écran et prépare la suite")
            step(1, "\(helper) vérifie et donne son accord")
            step(2, "\(carer) s'en occupe, avec Holo")
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card.opacity(0.55)))
    }

    private func step(_ i: Int, _ text: String) -> some View {
        let done = i < phase, now = i == phase
        return HStack(spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : now ? "circle.dotted" : "circle")
                .font(.system(size: 24)).foregroundStyle(done || now ? T.accent : T.muted)
            Text(text).font(rounded(21, now ? .semibold : .regular))
                .foregroundStyle(done ? T.muted : T.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done ? "Fait : \(text)" : now ? "En cours : \(text)" : text)
    }
}

/// Une question que Holo pose à la personne aidée, pour ce qu'elle seule sait.
private struct SeniorQuestion: View {
    let question: String
    let options: [String]
    let send: (String) -> Void
    @State private var text = ""
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Holo vous demande").font(rounded(16, .semibold)).foregroundStyle(T.muted)
            Text(question).font(rounded(28, .medium)).fixedSize(horizontal: false, vertical: true)
            if sent {
                Label("Merci, c'est noté.", systemImage: "checkmark.circle.fill")
                    .font(rounded(20, .semibold)).foregroundStyle(T.accent)
            } else {
                if !options.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(options, id: \.self) { o in
                            Button(o) { reply(o) }.buttonStyle(PillStyle(filled: false, height: 56))
                        }
                    }
                }
                HStack(spacing: 12) {
                    TextField("Votre réponse", text: $text)
                        .textFieldStyle(.plain).font(rounded(22, .medium))
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.bg))
                        .onSubmit { reply(text) }
                    Button("Répondre") { reply(text) }
                        .buttonStyle(PillStyle(height: 56))
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Ne donnez jamais de mot de passe ni de code : on ne vous les demandera pas.")
                    .font(rounded(15)).foregroundStyle(T.muted)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
    }

    private func reply(_ t: String) {
        let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        send(v); sent = true
    }
}
