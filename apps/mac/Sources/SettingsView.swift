import SwiftUI
import AppKit

/// Réglages de l'employé : taille du texte et protection. Le nom affiché et le support
/// viennent du poste (compte macOS, jeton de l'organisation) : rien à saisir ici.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Réglages").font(rounded(30, .bold))
                if !model.orgName.isEmpty {
                    Text("Poste géré par \(model.orgName)").font(rounded(15, .medium)).foregroundStyle(.white.opacity(0.92))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LangueReglage()
                    Toggle("Lire à voix haute", isOn: Binding(
                        get: { model.narration.enabled }, set: { model.narration.enabled = $0 }))
                        .font(rounded(22, .semibold)).toggleStyle(.switch).tint(T.accent)
                    Text("Holo décrit ses actions avec la voix française de cet ordinateur. La lecture se coupe pendant la dictée.")
                        .font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { model.realtimeProtection }, set: { model.setRealtimeProtection($0) })) {
                            Text("Protection en temps réel").font(rounded(22, .semibold))
                        }
                        .toggleStyle(.switch).tint(T.accent)
                        Text(model.realtimeProtection
                             ? String(localized: "Activée. PapAI repère les arnaques à partir des applications ouvertes, du titre de la fenêtre et du site visité. Jamais l'écran, jamais vos mots de passe.")
                             : String(localized: "Coupée. Rien ne part de cet ordinateur en dehors d'une assistance, et les arnaques ne sont plus repérées."))
                            .font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    MonSupport()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .buttonStyle(PillStyle(height: 50, icone: "checkmark.circle"))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(T.ink)
        .frame(width: 560, height: 580).background(T.bg)
    }
}

/// « Mon support » : le service informatique rattaché d'office à ce poste, en lecture seule.
/// Il vient du jeton déposé par l'IT (`orgToken`) : rien à relier ni à régler ici.
struct MonSupport: View {
    @Environment(AppModel.self) private var model

    private enum Etat { case rattache(String), enCours, aucun }

    private var etat: Etat {
        if !model.orgName.isEmpty { return .rattache(model.orgName) }
        return model.orgToken.isEmpty ? .aucun : .enCours
    }

    private var enLigne: Bool { model.connected && model.helpers.contains { $0.online } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mon support").font(rounded(22, .semibold))
            HStack(spacing: 14) {
                Image(systemName: icone)
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Circle().fill(couleurIcone))
                VStack(alignment: .leading, spacing: 4) {
                    Text(titre).font(rounded(20, .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(rounded(15)).foregroundStyle(enLigne ? T.leaf : T.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.card)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.line)))
            .accessibilityElement(children: .combine)
            if !isAucun {
                Text("Configuré par votre service informatique.")
                    .font(rounded(14)).foregroundStyle(T.muted)
            }
        }
    }

    private var isAucun: Bool {
        if case .aucun = etat { return true }
        return false
    }

    private var icone: String {
        switch etat {
        case .rattache: "person.fill.checkmark"
        case .enCours: "clock"
        case .aucun: "exclamationmark"
        }
    }

    private var couleurIcone: Color {
        if case .rattache = etat { return T.accent }
        return T.muted
    }

    private var titre: String {
        switch etat {
        case .rattache: String(localized: "Support IT")
        case .enCours: String(localized: "Support IT")
        case .aucun: String(localized: "Aucune organisation configurée")
        }
    }

    private var detail: String {
        switch etat {
        case .aucun:
            return String(localized: "Contactez votre service informatique.")
        case .enCours:
            return model.connected ? String(localized: "Rattachement à votre organisation en cours…") : String(localized: "Hors connexion pour le moment.")
        case .rattache:
            if !model.connected { return String(localized: "Hors connexion pour le moment.") }
            return enLigne ? String(localized: "En ligne") : String(localized: "Aucun agent en ligne : votre demande sera mise en attente.")
        }
    }
}


/// Langue de l'app : français (par défaut) ou anglais. Elle s'applique au prochain lancement,
/// PapAI se relance donc tout de suite.
struct LangueReglage: View {
    @State private var langue = (UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "fr").hasPrefix("en") ? "en" : "fr"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Langue").font(rounded(22, .semibold))
            Picker("Langue", selection: $langue) {
                Text(verbatim: "Français").tag("fr")
                Text(verbatim: "English").tag("en")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .onChange(of: langue) { _, l in
                UserDefaults.standard.set([l], forKey: "AppleLanguages")
                UserDefaults.standard.synchronize()
                // Relance : la langue de l'interface se choisit au démarrage.
                let url = Bundle.main.bundleURL
                let conf = NSWorkspace.OpenConfiguration(); conf.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, _ in
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                }
            }
        }
    }
}


/// Langue choisie dans les Réglages (au lancement) : sert à la dictée, à la voix et aux dates.
enum AppLangue {
    static var anglais: Bool {
        (Bundle.main.preferredLocalizations.first ?? "fr").hasPrefix("en")
    }
}
