import ActivityKit
import SwiftUI

/// La grande alerte de l'écran verrouillé (Live Activity), partagée entre l'app
/// et l'extension qui la dessine.
///
/// Elle vit tant que l'iPhone est lié à un proche : discrète quand tout va bien
/// (« Vous aidez Sophie »), elle devient une grande carte sombre qui
/// allume l'écran quand le proche demande de l'aide, puis suit l'avancement.
struct HelpActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case watching      // rien en cours
            case planning      // Holo prépare un plan
            case request       // un plan attend l'accord de l'aidant
            case needsYou      // Holo bloque et attend l'aidant
            case working       // Holo agit
            case paused        // le proche a mis en pause
            case done          // terminé
        }
        var phase: Phase
        var senior: String
        var task: String
        var detail: String
        var step: Int
        var steps: Int
        var since: Date

        /// L'aidant doit agir : la carte passe en grand.
        var urgent: Bool { phase == .request || phase == .needsYou }
    }
}

/// Mêmes couleurs que `Soin` dans l'app (le widget ne voit pas `Theme.swift`).
enum PapColors {
    /// Encre bleu nuit : fond de la carte urgente.
    static let ink = Color(red: 0x11/255, green: 0x1A/255, blue: 0x2E/255)
    static let accent = Color(red: 0x1F/255, green: 0x5B/255, blue: 0xFF/255)
    /// Bleu clair lisible sur l'encre (Dynamic Island, points).
    static let accentBright = Color(red: 0x7A/255, green: 0xA4/255, blue: 0xFF/255)
    static let card = Color.white
    static let secondary = Color(red: 0x55/255, green: 0x60/255, blue: 0x74/255)
    /// Dégradé du bouton principal : texte blanc à 4,5:1 et 6,3:1 aux deux bouts.
    static let primary = LinearGradient(colors: [Color(red: 0x2E/255, green: 0x6B/255, blue: 0xFF/255),
                                                 Color(red: 0x1A/255, green: 0x4F/255, blue: 0xE6/255)],
                                        startPoint: .top, endPoint: .bottom)
}

extension HelpActivityAttributes.ContentState {
    var headline: String {
        switch phase {
        case .watching: return "Vous aidez \(senior)"
        case .planning: return "\(senior) demande de l'aide"
        case .request: return "\(senior) demande de l'aide"
        case .needsYou: return "\(senior) a besoin de vous"
        case .working: return "Holo aide \(senior)"
        case .paused: return "\(senior) a mis l'aide en pause"
        case .done: return "C'est fait"
        }
    }

    var subline: String {
        switch phase {
        case .watching: return "PapAI vous prévient s'il faut aider."
        case .planning: return task.isEmpty ? "Holo prépare un plan…" : "« \(task) »"
        case .request: return task.isEmpty ? "Un plan attend votre accord." : "« \(task) »"
        case .needsYou: return detail.isEmpty ? "Holo attend votre aide." : detail
        case .working, .paused: return task.isEmpty ? "Sur l'ordinateur de \(senior)" : "« \(task) »"
        case .done: return task.isEmpty ? "Tout est réglé pour \(senior)." : "« \(task) »"
        }
    }

    var cta: String? {
        switch phase {
        case .request: return "Voir le plan"
        case .needsYou: return "Répondre"
        default: return nil
        }
    }

    /// Les mots courts de la Dynamic Island.
    var short: String {
        switch phase {
        case .watching: return "En veille"
        case .planning: return "Demande"
        case .request: return "Plan à valider"
        case .needsYou: return "À vous"
        case .working: return steps > 0 ? "\(min(step, steps))/\(steps)" : "En cours"
        case .paused: return "Pause"
        case .done: return "Fait"
        }
    }

    var progress: Double {
        guard steps > 0 else { return phase == .done ? 1 : 0.1 }
        return min(1, max(0.05, Double(max(step - 1, 0)) / Double(steps)))
    }
}
