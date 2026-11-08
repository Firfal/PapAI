import SwiftUI

/// Premier lancement : deux autorisations, expliquées simplement.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                Text("Deux autorisations, une seule fois").font(rounded(40, .bold)).tracking(-0.6)
                    .lineLimit(2).minimumScaleFactor(0.8)
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Pour que \(model.helperName) puisse vous aider, macOS doit vous demander votre accord. Cliquez sur chaque bouton, puis cochez PapAI dans la liste qui s'ouvre.")
                        .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    row(ok: model.screenOK, title: "Voir mon écran",
                        detail: "Pour que Holo voie ce que vous voyez. Jamais sans votre demande.",
                        action: Permissions.requestScreen)
                    row(ok: model.axOK, title: "Utiliser la souris et le clavier",
                        detail: "Pour cliquer à votre place, uniquement après l'accord de \(model.helperName).",
                        action: Permissions.requestAccessibility)
                    Spacer(minLength: 0)
                }
            }
            Button { model.permissionsDismissed = true } label: {
                Text(model.screenOK && model.axOK ? "Continuer" : "Plus tard").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillStyle(height: 78, icone: "arrow.right.circle", plein: true))
        }
    }

    private func row(ok: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        PermissionRow(ok: ok, title: title, detail: detail, action: action)
    }
}

struct PermissionRow: View {
    var ok: Bool
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 30)).foregroundStyle(ok ? Pastille.Ton.vert.texte : T.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(rounded(22, .semibold))
                Text(detail).font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !ok {
                Button("Autoriser", action: action).buttonStyle(PillStyle(height: 48, icone: "lock.open"))
            }
        }
        .padding(20)
        .champ(T.r)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Réglages").font(rounded(26, .bold))
                if !model.orgName.isEmpty {
                    Text("Poste géré par \(model.orgName)").font(rounded(13, .medium)).foregroundStyle(.white.opacity(0.92))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Prénom", text: $name, prompt: "Votre prénom")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { model.realtimeProtection }, set: { model.setRealtimeProtection($0) })) {
                            Text("Protection en temps réel").font(rounded(19, .semibold))
                        }
                        .toggleStyle(.switch).tint(T.accent)
                        Text(model.realtimeProtection
                             ? "Activée. PapAI repère les arnaques à partir des applications ouvertes, du titre de la fenêtre et du site visité. Jamais l'écran, jamais vos mots de passe."
                             : "Coupée. Rien ne part de cet ordinateur en dehors d'une assistance, et les arnaques ne sont plus repérées.")
                            .font(rounded(14)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mon support").font(rounded(19, .semibold))
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .semibold)).foregroundStyle(T.leaf)
                            Text("Support IT").font(rounded(17, .semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.line)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Support IT, validé")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.buttonStyle(PillStyle(filled: false, height: 50))
                Button("Enregistrer") {
                    // L'adresse du serveur ne se règle plus ici : elle vient de l'installation.
                    model.setFirstName(name)
                    dismiss()
                }.buttonStyle(PillStyle(height: 50, icone: "checkmark.circle"))
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(T.ink)
        .frame(width: 560, height: 580).background(T.bg)
        .onAppear { name = model.firstName }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(rounded(13, .semibold)).foregroundStyle(T.muted)
            TextField(prompt, text: text).textFieldStyle(.plain).font(rounded(15))
                .padding(16).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.line)))
        }
    }
}

