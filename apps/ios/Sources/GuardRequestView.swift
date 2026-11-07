import SwiftUI

struct GuardRequestView: View {
    @Bindable var model: HelperModel
    @State private var confirmDismiss = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(Soin.ink)
                    Text(model.lastAlert?.title ?? "Démarche à vérifier")
                        .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Soin.ink)
                    Text("PapAI a arrêté l'assistance : démarche suspecte")
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(Soin.ink)
                    Text(model.lastAlert?.detail ?? "")
                        .font(.system(size: 17, design: .rounded)).foregroundStyle(Soin.secondary)
                    if let who = model.guardAcknowledgedBy {
                        Text("\(who) s'en occupe. Prenez contact avec votre proche à son numéro habituel.")
                            .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Soin.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28).soinCard(radius: 36)
                if confirmDismiss {
                    Text("Vous connaissez cette démarche ? Cela ferme l'alerte, sans relancer l'assistance.")
                        .font(.system(size: 17, design: .rounded)).foregroundStyle(Soin.ink)
                    Button("Confirmer : c'est normal") { model.dismissGuardAlert() }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.ink, text: Soin.card))
                        .disabled(!model.connected)
                    Button("Retour") { confirmDismiss = false }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                } else {
                    Button("Je m'en occupe") { model.acknowledgeGuardAlert() }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.ink, text: Soin.card))
                        .disabled(!model.connected || model.guardAcknowledgedBy != nil)
                    Button("C'est normal") { confirmDismiss = true }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                        .disabled(!model.connected)
                }
                if !model.connected {
                    Text("Reconnectez-vous pour répondre à cette alerte.")
                        .font(.system(size: 16, design: .rounded)).foregroundStyle(Soin.secondary)
                }
            }
            .padding(24).padding(.vertical, 20)
        }
        .background(Soin.bg)
    }
}
