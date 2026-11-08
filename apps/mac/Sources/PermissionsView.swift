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
                    row(ok: model.screenOK, title: String(localized: "Voir mon écran"),
                        detail: String(localized: "Pour que Holo voie ce que vous voyez. Jamais sans votre demande."),
                        action: Permissions.requestScreen)
                    row(ok: model.axOK, title: String(localized: "Utiliser la souris et le clavier"),
                        detail: String(localized: "Pour cliquer à votre place, uniquement après l'accord de \(model.helperName)."),
                        action: Permissions.requestAccessibility)
                    Spacer(minLength: 0)
                }
            }
            Button { model.permissionsDismissed = true } label: {
                Text(model.screenOK && model.axOK ? "Continuer" : String(localized: "Plus tard")).frame(maxWidth: .infinity)
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
