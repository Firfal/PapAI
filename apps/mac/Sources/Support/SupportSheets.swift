import SwiftUI

/// Feuille Mac : en-tête bleu, corps, barre de boutons en bas.
struct SupportSheet<Corps: View, Bas: View>: View {
    let titre: String
    var sousTitre: String? = nil
    var width: CGFloat = 640
    var height: CGFloat = 560
    @ViewBuilder var corps: Corps
    @ViewBuilder var bas: Bas

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(titre).font(rounded(28, .bold))
                if let sousTitre { Text(sousTitre).font(rounded(16, .medium)).opacity(0.92).fixedSize(horizontal: false, vertical: true) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { corps }
                    .padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack(spacing: 12) { bas }
                .padding(.horizontal, 26).padding(.vertical, 16)
        }
        .foregroundStyle(T.ink)
        .frame(width: width, height: height).background(T.bg)
    }
}

private func sheetLabel(_ s: String) -> some View {
    Text(s).font(rounded(14, .semibold)).foregroundStyle(T.muted)
}

// MARK: - Préciser, Modifier

struct SupportRefineSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dictation = Dictation()
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SupportSheet(titre: "Préciser le plan",
                     sousTitre: "Dites ou écrivez à Holo ce qu’il doit changer. Il proposera un nouveau plan.") {
            SupportDictationField(text: $text, placeholder: "Par exemple : le rapport est dans Documents > Rapports 2026",
                                  dictation: dictation, httpBase: model.baseHTTP)
        } bas: {
            Spacer()
            Button("Annuler") { dictation.stop(); dismiss() }
                .buttonStyle(supportSecondary(50)).keyboardShortcut(.cancelAction)
            Button("Envoyer à Holo") {
                let t = trimmed
                if !t.isEmpty { model.refinePlan(t); dismiss() }
            }
            .buttonStyle(PillStyle(height: 50, icone: "arrow.up"))
            .disabled(trimmed.isEmpty || dictation.phase != .idle)
        }
        .onDisappear { dictation.stop() }
    }
}

struct SupportStepEditSheet: View {
    let model: HelperModel
    let step: EditedStepMac
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dictation = Dictation()
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SupportSheet(titre: "Modifier l’étape \(step.index + 1)",
                     sousTitre: "Corrigez le texte, ou dites la nouvelle étape. Holo proposera un nouveau plan, que vous validerez.") {
            SupportDictationField(text: $text, placeholder: "La nouvelle étape", dictation: dictation,
                                  httpBase: model.baseHTTP, replacing: step.text)
            if trimmed != step.text {
                VStack(alignment: .leading, spacing: 4) {
                    sheetLabel("Avant")
                    Text(step.text).font(rounded(16)).foregroundStyle(T.muted).strikethrough()
                }
            }
        } bas: {
            Spacer()
            Button("Annuler") { dictation.stop(); dismiss() }
                .buttonStyle(supportSecondary(50)).keyboardShortcut(.cancelAction)
            Button("Envoyer à Holo") {
                let t = trimmed
                guard !t.isEmpty, t != step.text else { return }
                model.refinePlan(step.instruction(t)); dismiss()
            }
            .buttonStyle(PillStyle(height: 50, icone: "arrow.up"))
            .disabled(trimmed.isEmpty || trimmed == step.text || dictation.phase != .idle)
        }
        .onAppear { text = step.text }
        .onDisappear { dictation.stop() }
    }
}

// MARK: - Sans organisation, sans poste

/// Sans jeton support : rien à saisir, l'administrateur configure ce Mac.
struct SupportNoOrg: View {
    var body: some View {
        Panneau {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aucune organisation configurée").font(rounded(32, .bold))
                Text("Contactez votre administrateur.").font(rounded(18, .medium)).opacity(0.92)
            }
        } corps: {
            Text("Votre service informatique dépose sur ce Mac le jeton du support de votre organisation. Les postes et leurs demandes apparaissent alors ici, sans rien saisir.")
                .font(rounded(18)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Organisation configurée, mais aucun poste à suivre : chargement, liste vide ou serveur injoignable.
struct SupportNoPoste: View {
    let model: HelperModel
    var body: some View {
        Panneau {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.orgTitle).font(rounded(32, .bold))
                Text(!model.orgLoaded && model.orgError == nil ? "Chargement des postes…"
                     : model.orgError == nil ? "Aucun poste inscrit pour l’instant" : "Postes indisponibles")
                    .font(rounded(18, .medium)).opacity(0.92)
            }
        } corps: {
            HStack(spacing: 16) {
                if !model.orgLoaded && model.orgError == nil { ProgressView().controlSize(.small) }
                Text(model.orgError ?? "Les postes de l’organisation apparaissent ici dès que PapAI y est installé.")
                    .font(rounded(18)).foregroundStyle(model.orgError == nil ? T.muted : T.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.orgError != nil {
                    Button("Réessayer") { Task { await model.refreshOrg() } }.buttonStyle(supportSecondary(48))
                }
            }
        }
    }
}

// MARK: - Réglages

/// Réglages en lecture seule : tout vient de la configuration de l'organisation.
struct SupportSettings: View {
    @Bindable var model: HelperModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SupportSheet(titre: "Réglages", sousTitre: model.helperName.map { "Support : \($0)" }, width: 560, height: 420) {
            sheetLabel("Organisation")
            Text(model.orgConfigured ? model.orgTitle : "Aucune organisation configurée").font(rounded(20, .bold))
            if let o = model.org {
                Text(URL(string: o.server)?.host ?? o.server).font(rounded(15)).foregroundStyle(T.muted)
                Text("\(model.people.count) poste\(model.people.count > 1 ? "s" : "")").font(rounded(15)).foregroundStyle(T.muted)
            }
            if let e = model.orgError { Text(e).font(rounded(14, .semibold)).foregroundStyle(T.danger) }
            Text(model.orgConfigured ? "Configuré par votre administrateur. Rien à régler sur ce Mac."
                 : "Contactez votre administrateur : il dépose le jeton du support de votre organisation sur ce Mac.")
                .font(rounded(15)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if model.isConfigured {
                HStack(spacing: 8) {
                    Circle().fill(model.connected ? Color(hex: 0x12A15E) : (model.linkError == nil ? T.muted : T.danger))
                        .frame(width: 8, height: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(SupportConnection.line(model, now: ctx.date)).font(rounded(14)).foregroundStyle(T.muted)
                    }
                }
            }
        } bas: {
            if model.orgConfigured {
                Button("Réessayer maintenant") { model.reconnect(); Task { await model.refreshOrg() } }
                    .buttonStyle(supportSecondary(50))
            }
            Spacer()
            Button("Fermer") { dismiss() }.buttonStyle(PillStyle(height: 50)).keyboardShortcut(.cancelAction)
        }
    }
}
