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

/// Couleurs du widget, tirées de la palette commune (`apps/shared/Palette.swift`).
enum PapColors {
    /// Encre bleu nuit : fond de la carte urgente.
    static let ink = T.ink
    static let accent = T.accent
    /// Bleu clair lisible sur l'encre (Dynamic Island, points).
    static let accentBright = Color(hex: 0x7AA4FF)
    static let card = T.card
    static let secondary = T.muted
    static let primary = T.primary
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
