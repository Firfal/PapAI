import SwiftUI

struct GuardRequestView: View {
    @Bindable var model: HelperModel
    @State private var contact = false
    @State private var confirmDismiss = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40)).foregroundStyle(.orange)
                Text(model.lastAlert?.title ?? "Arnaque possible")
                    .font(.system(size: 32, weight: .bold)).foregroundStyle(Soin.ink)
                Text("L'assistance est arrêtée. Rien ne reprend sans une nouvelle demande.")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Soin.ink)
                Text(model.lastAlert?.detail ?? "")
                    .font(.system(size: 17)).foregroundStyle(Soin.secondary)
                Button { contact = true } label: {
                    Label("Rappeler mon proche", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.borderedProminent).tint(Soin.accent)
                Button("Je connais cette démarche : rejeter l'alerte") { confirmDismiss = true }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .disabled(!model.connected)
                if !model.connected { Text("Reconnectez-vous pour rejeter l'alerte.").foregroundStyle(Soin.secondary) }
            }
            .padding(28)
        }
        .background(Soin.bg)
        .alert("Rappelez \(model.senior)", isPresented: $contact) {
            Button("D'accord", role: .cancel) { }
        } message: {
            Text("Utilisez son numéro habituel dans Téléphone ou Contacts, jamais un numéro communiqué dans la demande suspecte.")
        }
        .confirmationDialog("Vous connaissez cette démarche ?", isPresented: $confirmDismiss, titleVisibility: .visible) {
            Button("Rejeter l'alerte", role: .destructive) { model.dismissGuardAlert() }
        } message: {
            Text("Cela ferme l'alerte, mais ne relance pas l'assistance.")
        }
    }
}
