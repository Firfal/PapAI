import SwiftUI

// Même mascotte que l'app Mac (apps/mac/Sources/Theme.swift), pour une identité commune.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// La mascotte : la papaye « Pastel » de l'icône (`brand/papai-mascotte-pastel.svg`),
/// avec quelques humeurs pour accompagner la personne sans ajouter de texte.
/// Décorative : jamais seule porteuse d'une information.
struct Mascotte: View {
    enum Humeur { case joyeuse, ecoute, reflechit, bravo, calme }
    var humeur: Humeur = .joyeuse
    var anime = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var souffle = false
    /// Discrète : immobile, sauf un léger souffle pendant l'écoute.
    private var bouge: Bool { anime && !reduceMotion && humeur == .ecoute }

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 256
            ctx.translateBy(x: (size.width - 256 * k) / 2, y: (size.height - 256 * k) / 2)
            ctx.scaleBy(x: k, y: k)
            MascotteDessin.dessiner(in: &ctx, humeur: humeur)
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(x: 1, y: souffle ? 1.015 : 1, anchor: .bottom)
        .onAppear(perform: suivre)
        .onChange(of: bouge) { _, _ in suivre() }
        .accessibilityHidden(true)
    }

    private func suivre() {
        if bouge {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { souffle = true }
        } else {
            withTransaction(Transaction(animation: nil)) { souffle = false }
        }
    }
}

extension Mascotte {
    /// Tailles de Papaye, volontairement petites : elle accompagne sans prendre la place du texte.
    enum Taille {
        static let carte: CGFloat = 52
        static let attente: CGFloat = 60
        static let arret: CGFloat = 64
    }
}

enum MascotteDessin {
    static let trait = Color(hex: 0x3E3631)
    static let peau = Color(hex: 0x79BE8C)
    static let chair = Color(hex: 0xF9A56C)
    static let creme = Color(hex: 0xFFEDDA)
    static let joues = Color(hex: 0xF58A6A)

    static func dessiner(in ctx: inout GraphicsContext, humeur: Mascotte.Humeur) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        let rond = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)

        var tige = Path()
        tige.move(to: pt(122, 32))
        tige.addCurve(to: pt(132, 8), control1: pt(120, 20), control2: pt(124, 12))
        tige.addLine(to: pt(140, 14))
        tige.addCurve(to: pt(135, 32), control1: pt(135, 18), control2: pt(133, 24))
        tige.closeSubpath()
        ctx.fill(tige, with: .color(trait))

        var feuille = Path()
        feuille.move(to: pt(136, 20))
        feuille.addCurve(to: pt(178, 15), control1: pt(150, 4), control2: pt(172, 6))
        feuille.addCurve(to: pt(136, 20), control1: pt(166, 28), control2: pt(148, 28))
        feuille.closeSubpath()
        ctx.fill(feuille, with: .color(peau))
        ctx.stroke(feuille, with: .color(trait), style: StrokeStyle(lineWidth: 6, lineJoin: .round))

        var corps = Path()
        corps.move(to: pt(128, 28))
        corps.addCurve(to: pt(203, 132), control1: pt(170, 28), control2: pt(198, 74))
        corps.addCurve(to: pt(128, 244), control1: pt(209, 198), control2: pt(174, 244))
        corps.addCurve(to: pt(53, 132), control1: pt(82, 244), control2: pt(47, 198))
        corps.addCurve(to: pt(128, 28), control1: pt(58, 74), control2: pt(86, 28))
        corps.closeSubpath()
        ctx.fill(corps, with: .color(peau))
        ctx.stroke(corps, with: .color(trait), style: StrokeStyle(lineWidth: 9, lineJoin: .round))

        var interieur = Path()
        interieur.move(to: pt(128, 44))
        interieur.addCurve(to: pt(188, 134), control1: pt(162, 44), control2: pt(184, 82))
        interieur.addCurve(to: pt(128, 228), control1: pt(193, 188), control2: pt(164, 228))
        interieur.addCurve(to: pt(68, 134), control1: pt(92, 228), control2: pt(63, 188))
        interieur.addCurve(to: pt(128, 44), control1: pt(72, 82), control2: pt(94, 44))
        interieur.closeSubpath()
        ctx.fill(interieur, with: .color(chair))

        var coeur = Path()
        coeur.move(to: pt(128, 150))
        coeur.addCurve(to: pt(157, 186), control1: pt(146, 150), control2: pt(157, 166))
        coeur.addCurve(to: pt(128, 218), control1: pt(157, 206), control2: pt(144, 218))
        coeur.addCurve(to: pt(99, 186), control1: pt(112, 218), control2: pt(99, 206))
        coeur.addCurve(to: pt(128, 150), control1: pt(99, 166), control2: pt(110, 150))
        coeur.closeSubpath()
        ctx.fill(coeur, with: .color(creme))
        ctx.stroke(coeur, with: .color(trait), style: StrokeStyle(lineWidth: 5))
        for (x, y) in [(118, 166), (138, 166), (110, 184), (128, 182), (146, 184), (118, 201), (138, 201), (128, 212)] as [(CGFloat, CGFloat)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)), with: .color(trait))
        }

        let joueTaille: CGFloat = humeur == .bravo ? 1.25 : 1
        for x in [88, 168] as [CGFloat] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 11 * joueTaille, y: 127, width: 22 * joueTaille, height: 14)),
                     with: .color(joues.opacity(humeur == .calme ? 0.6 : 1)))
        }

        func oeilOuvert(_ cx: CGFloat, regard: CGPoint = .zero) {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 9, y: 100, width: 18, height: 24)), with: .color(trait))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 6.5 + regard.x, y: 103.5 + regard.y, width: 7, height: 7)), with: .color(.white))
        }
        func oeilArc(_ cx: CGFloat, haut: Bool) {
            var a = Path()
            a.move(to: pt(cx - 10, 112))
            a.addQuadCurve(to: pt(cx + 10, 112), control: pt(cx, haut ? 102 : 122))
            ctx.stroke(a, with: .color(trait), style: rond)
        }

        switch humeur {
        case .joyeuse:
            oeilOuvert(104); oeilArc(152, haut: true)
        case .ecoute:
            oeilOuvert(104); oeilOuvert(152)
        case .reflechit:
            oeilOuvert(104, regard: pt(3, -2)); oeilOuvert(152, regard: pt(3, -2))
        case .bravo:
            oeilArc(104, haut: true); oeilArc(152, haut: true)
        case .calme:
            oeilArc(104, haut: false); oeilArc(152, haut: false)
        }

        var bouche = Path()
        switch humeur {
        case .joyeuse:
            bouche.move(to: pt(112, 132)); bouche.addQuadCurve(to: pt(144, 132), control: pt(128, 152)); bouche.closeSubpath()
            ctx.fill(bouche, with: .color(trait))
            ctx.stroke(bouche, with: .color(trait), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        case .bravo:
            bouche.move(to: pt(108, 130)); bouche.addQuadCurve(to: pt(148, 130), control: pt(128, 158)); bouche.closeSubpath()
            ctx.fill(bouche, with: .color(trait))
            ctx.stroke(bouche, with: .color(trait), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        case .ecoute:
            ctx.fill(Path(ellipseIn: CGRect(x: 120, y: 131, width: 16, height: 14)), with: .color(trait))
        case .reflechit:
            bouche.move(to: pt(118, 138)); bouche.addLine(to: pt(138, 136))
            ctx.stroke(bouche, with: .color(trait), style: rond)
        case .calme:
            bouche.move(to: pt(116, 134)); bouche.addQuadCurve(to: pt(140, 134), control: pt(128, 142))
            ctx.stroke(bouche, with: .color(trait), style: rond)
        }
    }
}

/// Une bulle de parole, la pointe à gauche vers la mascotte.
struct Bulle<Content: View>: View {
    var fill: Color = Soin.card
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 22).padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(fill)
                    .overlay(alignment: .leading) {
                        PointeBulle().fill(fill).frame(width: 16, height: 22).offset(x: -12)
                    }
            )
    }
}

private struct PointeBulle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.midY - 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.midY + 2))
        p.closeSubpath()
        return p
    }
}
