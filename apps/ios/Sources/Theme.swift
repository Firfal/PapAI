import SwiftUI

/// Palette « Soin » réchauffée par la papaye du logo, comme sur le Mac.
/// Les textes secondaires gardent un contraste d'au moins 4,5:1 sur le fond et sur la menthe.
enum Soin {
    static let bg = Color(red: 0xF6/255, green: 0xF1/255, blue: 0xEA/255)
    static let card = Color.white
    static let ink = Color(red: 0x11/255, green: 0x13/255, blue: 0x12/255)
    static let secondary = Color(red: 0x5C/255, green: 0x62/255, blue: 0x5E/255)
    static let accent = Color(red: 0x2E/255, green: 0x9E/255, blue: 0x5B/255)
    static let accentSoft = Color(red: 0xE2/255, green: 0xF2/255, blue: 0xE7/255)
    /// Vert du texte sur menthe, pêche ou blanc (le vert d'accent y est trop clair).
    static let leaf = Color(red: 0x1C/255, green: 0x72/255, blue: 0x40/255)
    static let papaya = Color(red: 0xF5/255, green: 0x8A/255, blue: 0x3A/255)
    /// Chair de papaye : fond des moments heureux (fin d'aide).
    static let peach = Color(red: 0xFF/255, green: 0xE7/255, blue: 0xD2/255)
    static let danger = Color(red: 0xC8/255, green: 0x44/255, blue: 0x2F/255)
}

extension View {
    func soinCard(_ fill: Color = Soin.card, radius: CGFloat = 22) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Bouton plein en capsule (ink par défaut).
struct CapsuleButtonStyle: ButtonStyle {
    var fill: Color = Soin.ink
    var text: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 58, height: 58)
            .background(Soin.card, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Place les enfants côte à côte et passe à la ligne.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); w = max(w, x - spacing)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
