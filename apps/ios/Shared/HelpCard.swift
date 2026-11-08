import SwiftUI

/// La carte de l'écran verrouillé. En grand et en sombre quand il faut agir.
struct LockScreenCard: View {
    let s: HelpActivityAttributes.ContentState

    var body: some View {
        if s.urgent { urgent } else { calm }
    }

    /// Le moment « il faut y aller » : gros titre, la demande, un seul bouton.
    private var urgent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("Mascot").resizable().scaledToFit().frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("PAPAI").font(.system(size: 12, weight: .bold)).kerning(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(s.since, style: .relative)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.trailing)
            }
            Text(s.headline)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                .padding(.top, 10)
            Text(s.subline)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                .padding(.top, 4)
            if let cta = s.cta {
                HStack(spacing: 6) {
                    Text(cta)
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(PapColors.primary, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .padding(.top, 12)
            }
        }
        .padding(18)
    }

    /// Le reste du temps : une ligne calme, et l'avancement quand Holo agit.
    private var calm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image("Mascot").resizable().scaledToFit().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.headline).font(.system(size: 17, weight: .bold))
                        .foregroundStyle(PapColors.ink).lineLimit(1).minimumScaleFactor(0.8)
                    Text(s.subline).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PapColors.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if s.phase == .working || s.phase == .paused {
                    Text(s.short).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(s.phase == .paused ? PapColors.secondary : PapColors.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(s.phase == .paused ? PapColors.secondary.opacity(0.12) : PapColors.accent.opacity(0.1), in: Capsule())
                }
            }
            if s.phase == .working || s.phase == .paused || s.phase == .planning {
                Bar(value: s.phase == .planning ? 0.08 : s.progress,
                    track: PapColors.ink.opacity(0.08),
                    fill: s.phase == .paused ? PapColors.secondary : PapColors.accent)
            }
        }
        .padding(16)
    }
}

struct Bar: View {
    let value: Double
    let track: Color
    let fill: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(8, g.size.width * value))
            }
        }
        .frame(height: 6)
    }
}
