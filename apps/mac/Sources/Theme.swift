import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

enum T {
    static let bg = Color(hex: 0xEEF0EE)
    static let card = Color.white
    static let ink = Color(hex: 0x111312)
    static let muted = Color(hex: 0x7A807C)
    static let accent = Color(hex: 0x2E9E5B)
    static let mint = Color(hex: 0xE2F2E7)
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}

struct Header: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 14) {
            Text("PapAI")
                .font(rounded(22, .semibold))
            Text("·").foregroundStyle(T.muted)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))))
                .font(rounded(18)).foregroundStyle(T.muted)
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
