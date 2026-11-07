import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Palette « Soin » réchauffée par la papaye du logo. Les textes secondaires
/// gardent un contraste d'au moins 4,5:1 sur le fond et sur la menthe.
enum T {
    static let bg = Color(hex: 0xF6F1EA)
    static let card = Color.white
    static let ink = Color(hex: 0x111312)
    static let muted = Color(hex: 0x5C625E)
    static let accent = Color(hex: 0x2E9E5B)
    /// Vert du texte sur menthe ou blanc (le vert d'accent y est trop clair).
    static let leaf = Color(hex: 0x1C7240)
    static let mint = Color(hex: 0xE2F2E7)
    static let papaya = Color(hex: 0xF58A3A)
    /// Chair de papaye : fond des moments heureux (fin d'aide, bienvenue).
    static let peach = Color(hex: 0xFFE7D2)
    static let danger = Color(hex: 0xC8442F)
    static let r: CGFloat = 28
    static let rBig: CGFloat = 36
}

/// Taille du texte choisie à l'accueil. Grande par défaut, l'interface est
/// déjà dessinée en gros caractères ; « Très grande » agrandit tout.
enum TextScale {
    static let options: [(label: String, value: Double)] = [("Grande", 1.0), ("Très grande", 1.18)]
    static var current: Double {
        get { let v = UserDefaults.standard.double(forKey: "textScale"); return v > 0 ? v : 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: "textScale") }
    }
}

func rounded(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    .system(size: size * CGFloat(TextScale.current), weight: weight, design: .rounded)
}

/// Bouton pilule : encre pleine par défaut, blanc en secondaire.
struct PillStyle: ButtonStyle {
    var filled = true
    var height: CGFloat = 64
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(rounded(20, .semibold))
            .foregroundStyle(filled ? Color.white : T.ink)
            .padding(.horizontal, 30)
            .frame(height: height)
            .background(Capsule().fill(filled ? T.ink : T.card))
            .overlay(Capsule().strokeBorder(filled ? Color.clear : T.ink.opacity(0.08), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}

struct Header: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 14) {
            LogotypePapai().frame(height: 36 * CGFloat(model.textScale))
            Spacer()
            // Rien quand tout va bien : la personne aidée n'a pas à se soucier de la connexion.
            if !model.connected {
                HStack(spacing: 10) {
                    Circle().fill(T.muted.opacity(0.5)).frame(width: 10, height: 10)
                    Text("Pas de connexion pour le moment").font(rounded(16, .medium))
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(Capsule().fill(T.card))
            }
            Button { model.showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42).background(Circle().fill(T.card))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réglages")
        }
        .foregroundStyle(T.ink)
    }
}

struct LogotypePapai: View {
    var body: some View {
        ZStack {
            LettresPapai().fill(T.ink)
            PapayePapai().fill(Color(hex: 0xF58A3A))
        }
        .aspectRatio(235.0 / 101.0, contentMode: .fit)
        .accessibilityLabel("PapAI")
    }
}

private struct LettresPapai: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 32.064, y: 96.96))
        p.addCurve(to: CGPoint(x: 23.424, y: 95.136), control1: CGPoint(x: 28.928, y: 96.96), control2: CGPoint(x: 26.048, y: 96.352))
        p.addCurve(to: CGPoint(x: 16.992, y: 90.144), control1: CGPoint(x: 20.8, y: 93.92), control2: CGPoint(x: 18.656, y: 92.256))
        p.addCurve(to: CGPoint(x: 14.112, y: 82.752), control1: CGPoint(x: 15.328, y: 87.968), control2: CGPoint(x: 14.368, y: 85.504))
        p.addLine(to: CGPoint(x: 14.112, y: 63.072))
        p.addCurve(to: CGPoint(x: 16.992, y: 55.584), control1: CGPoint(x: 14.368, y: 60.32), control2: CGPoint(x: 15.328, y: 57.824))
        p.addCurve(to: CGPoint(x: 23.424, y: 50.304), control1: CGPoint(x: 18.656, y: 53.344), control2: CGPoint(x: 20.8, y: 51.584))
        p.addCurve(to: CGPoint(x: 32.064, y: 48.384), control1: CGPoint(x: 26.048, y: 49.024), control2: CGPoint(x: 28.928, y: 48.384))
        p.addCurve(to: CGPoint(x: 43.776, y: 51.552), control1: CGPoint(x: 36.48, y: 48.384), control2: CGPoint(x: 40.384, y: 49.44))
        p.addCurve(to: CGPoint(x: 51.84, y: 60.192), control1: CGPoint(x: 47.232, y: 53.664), control2: CGPoint(x: 49.92, y: 56.544))
        p.addCurve(to: CGPoint(x: 54.816, y: 72.672), control1: CGPoint(x: 53.824, y: 63.84), control2: CGPoint(x: 54.816, y: 68))
        p.addCurve(to: CGPoint(x: 51.84, y: 85.152), control1: CGPoint(x: 54.816, y: 77.344), control2: CGPoint(x: 53.824, y: 81.504))
        p.addCurve(to: CGPoint(x: 43.776, y: 93.792), control1: CGPoint(x: 49.92, y: 88.8), control2: CGPoint(x: 47.232, y: 91.68))
        p.addCurve(to: CGPoint(x: 32.064, y: 96.96), control1: CGPoint(x: 40.384, y: 95.904), control2: CGPoint(x: 36.48, y: 96.96))
        p.closeSubpath()
        p.move(to: CGPoint(x: 5.18402, y: 115.68))
        p.addLine(to: CGPoint(x: 5.18402, y: 49.344))
        p.addLine(to: CGPoint(x: 19.872, y: 49.344))
        p.addLine(to: CGPoint(x: 19.872, y: 61.344))
        p.addLine(to: CGPoint(x: 17.472, y: 72.672))
        p.addLine(to: CGPoint(x: 19.68, y: 84))
        p.addLine(to: CGPoint(x: 19.68, y: 115.68))
        p.addLine(to: CGPoint(x: 5.18402, y: 115.68))
        p.closeSubpath()
        p.move(to: CGPoint(x: 29.376, y: 83.712))
        p.addCurve(to: CGPoint(x: 34.848, y: 82.272), control1: CGPoint(x: 31.488, y: 83.712), control2: CGPoint(x: 33.312, y: 83.232))
        p.addCurve(to: CGPoint(x: 38.592, y: 78.336), control1: CGPoint(x: 36.448, y: 81.312), control2: CGPoint(x: 37.696, y: 80))
        p.addCurve(to: CGPoint(x: 39.936, y: 72.672), control1: CGPoint(x: 39.488, y: 76.672), control2: CGPoint(x: 39.936, y: 74.784))
        p.addCurve(to: CGPoint(x: 38.592, y: 66.912), control1: CGPoint(x: 39.936, y: 70.496), control2: CGPoint(x: 39.488, y: 68.576))
        p.addCurve(to: CGPoint(x: 34.848, y: 63.072), control1: CGPoint(x: 37.696, y: 65.248), control2: CGPoint(x: 36.448, y: 63.968))
        p.addCurve(to: CGPoint(x: 29.472, y: 61.632), control1: CGPoint(x: 33.312, y: 62.112), control2: CGPoint(x: 31.52, y: 61.632))
        p.addCurve(to: CGPoint(x: 24, y: 63.072), control1: CGPoint(x: 27.424, y: 61.632), control2: CGPoint(x: 25.6, y: 62.112))
        p.addCurve(to: CGPoint(x: 20.352, y: 66.912), control1: CGPoint(x: 22.464, y: 63.968), control2: CGPoint(x: 21.248, y: 65.248))
        p.addCurve(to: CGPoint(x: 19.008, y: 72.672), control1: CGPoint(x: 19.456, y: 68.576), control2: CGPoint(x: 19.008, y: 70.496))
        p.addCurve(to: CGPoint(x: 20.256, y: 78.336), control1: CGPoint(x: 19.008, y: 74.784), control2: CGPoint(x: 19.424, y: 76.672))
        p.addCurve(to: CGPoint(x: 24, y: 82.272), control1: CGPoint(x: 21.152, y: 80), control2: CGPoint(x: 22.4, y: 81.312))
        p.addCurve(to: CGPoint(x: 29.376, y: 83.712), control1: CGPoint(x: 25.6, y: 83.232), control2: CGPoint(x: 27.392, y: 83.712))
        p.closeSubpath()
        p.move(to: CGPoint(x: 78.8858, y: 96.96))
        p.addCurve(to: CGPoint(x: 67.3658, y: 93.792), control1: CGPoint(x: 74.5978, y: 96.96), control2: CGPoint(x: 70.7578, y: 95.904))
        p.addCurve(to: CGPoint(x: 59.3978, y: 85.152), control1: CGPoint(x: 64.0378, y: 91.68), control2: CGPoint(x: 61.3818, y: 88.8))
        p.addCurve(to: CGPoint(x: 56.5178, y: 72.672), control1: CGPoint(x: 57.4778, y: 81.504), control2: CGPoint(x: 56.5178, y: 77.344))
        p.addCurve(to: CGPoint(x: 59.3978, y: 60.192), control1: CGPoint(x: 56.5178, y: 68), control2: CGPoint(x: 57.4778, y: 63.84))
        p.addCurve(to: CGPoint(x: 67.3658, y: 51.552), control1: CGPoint(x: 61.3818, y: 56.544), control2: CGPoint(x: 64.0378, y: 53.664))
        p.addCurve(to: CGPoint(x: 78.8858, y: 48.384), control1: CGPoint(x: 70.7578, y: 49.44), control2: CGPoint(x: 74.5978, y: 48.384))
        p.addCurve(to: CGPoint(x: 87.3338, y: 50.208), control1: CGPoint(x: 82.0218, y: 48.384), control2: CGPoint(x: 84.8378, y: 48.992))
        p.addCurve(to: CGPoint(x: 93.5738, y: 55.296), control1: CGPoint(x: 89.8938, y: 51.424), control2: CGPoint(x: 91.9738, y: 53.12))
        p.addCurve(to: CGPoint(x: 96.2618, y: 62.592), control1: CGPoint(x: 95.1738, y: 57.408), control2: CGPoint(x: 96.0698, y: 59.84))
        p.addLine(to: CGPoint(x: 96.2618, y: 82.752))
        p.addCurve(to: CGPoint(x: 93.5738, y: 90.144), control1: CGPoint(x: 96.0698, y: 85.504), control2: CGPoint(x: 95.1738, y: 87.968))
        p.addCurve(to: CGPoint(x: 87.4298, y: 95.136), control1: CGPoint(x: 92.0378, y: 92.256), control2: CGPoint(x: 89.9898, y: 93.92))
        p.addCurve(to: CGPoint(x: 78.8858, y: 96.96), control1: CGPoint(x: 84.8698, y: 96.352), control2: CGPoint(x: 82.0218, y: 96.96))
        p.closeSubpath()
        p.move(to: CGPoint(x: 81.8618, y: 83.712))
        p.addCurve(to: CGPoint(x: 89.4458, y: 80.64), control1: CGPoint(x: 84.9978, y: 83.712), control2: CGPoint(x: 87.5258, y: 82.688))
        p.addCurve(to: CGPoint(x: 92.3258, y: 72.672), control1: CGPoint(x: 91.3658, y: 78.528), control2: CGPoint(x: 92.3258, y: 75.872))
        p.addCurve(to: CGPoint(x: 90.9818, y: 66.912), control1: CGPoint(x: 92.3258, y: 70.496), control2: CGPoint(x: 91.8778, y: 68.576))
        p.addCurve(to: CGPoint(x: 87.3338, y: 63.072), control1: CGPoint(x: 90.1498, y: 65.248), control2: CGPoint(x: 88.9338, y: 63.968))
        p.addCurve(to: CGPoint(x: 81.9578, y: 61.632), control1: CGPoint(x: 85.7978, y: 62.112), control2: CGPoint(x: 84.0058, y: 61.632))
        p.addCurve(to: CGPoint(x: 76.4858, y: 63.072), control1: CGPoint(x: 79.9098, y: 61.632), control2: CGPoint(x: 78.0858, y: 62.112))
        p.addCurve(to: CGPoint(x: 72.7418, y: 66.912), control1: CGPoint(x: 74.9498, y: 63.968), control2: CGPoint(x: 73.7018, y: 65.248))
        p.addCurve(to: CGPoint(x: 71.3978, y: 72.672), control1: CGPoint(x: 71.8458, y: 68.576), control2: CGPoint(x: 71.3978, y: 70.496))
        p.addCurve(to: CGPoint(x: 72.7418, y: 78.336), control1: CGPoint(x: 71.3978, y: 74.784), control2: CGPoint(x: 71.8458, y: 76.672))
        p.addCurve(to: CGPoint(x: 76.4858, y: 82.272), control1: CGPoint(x: 73.6378, y: 80), control2: CGPoint(x: 74.8858, y: 81.312))
        p.addCurve(to: CGPoint(x: 81.8618, y: 83.712), control1: CGPoint(x: 78.0858, y: 83.232), control2: CGPoint(x: 79.8778, y: 83.712))
        p.closeSubpath()
        p.move(to: CGPoint(x: 91.7498, y: 96))
        p.addLine(to: CGPoint(x: 91.7498, y: 83.424))
        p.addLine(to: CGPoint(x: 93.9578, y: 72.096))
        p.addLine(to: CGPoint(x: 91.7498, y: 60.768))
        p.addLine(to: CGPoint(x: 91.7498, y: 49.344))
        p.addLine(to: CGPoint(x: 106.15, y: 49.344))
        p.addLine(to: CGPoint(x: 106.15, y: 96))
        p.addLine(to: CGPoint(x: 91.7498, y: 96))
        p.closeSubpath()
        p.move(to: CGPoint(x: 140.492, y: 96.96))
        p.addCurve(to: CGPoint(x: 131.852, y: 95.136), control1: CGPoint(x: 137.356, y: 96.96), control2: CGPoint(x: 134.476, y: 96.352))
        p.addCurve(to: CGPoint(x: 125.42, y: 90.144), control1: CGPoint(x: 129.228, y: 93.92), control2: CGPoint(x: 127.084, y: 92.256))
        p.addCurve(to: CGPoint(x: 122.54, y: 82.752), control1: CGPoint(x: 123.756, y: 87.968), control2: CGPoint(x: 122.796, y: 85.504))
        p.addLine(to: CGPoint(x: 122.54, y: 63.072))
        p.addCurve(to: CGPoint(x: 125.42, y: 55.584), control1: CGPoint(x: 122.796, y: 60.32), control2: CGPoint(x: 123.756, y: 57.824))
        p.addCurve(to: CGPoint(x: 131.852, y: 50.304), control1: CGPoint(x: 127.084, y: 53.344), control2: CGPoint(x: 129.228, y: 51.584))
        p.addCurve(to: CGPoint(x: 140.492, y: 48.384), control1: CGPoint(x: 134.476, y: 49.024), control2: CGPoint(x: 137.356, y: 48.384))
        p.addCurve(to: CGPoint(x: 152.204, y: 51.552), control1: CGPoint(x: 144.908, y: 48.384), control2: CGPoint(x: 148.812, y: 49.44))
        p.addCurve(to: CGPoint(x: 160.268, y: 60.192), control1: CGPoint(x: 155.66, y: 53.664), control2: CGPoint(x: 158.348, y: 56.544))
        p.addCurve(to: CGPoint(x: 163.244, y: 72.672), control1: CGPoint(x: 162.252, y: 63.84), control2: CGPoint(x: 163.244, y: 68))
        p.addCurve(to: CGPoint(x: 160.268, y: 85.152), control1: CGPoint(x: 163.244, y: 77.344), control2: CGPoint(x: 162.252, y: 81.504))
        p.addCurve(to: CGPoint(x: 152.204, y: 93.792), control1: CGPoint(x: 158.348, y: 88.8), control2: CGPoint(x: 155.66, y: 91.68))
        p.addCurve(to: CGPoint(x: 140.492, y: 96.96), control1: CGPoint(x: 148.812, y: 95.904), control2: CGPoint(x: 144.908, y: 96.96))
        p.closeSubpath()
        p.move(to: CGPoint(x: 113.612, y: 115.68))
        p.addLine(to: CGPoint(x: 113.612, y: 49.344))
        p.addLine(to: CGPoint(x: 128.3, y: 49.344))
        p.addLine(to: CGPoint(x: 128.3, y: 61.344))
        p.addLine(to: CGPoint(x: 125.9, y: 72.672))
        p.addLine(to: CGPoint(x: 128.108, y: 84))
        p.addLine(to: CGPoint(x: 128.108, y: 115.68))
        p.addLine(to: CGPoint(x: 113.612, y: 115.68))
        p.closeSubpath()
        p.move(to: CGPoint(x: 137.804, y: 83.712))
        p.addCurve(to: CGPoint(x: 143.276, y: 82.272), control1: CGPoint(x: 139.916, y: 83.712), control2: CGPoint(x: 141.74, y: 83.232))
        p.addCurve(to: CGPoint(x: 147.02, y: 78.336), control1: CGPoint(x: 144.876, y: 81.312), control2: CGPoint(x: 146.124, y: 80))
        p.addCurve(to: CGPoint(x: 148.364, y: 72.672), control1: CGPoint(x: 147.916, y: 76.672), control2: CGPoint(x: 148.364, y: 74.784))
        p.addCurve(to: CGPoint(x: 147.02, y: 66.912), control1: CGPoint(x: 148.364, y: 70.496), control2: CGPoint(x: 147.916, y: 68.576))
        p.addCurve(to: CGPoint(x: 143.276, y: 63.072), control1: CGPoint(x: 146.124, y: 65.248), control2: CGPoint(x: 144.876, y: 63.968))
        p.addCurve(to: CGPoint(x: 137.9, y: 61.632), control1: CGPoint(x: 141.74, y: 62.112), control2: CGPoint(x: 139.948, y: 61.632))
        p.addCurve(to: CGPoint(x: 132.428, y: 63.072), control1: CGPoint(x: 135.852, y: 61.632), control2: CGPoint(x: 134.028, y: 62.112))
        p.addCurve(to: CGPoint(x: 128.78, y: 66.912), control1: CGPoint(x: 130.892, y: 63.968), control2: CGPoint(x: 129.676, y: 65.248))
        p.addCurve(to: CGPoint(x: 127.436, y: 72.672), control1: CGPoint(x: 127.884, y: 68.576), control2: CGPoint(x: 127.436, y: 70.496))
        p.addCurve(to: CGPoint(x: 128.684, y: 78.336), control1: CGPoint(x: 127.436, y: 74.784), control2: CGPoint(x: 127.852, y: 76.672))
        p.addCurve(to: CGPoint(x: 132.428, y: 82.272), control1: CGPoint(x: 129.58, y: 80), control2: CGPoint(x: 130.828, y: 81.312))
        p.addCurve(to: CGPoint(x: 137.804, y: 83.712), control1: CGPoint(x: 134.028, y: 83.232), control2: CGPoint(x: 135.82, y: 83.712))
        p.closeSubpath()
        p.move(to: CGPoint(x: 187.313, y: 96.96))
        p.addCurve(to: CGPoint(x: 175.793, y: 93.792), control1: CGPoint(x: 183.025, y: 96.96), control2: CGPoint(x: 179.185, y: 95.904))
        p.addCurve(to: CGPoint(x: 167.825, y: 85.152), control1: CGPoint(x: 172.465, y: 91.68), control2: CGPoint(x: 169.809, y: 88.8))
        p.addCurve(to: CGPoint(x: 164.945, y: 72.672), control1: CGPoint(x: 165.905, y: 81.504), control2: CGPoint(x: 164.945, y: 77.344))
        p.addCurve(to: CGPoint(x: 167.825, y: 60.192), control1: CGPoint(x: 164.945, y: 68), control2: CGPoint(x: 165.905, y: 63.84))
        p.addCurve(to: CGPoint(x: 175.793, y: 51.552), control1: CGPoint(x: 169.809, y: 56.544), control2: CGPoint(x: 172.465, y: 53.664))
        p.addCurve(to: CGPoint(x: 187.313, y: 48.384), control1: CGPoint(x: 179.185, y: 49.44), control2: CGPoint(x: 183.025, y: 48.384))
        p.addCurve(to: CGPoint(x: 195.761, y: 50.208), control1: CGPoint(x: 190.449, y: 48.384), control2: CGPoint(x: 193.265, y: 48.992))
        p.addCurve(to: CGPoint(x: 202.001, y: 55.296), control1: CGPoint(x: 198.321, y: 51.424), control2: CGPoint(x: 200.401, y: 53.12))
        p.addCurve(to: CGPoint(x: 204.689, y: 62.592), control1: CGPoint(x: 203.601, y: 57.408), control2: CGPoint(x: 204.497, y: 59.84))
        p.addLine(to: CGPoint(x: 204.689, y: 82.752))
        p.addCurve(to: CGPoint(x: 202.001, y: 90.144), control1: CGPoint(x: 204.497, y: 85.504), control2: CGPoint(x: 203.601, y: 87.968))
        p.addCurve(to: CGPoint(x: 195.857, y: 95.136), control1: CGPoint(x: 200.465, y: 92.256), control2: CGPoint(x: 198.417, y: 93.92))
        p.addCurve(to: CGPoint(x: 187.313, y: 96.96), control1: CGPoint(x: 193.297, y: 96.352), control2: CGPoint(x: 190.449, y: 96.96))
        p.closeSubpath()
        p.move(to: CGPoint(x: 190.289, y: 83.712))
        p.addCurve(to: CGPoint(x: 197.873, y: 80.64), control1: CGPoint(x: 193.425, y: 83.712), control2: CGPoint(x: 195.953, y: 82.688))
        p.addCurve(to: CGPoint(x: 200.753, y: 72.672), control1: CGPoint(x: 199.793, y: 78.528), control2: CGPoint(x: 200.753, y: 75.872))
        p.addCurve(to: CGPoint(x: 199.409, y: 66.912), control1: CGPoint(x: 200.753, y: 70.496), control2: CGPoint(x: 200.305, y: 68.576))
        p.addCurve(to: CGPoint(x: 195.761, y: 63.072), control1: CGPoint(x: 198.577, y: 65.248), control2: CGPoint(x: 197.361, y: 63.968))
        p.addCurve(to: CGPoint(x: 190.385, y: 61.632), control1: CGPoint(x: 194.225, y: 62.112), control2: CGPoint(x: 192.433, y: 61.632))
        p.addCurve(to: CGPoint(x: 184.913, y: 63.072), control1: CGPoint(x: 188.337, y: 61.632), control2: CGPoint(x: 186.513, y: 62.112))
        p.addCurve(to: CGPoint(x: 181.169, y: 66.912), control1: CGPoint(x: 183.377, y: 63.968), control2: CGPoint(x: 182.129, y: 65.248))
        p.addCurve(to: CGPoint(x: 179.825, y: 72.672), control1: CGPoint(x: 180.273, y: 68.576), control2: CGPoint(x: 179.825, y: 70.496))
        p.addCurve(to: CGPoint(x: 181.169, y: 78.336), control1: CGPoint(x: 179.825, y: 74.784), control2: CGPoint(x: 180.273, y: 76.672))
        p.addCurve(to: CGPoint(x: 184.913, y: 82.272), control1: CGPoint(x: 182.065, y: 80), control2: CGPoint(x: 183.313, y: 81.312))
        p.addCurve(to: CGPoint(x: 190.289, y: 83.712), control1: CGPoint(x: 186.513, y: 83.232), control2: CGPoint(x: 188.305, y: 83.712))
        p.closeSubpath()
        p.move(to: CGPoint(x: 200.177, y: 96))
        p.addLine(to: CGPoint(x: 200.177, y: 83.424))
        p.addLine(to: CGPoint(x: 202.385, y: 72.096))
        p.addLine(to: CGPoint(x: 200.177, y: 60.768))
        p.addLine(to: CGPoint(x: 200.177, y: 49.344))
        p.addLine(to: CGPoint(x: 214.577, y: 49.344))
        p.addLine(to: CGPoint(x: 214.577, y: 96))
        p.addLine(to: CGPoint(x: 200.177, y: 96))
        p.closeSubpath()
        p.move(to: CGPoint(x: 222.039, y: 96))
        p.addLine(to: CGPoint(x: 222.039, y: 49.344))
        p.addLine(to: CGPoint(x: 236.727, y: 49.344))
        p.addLine(to: CGPoint(x: 236.727, y: 96))
        p.addLine(to: CGPoint(x: 222.039, y: 96))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: -5, y: -15))
            .applying(CGAffineTransform(scaleX: rect.width / 235, y: rect.height / 101))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

private struct PapayePapai: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 230.789, y: 18.3313))
        p.addCurve(to: CGPoint(x: 239.058, y: 30.0756), control1: CGPoint(x: 235.343, y: 18.3313), control2: CGPoint(x: 238.459, y: 23.3646))
        p.addCurve(to: CGPoint(x: 230.789, y: 43.4977), control1: CGPoint(x: 239.777, y: 37.9851), control2: CGPoint(x: 235.822, y: 43.4977))
        p.addCurve(to: CGPoint(x: 222.52, y: 30.0756), control1: CGPoint(x: 225.756, y: 43.4977), control2: CGPoint(x: 221.801, y: 37.9851))
        p.addCurve(to: CGPoint(x: 230.789, y: 18.3313), control1: CGPoint(x: 223.119, y: 23.3646), control2: CGPoint(x: 226.235, y: 18.3313))
        p.closeSubpath()
        p.move(to: CGPoint(x: 230.07, y: 19.0503))
        p.addCurve(to: CGPoint(x: 231.508, y: 15.4551), control1: CGPoint(x: 229.95, y: 17.3725), control2: CGPoint(x: 230.43, y: 16.1741))
        p.addLine(to: CGPoint(x: 232.467, y: 16.294))
        p.addCurve(to: CGPoint(x: 231.748, y: 19.0503), control1: CGPoint(x: 231.748, y: 16.8932), control2: CGPoint(x: 231.508, y: 17.8519))
        p.addLine(to: CGPoint(x: 230.07, y: 19.0503))
        p.closeSubpath()
        return p.applying(CGAffineTransform(translationX: -5, y: -15))
            .applying(CGAffineTransform(scaleX: rect.width / 235, y: rect.height / 101))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
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
    private var bouge: Bool { souffle && anime && !reduceMotion }

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 256
            ctx.translateBy(x: (size.width - 256 * k) / 2, y: (size.height - 256 * k) / 2)
            ctx.scaleBy(x: k, y: k)
            MascotteDessin.dessiner(in: &ctx, humeur: humeur)
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(x: 1, y: bouge ? 1.025 : 1, anchor: .bottom)
        .rotationEffect(.degrees(humeur == .ecoute && bouge ? -3 : 0), anchor: .bottom)
        .onAppear {
            guard anime, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { souffle = true }
        }
        // « Réduire les animations » activé à chaud : la mascotte s'immobilise aussitôt.
        .onChange(of: reduceMotion) { _, reduit in
            if reduit {
                withTransaction(Transaction(animation: nil)) { souffle = false }
            } else if anime {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { souffle = true }
            }
        }
        .accessibilityHidden(true)
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
    var fill: Color = T.card
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
