import SwiftUI

// Palette unique de PapAI, partagée par l'app Mac (aidé et support), l'app
// iPhone du support et son widget (apps/mac/project.yml, apps/ios/project.yml).

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Palette « Bleu clair » : fond bleu-lavande très clair, cartes blanches à
/// ombre douce, un seul accent bleu. Textes secondaires et bleus de texte à au
/// moins 4,5:1 sur le blanc et sur le fond ; le rouge des alertes ne change pas.
enum T {
    /// Fond uni (feuilles, encart) ; la fenêtre principale prend `fond`, en dégradé.
    static let bg = Color(hex: 0xF1F4FD)
    static let card = Color.white
    static let ink = Color(hex: 0x141A33)
    static let muted = Color(hex: 0x5A6178)
    /// Bleu d'accent (4,5:1 sur blanc) : icônes, barres d'avancement, boutons.
    static let accent = Color(hex: 0x2F6EF7)
    /// Bleu de texte sur blanc ou bleu pâle.
    static let leaf = Color(hex: 0x1D4FD7)
    /// Bleu pâle : pastilles, ronds d'icône, encarts d'information.
    static let mint = Color(hex: 0xEAF1FF)
    /// Pépin du logo, réservé à la marque.
    static let papaya = Color(hex: 0xF58A3A)
    /// Violet pâle : moments heureux (fin d'aide, bienvenue).
    static let peach = Color(hex: 0xF1ECFF)
    static let danger = Color(hex: 0xC8442F)
    /// Champs et surfaces dans une carte blanche.
    static let field = Color(hex: 0xF2F4FA)
    /// Séparateurs et bords fins.
    static let line = Color(hex: 0xE3E7F2)
    static let r: CGFloat = 18
    static let rBig: CGFloat = 24

    static let blueLight = Color(hex: 0x4C8DFF)
    static let blueDeep = Color(hex: 0x1A56E0)
    /// En-tête : dégradé bleu vif, titre blanc.
    /// Blanc à 5:1 à gauche (où sont les titres), 3,7:1 à droite : réservé aux grands titres.
    static let header = LinearGradient(colors: [Color(hex: 0x1F5FF0), Color(hex: 0x3D7FFF)], startPoint: .leading, endPoint: .trailing)
    /// Bouton principal : bleu assez soutenu pour un texte blanc à 4,5:1 partout.
    static let primary = LinearGradient(colors: [accent, blueDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Fond de la fenêtre : bleuté en haut, lavande en bas.
    static let fond = LinearGradient(colors: [Color(hex: 0xEDF2FE), Color(hex: 0xF2EFFC)], startPoint: .top, endPoint: .bottom)
    static let ombre = Color(hex: 0x2A3F8F)
    /// Point « en ligne ».
    static let online = Color(hex: 0x12A15E)
}

/// Tons des pastilles d'état pâles (`Pastille` sur Mac, `StatusPill` sur iPhone).
enum TonPastille {
    case bleu, violet, vert, orange, gris
    var fond: Color {
        switch self {
        case .bleu: T.mint
        case .violet: Color(hex: 0xF1EAFE)
        case .vert: Color(hex: 0xE4F5EA)
        case .orange: Color(hex: 0xFFF0E0)
        case .gris: Color(hex: 0xEEF0F5)
        }
    }
    /// Textes à au moins 4,5:1 sur leur fond.
    var texte: Color {
        switch self {
        case .bleu: T.leaf
        case .violet: Color(hex: 0x6236C7)
        case .vert: Color(hex: 0x1C6E3F)
        case .orange: Color(hex: 0x9A4706)
        case .gris: Color(hex: 0x4D5468)
        }
    }
}
