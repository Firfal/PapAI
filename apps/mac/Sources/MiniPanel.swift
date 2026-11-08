import AppKit
import SwiftUI

/// Petit encart flottant en bas à droite de l'écran.
///
/// - Pendant qu'Holo agit, la grande fenêtre PapAI s'efface pour qu'on voie ce
///   qu'il fait : seul cet encart reste, avec l'avancement, Pause et Arrêter.
/// - Quand on réduit PapAI à la main, il reste aussi, pour revenir en un clic.
/// Il appartient à l'app PapAI : il est donc exclu des captures envoyées à Holo,
/// et ses clics restent possibles pendant le verrou des entrées (`InputLock`).
@MainActor
final class MiniPanel {
    static let shared = MiniPanel()

    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(model: AppModel) {
        let p = panel ?? make(model: model)
        panel = p
        place(p)
        p.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    /// Cadre de l'encart, en points écran, origine en haut à gauche (comme les clics de Holo).
    func protectedRect() -> CGRect? {
        guard let p = panel, p.isVisible else { return nil }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let f = p.frame
        return CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height).insetBy(dx: -4, dy: -4)
    }

    private func make(model: AppModel) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 132),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        let host = NSHostingView(rootView: MiniView().environment(model).preferredColorScheme(.light))
        host.frame = p.contentRect(forFrameRect: p.frame)
        p.contentView = host
        return p
    }

    private func place(_ p: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        let size = p.frame.size
        p.setFrameOrigin(NSPoint(x: v.maxX - size.width - 18, y: v.minY + 18))
    }
}

/// Le contenu de l'encart.
private struct MiniView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Mascotte(humeur: model.paused || !model.sessionOpen ? .calme : .joyeuse, anime: false)
                    .frame(width: Mascotte.Taille.encart, height: Mascotte.Taille.encart)
                Text(model.state == .active && !model.paused ? model.currentAction ?? title : title)
                    .font(rounded(17, .semibold)).foregroundStyle(T.ink).lineLimit(1)
                    .help(model.currentAction ?? title)
                Spacer(minLength: 0)
                Button { model.expandWindow() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                        .frame(width: 30, height: 30).background(Circle().fill(T.bg))
                }
                .buttonStyle(.plain).accessibilityLabel("Ouvrir PapAI en grand")
            }
            if model.sessionOpen {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(T.bg)
                        Capsule().fill(T.primary).frame(width: max(10, g.size.width * fraction))
                    }
                }
                .frame(height: 8)
                HStack(spacing: 8) {
                    if model.state == .active || model.state == .awaiting_helper || model.paused {
                        Button { model.togglePause() } label: {
                            Label(model.paused ? "Reprendre" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill")
                                .font(rounded(15, .semibold)).foregroundStyle(T.ink)
                                .frame(maxWidth: .infinity).frame(height: 38)
                                .background(Capsule().fill(T.bg))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { model.stop() } label: {
                        Label("Arrêter", systemImage: "stop.fill")
                            .font(rounded(15, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(Capsule().fill(T.ink))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Arrêter l'assistance (Échap)")
                }
            } else {
                Button {
                    MicPresence.shared.demande = true
                    model.backHome()
                    model.expandWindow()
                } label: {
                    Label(MicPresence.shared.microPresent ? "Parler à PapAI" : "Écrire à PapAI",
                          systemImage: MicPresence.shared.microPresent ? "mic.fill" : "pencil")
                        .font(rounded(16, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(T.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 340, height: 132, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(T.line))
        .id(model.textScale)
    }

    private var title: String {
        if model.sessionWhere == "web" && model.sessionOpen
            && (model.state == .active || model.state == .awaiting_helper) {
            return "Holo travaille dans Chrome PapAI"
        }
        if model.paused && model.sessionOpen { return "L'aide est en pause" }
        switch model.state {
        case .planning: return "Holo prépare la suite…"
        case .awaiting_approval: return "\(model.HelperName) vérifie"
        case .active: return "\(model.carer) s'en occupe"
        case .awaiting_helper: return "\(model.HelperName) vous aide"
        case .done: return "C'est fait !"
        default: return "PapAI"
        }
    }

    private var fraction: Double {
        switch model.state {
        case .planning: return 0.15
        case .awaiting_approval: return 0.35
        case .active, .awaiting_helper:
            if let s = model.planStep, !model.plan.isEmpty {
                return 0.45 + 0.5 * Double(max(s - 1, 0)) / Double(model.plan.count)
            }
            return 0.5
        default: return 1
        }
    }
}
