import SwiftUI

/// Premier lancement : deux autorisations, expliquées simplement.
struct PermissionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Deux autorisations, une seule fois").font(rounded(44, .semibold)).tracking(-0.6)
                Text("Pour que Quentin puisse vous aider, macOS doit vous demander votre accord. Cliquez sur chaque bouton, puis cochez PapAI dans la liste qui s'ouvre.")
                    .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                row(ok: model.screenOK, title: "Voir mon écran",
                    detail: "Pour que Holo voie ce que vous voyez. Jamais sans votre demande.",
                    action: Permissions.requestScreen)
                row(ok: model.axOK, title: "Utiliser la souris et le clavier",
                    detail: "Pour cliquer à votre place, uniquement après l'accord de Quentin.",
                    action: Permissions.requestAccessibility)
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.ink).padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))
            Button { model.permissionsDismissed = true } label: {
                Text(model.screenOK && model.axOK ? "Continuer" : "Plus tard").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillStyle(height: 78))
        }
    }

    private func row(ok: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 18) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 32)).foregroundStyle(ok ? T.accent : T.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(rounded(22, .semibold))
                Text(detail).font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !ok {
                Button("Autoriser", action: action).buttonStyle(PillStyle(height: 48))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Réglages").font(rounded(30, .semibold))
            field("Prénom", text: $name, prompt: "Jeanne")
            field("Serveur", text: $server, prompt: "ws://localhost:8000/ws/bridge")
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.buttonStyle(PillStyle(filled: false, height: 50))
                Button("Enregistrer") {
                    UserDefaults.standard.set(server, forKey: "server")
                    UserDefaults.standard.set(name, forKey: "firstName")
                    model.reconnect()
                    Task { await model.refreshLessons() }
                    dismiss()
                }.buttonStyle(PillStyle(height: 50))
            }
        }
        .foregroundStyle(T.ink)
        .padding(32).frame(width: 520).background(T.bg)
        .onAppear { server = model.serverURL; name = model.firstName }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(rounded(15, .semibold)).foregroundStyle(T.muted)
            TextField(prompt, text: text).textFieldStyle(.plain).font(rounded(18))
                .padding(16).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.card))
        }
    }
}
