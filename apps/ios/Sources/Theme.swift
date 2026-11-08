import SwiftUI

/// Noms de la palette côté iPhone. Une seule palette pour tout PapAI : chaque
/// couleur vient de `T` (`apps/shared/Palette.swift`), la même que sur le Mac.
enum Soin {
    static let bg = T.bg
    static let card = T.card
    /// Champs de saisie : gris très clair.
    static let field = T.field
    /// Filet des cartes et des champs.
    static let hairline = T.line
    static let ink = T.ink
    static let secondary = T.muted
    /// Bleu d'accent (icônes, étape en cours, onglet choisi).
    static let accent = T.accent
    /// Bleu de texte sur blanc ou bleu pâle.
    static let accentText = T.leaf
    /// Fond pâle des cartes et pastilles bleues.
    static let accentSoft = T.mint
    /// Bouts du dégradé du bouton principal (ombres bleues).
    static let gradientTop = T.accent
    static let gradientBottom = T.blueDeep
    /// Vert du texte « terminé ».
    static let leaf = TonPastille.vert.texte
    /// Point « en ligne ».
    static let online = T.online
    /// Rouge du gardien et des erreurs.
    static let danger = T.danger

    static var primary: LinearGradient { T.primary }
    /// Ombre diffuse des cartes, teintée de bleu.
    static let shadow = T.ombre.opacity(0.08)
}

/// Fond d'écran : léger dégradé bleuté vers lavande.
struct SoinBackground: View {
    var body: some View {
        T.fond.ignoresSafeArea()
    }
}

/// Bandeau d'en-tête bleu dégradé, qui passe sous la barre d'état.
struct SoinHeaderBackground: View {
    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
            .fill(T.header)
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

/// Pastille d'état pâle et arrondie (même rendu que `Pastille` sur Mac).
struct StatusPill: View {
    enum Tone { case blue, violet, green, orange, gray }
    let text: String
    var tone: Tone = .blue
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.bold)).accessibilityHidden(true) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(ton.texte)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(ton.fond, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var ton: TonPastille {
        switch tone {
        case .blue: .bleu
        case .violet: .violet
        case .green: .vert
        case .orange: .orange
        case .gray: .gris
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
