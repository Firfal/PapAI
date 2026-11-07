import ActivityKit
import SwiftUI

/// La grande alerte de l'écran verrouillé (Live Activity), partagée entre l'app
/// et l'extension qui la dessine.
///
/// Elle vit tant que l'iPhone est lié à un proche : discrète quand tout va bien
/// (« Vous veillez sur Sophie »), elle devient une grande carte sombre qui
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

enum PapColors {
    static let ink = Color(red: 0x11/255, green: 0x13/255, blue: 0x12/255)
    static let accent = Color(red: 0x2E/255, green: 0x9E/255, blue: 0x5B/255)
    static let accentBright = Color(red: 0x5B/255, green: 0xD1/255, blue: 0x8A/255)
    static let card = Color.white
    static let secondary = Color(red: 0x7A/255, green: 0x80/255, blue: 0x7C/255)
}

extension HelpActivityAttributes.ContentState {
    var headline: String {
        switch phase {
        case .watching: return "Vous veillez sur \(senior)"
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
