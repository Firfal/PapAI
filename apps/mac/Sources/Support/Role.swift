import AppKit
import SwiftUI

/// Rôle de ce Mac, choisi au premier lancement et mémorisé (`UserDefaults`, clé `role`).
/// - `aide` : la personne aidée, l'app PapAI habituelle ;
/// - `support` : celui qui aide, l'app du support (comme sur iPhone).
/// `-role aide` ou `-role support` au lancement le force (démo, rendus).
enum AppRole: String {
    case aide, support

    static let key = "role"
    static var saved: AppRole? { UserDefaults.standard.string(forKey: key).flatMap(AppRole.init) }

    /// Changer de rôle : on oublie le choix et on relance PapAI, pour repartir
    /// d'une app propre (aucune connexion de l'autre rôle ne reste ouverte).
    @MainActor static func forgetAndRelaunch() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
        let bundle = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", bundle]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// Premier écran : « Je me fais aider » ou « J'aide quelqu'un ».
struct RoleChoiceView: View {
    var choose: (AppRole) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                LogotypePapai().frame(height: 36)
                Spacer()
            }
            .padding(.top, 24)
            Panneau {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bienvenue dans PapAI").font(rounded(34, .bold))
                    Text("Sur cet ordinateur, vous êtes…").font(rounded(19, .medium)).opacity(0.92)
                }
            } corps: {
                VStack(spacing: 24) {
                    HStack(spacing: 24) {
                        carte(.aide, icone: "hand.raised.fill", titre: "Je me fais aider",
                              texte: "Je demande une assistance. Holo agit sur cet ordinateur, avec l'accord de mon support.",
                              mascotte: .joyeuse)
                        carte(.support, icone: "person.2.fill", titre: "J'aide quelqu'un",
                              texte: "Je suis le support. Je reçois les demandes, je valide le plan de Holo et je suis l'assistance en direct.",
                              mascotte: .calme)
                    }
                    Text("Vous pourrez changer plus tard dans les Réglages.")
                        .font(rounded(15)).foregroundStyle(T.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 28)
        .foregroundStyle(T.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(T.fond.ignoresSafeArea())
    }

    private func carte(_ role: AppRole, icone: String, titre: String, texte: String, mascotte: Mascotte.Humeur) -> some View {
        Button { choose(role) } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: icone).font(.system(size: 26, weight: .semibold)).foregroundStyle(T.accent)
                        .frame(width: 64, height: 64).background(Circle().fill(T.mint))
                    Spacer()
                    Mascotte(humeur: mascotte, anime: false).frame(width: 64, height: 64)
                }
                Text(titre).font(rounded(28, .bold))
                Text(texte).font(rounded(17)).foregroundStyle(T.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text("Choisir").font(rounded(18, .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(T.leaf)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.card)
                    .overlay(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).strokeBorder(T.line, lineWidth: 1.5))
                    .shadow(color: T.ombre.opacity(0.08), radius: 18, y: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: T.rBig, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(T.ink)
        .accessibilityLabel("\(titre). \(texte)")
    }
}
