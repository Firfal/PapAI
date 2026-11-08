import SwiftUI

struct GuardRequestView: View {
    @Bindable var model: HelperModel
    @State private var confirmDismiss = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(Soin.danger)
                        .frame(width: 60, height: 60).background(Soin.danger.opacity(0.1), in: Circle())
                    Text(model.lastAlert?.title ?? "Démarche à vérifier")
                        .font(.system(size: 28, weight: .bold)).foregroundStyle(Soin.ink)
                    Text("PapAI a arrêté l'assistance : démarche suspecte")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Soin.ink)
                    if !model.guardTask.isEmpty {
                        Text("« \(model.guardTask) »")
                            .font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
                    }
                    Text(instructions)
                        .font(.system(size: 17)).foregroundStyle(Soin.secondary)
                    if model.guardAcknowledged {
                        Text("Un support a vu l'alerte et s'en occupe")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28).soinCard(radius: 28)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Soin.danger, lineWidth: 2))
                if confirmDismiss {
                    Text("Vous connaissez cette démarche ? Cela ferme l'alerte, sans relancer l'assistance.")
                        .font(.system(size: 17)).foregroundStyle(Soin.ink)
                    Button("Confirmer : c'est normal") { model.dismissGuardAlert() }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.ink, text: Soin.card))
                        .disabled(!model.connected)
                    Button("Retour") { confirmDismiss = false }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                } else {
                    Button("Je m'en occupe") { model.acknowledgeGuardAlert() }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.ink, text: Soin.card))
                        .disabled(!model.connected || model.guardAcknowledged)
                    Button("C'est normal") { confirmDismiss = true }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                        .disabled(!model.connected)
                }
                if !model.connected {
                    Text("Reconnectez-vous pour répondre à cette alerte.")
                        .font(.system(size: 16)).foregroundStyle(Soin.secondary)
                }
            }
            .padding(24).padding(.vertical, 20)
        }
        .background { SoinBackground() }
    }

    private var instructions: String {
        let detail = model.lastAlert?.detail ?? ""
        guard !model.guardTask.isEmpty else { return detail }
        return detail.replacingOccurrences(of: "\nDemande : « \(model.guardTask) »", with: "")
    }
}
