import SwiftUI

/// Palette « Soin » : fond bleu-lavande très clair, cartes blanches, un seul accent bleu vif.
/// Contrastes vérifiés (AA, 4,5:1) : accent et texte secondaire sur blanc et sur le fond,
/// texte blanc sur les deux bouts du dégradé bleu, texte des pastilles sur leur fond pâle.
enum Soin {
    /// Bas du fond (et des barres posées en bas d'écran), lavande très pâle.
    static let bg = Color(hex: 0xF2F1FC)
    /// Haut du fond, bleuté.
    static let bgTop = Color(hex: 0xE9F0FF)
    static let card = Color.white
    /// Champs de saisie : gris très clair.
    static let field = Color(hex: 0xF2F4F8)
    /// Filet des cartes et des champs.
    static let hairline = Color(hex: 0xE4E8F1)
    static let ink = Color(hex: 0x111A2E)
    static let secondary = Color(hex: 0x556074)
    /// Bleu d'accent (texte, icônes, étape en cours) : 5,3:1 sur blanc.
    static let accent = Color(hex: 0x1F5BFF)
    /// Fond pâle des cartes et pastilles bleues.
    static let accentSoft = Color(hex: 0xE8EFFF)
    /// Dégradé du bouton principal et de l'en-tête : blanc à 4,5:1 et 6,3:1 aux deux bouts.
    static let gradientTop = Color(hex: 0x2E6BFF)
    static let gradientBottom = Color(hex: 0x1A4FE6)
    /// Vert du texte « terminé » et des pastilles vertes.
    static let leaf = Color(hex: 0x16794C)
    /// Point « en ligne ».
    static let online = Color(hex: 0x12A15E)
    /// Rouge du gardien et des erreurs : inchangé, impossible à confondre avec l'accent.
    static let danger = Color(red: 0xC8/255, green: 0x44/255, blue: 0x2F/255)

    static var primary: LinearGradient {
        LinearGradient(colors: [gradientTop, gradientBottom], startPoint: .top, endPoint: .bottom)
    }
    /// Ombre diffuse des cartes, teintée de bleu.
    static let shadow = Color(hex: 0x1E3A8A).opacity(0.08)
}

/// Fond d'écran : léger dégradé bleuté vers lavande.
struct SoinBackground: View {
    var body: some View {
        LinearGradient(colors: [Soin.bgTop, Color(hex: 0xF4F6FE), Soin.bg], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Bandeau d'en-tête bleu dégradé, qui passe sous la barre d'état.
struct SoinHeaderBackground: View {
    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: [Soin.gradientTop, Soin.gradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: Soin.gradientTop.opacity(0.28), radius: 18, y: 8)
            .ignoresSafeArea(edges: .top)
    }
}

extension View {
    /// Carte arrondie : blanche avec filet et ombre douce ; teintée (bleu pâle…) avec un filet de la même teinte.
    func soinCard(_ fill: Color = Soin.card, radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let white = fill == Soin.card
        return background {
            shape.fill(fill)
                .overlay(shape.strokeBorder(white ? Soin.hairline : Soin.accent.opacity(0.12), lineWidth: 1))
                .shadow(color: white ? Soin.shadow : .clear, radius: 14, y: 6)
        }
    }

    /// Champ de saisie : gris très clair, arrondi, avec un filet.
    func soinField(radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Soin.field, in: shape)
            .overlay(shape.strokeBorder(Soin.hairline, lineWidth: 1))
    }
}

/// Pastille d'état pâle et arrondie.
struct StatusPill: View {
    enum Tone { case blue, violet, green, orange, gray }
    let text: String
    var tone: Tone = .blue
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(colors.text)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(colors.fill, in: Capsule())
    }

    private var colors: (text: Color, fill: Color) {
        switch tone {
        case .blue: (Soin.accent, Soin.accentSoft)
        case .violet: (Color(hex: 0x6235D9), Color(hex: 0xF0EAFF))
        case .green: (Soin.leaf, Color(hex: 0xE3F6EA))
        case .orange: (Color(hex: 0xA7480B), Color(hex: 0xFEEEDD))
        case .gray: (Color(hex: 0x475467), Color(hex: 0xEEF0F4))
        }
    }
}

/// Bouton en pilule. Par défaut (ou `fill: Soin.accent`) : le bouton principal bleu dégradé avec
/// une ombre bleue. `fill: Soin.card` : bouton secondaire blanc et discret. Autre couleur : pleine.
struct CapsuleButtonStyle: ButtonStyle {
    var fill: Color?
    var text: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        CapsuleLabel(configuration: configuration, fill: fill, text: text)
    }

    private struct CapsuleLabel: View {
        let configuration: Configuration
        let fill: Color?
        let text: Color
        @Environment(\.isEnabled) private var enabled

        private var primary: Bool { fill == nil || fill == Soin.accent }
        private var secondary: Bool { fill == Soin.card }

        var body: some View {
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background {
                    if primary {
                        Capsule().fill(Soin.primary)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: Soin.gradientTop.opacity(enabled ? 0.35 : 0), radius: 12, y: 6)
                    } else if secondary {
                        Capsule().fill(Soin.card)
                            .overlay(Capsule().strokeBorder(Soin.hairline, lineWidth: 1))
                            .shadow(color: Soin.shadow, radius: 8, y: 3)
                    } else {
                        Capsule().fill(fill ?? Soin.ink)
                    }
                }
                .opacity(configuration.isPressed ? 0.85 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.spring(duration: 0.25), value: configuration.isPressed)
        }
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 58, height: 58)
            .background {
                Circle().fill(Soin.card)
                    .overlay(Circle().strokeBorder(Soin.hairline, lineWidth: 1))
                    .shadow(color: Soin.shadow, radius: 8, y: 3)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
