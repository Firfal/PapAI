import AppKit
import SwiftUI
import UserNotifications

// Mode support sur Mac : la logique est celle de l'app iPhone (`HelperModel`,
// apps/ios/Sources), les écrans sont redessinés pour une fenêtre Mac.

/// Notifications macOS : une demande, une question de Holo ou une alerte du
/// gardien s'affichent en bannière, même quand PapAI est devant.
final class SupportNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SupportNotifications()

    func setUp() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Point d'entrée du mode support.
struct SupportApp: View {
    @State private var model = HelperModel()

    var body: some View {
        SupportRoot(model: model)
            .task {
                SupportNotifications.shared.setUp()
                model.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.wakeUp()
            }
    }
}

enum SupportConnection {
    @MainActor static func line(_ m: HelperModel, now: Date) -> String {
        if m.connected { return "Connecté à \(m.displayHost)" }
        guard let e = m.linkError else { return "Connexion à \(m.displayHost)…" }
        guard let at = m.retryAt else { return e }
        let n = Int(at.timeIntervalSince(now).rounded(.up))
        return n > 0 ? "\(e), nouvel essai dans \(n) s" : "\(e), nouvel essai…"
    }
}

struct SupportRoot: View {
    @Bindable var model: HelperModel
    @State private var onglet = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SupportHeader(model: model)
            if !model.orgConfigured {
                SupportNoOrg()
            } else if !model.isConfigured {
                SupportNoPoste(model: model)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Onglets(options: [("Tickets", 0), ("Utilisateurs", 1), ("Mes automates", 2)], selection: $onglet)
                        .frame(maxWidth: 520)
                    switch onglet {
                    case 0:
                        SupportTickets(model: model) { p in model.switchTo(p); onglet = 1 }
                    case 2:
                        SupportAutomates(model: model)
                    default:
                        HStack(alignment: .top, spacing: 22) {
                            PeopleSidebar(model: model).frame(width: 236)
                            VStack(alignment: .leading, spacing: 12) {
                                if !model.connected { LostBar(model: model) }
                                if let reason = model.sensitiveRefusal { refusal(reason) }
                                content
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 28)
        .foregroundStyle(T.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(T.fond.ignoresSafeArea())
        .disabled(model.guardAlertId != nil)
        .overlay { if model.guardAlertId != nil { SupportGuardView(model: model) } }
        .overlay(alignment: .bottom) { toast }
        .animation(.spring(duration: 0.35), value: model.toast)
        .animation(.easeInOut(duration: 0.25), value: model.screen)
        // Une assistance démarre : on montre l'utilisateur concerné, quel que soit l'onglet.
        .onChange(of: model.screen) { _, s in if s != .idle { onglet = 1 } }
        .sheet(item: $model.sheet) { _ in SupportSettings(model: model) }
    }

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .idle:
            // Hors assistance : les tickets de l'utilisateur choisi, sous l'accueil.
            VStack(alignment: .leading, spacing: 14) {
                ProfilUtilisateur(model: model)
                Text("Historique des demandes").font(rounded(19, .bold))
                SupportTickets(model: model, only: model.helperKey) { _ in }
            }
        case .waiting: SupportWaiting(model: model, text: "En attente de l’autorisation de \(model.senior)")
        case .planning: SupportWaiting(model: model, text: "Holo regarde l’écran…")
        case .approval: SupportApproval(model: model)
        case .active: SupportActive(model: model)
        case .helper: SupportHelperView(model: model)
        case .done: SupportDone(model: model)
        case .stopped: SupportStopped(model: model)
        }
    }

    private func refusal(_ reason: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(T.danger)
            Text(reason).font(rounded(17)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Compris") { model.sensitiveRefusal = nil }.buttonStyle(PillStyle(height: 44))
        }
        .padding(18).carte()
    }

    @ViewBuilder private var toast: some View {
        if let t = model.toast {
            Text(verbatim: t)
                .font(rounded(16, .semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22).padding(.vertical, 13)
                .background(Capsule().fill(T.ink))
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - En-tête et barre latérale

struct SupportHeader: View {
    @Bindable var model: HelperModel
    var body: some View {
        HStack(spacing: 14) {
            LogotypePapai().frame(height: 36)
            Pastille(texte: model.orgTitle, icone: "building.2.fill", ton: .bleu, taille: 14)
            Spacer()
            if model.isConfigured {
                if model.connected {
                    Pastille(texte: "Connecté", icone: "checkmark.circle.fill", ton: .vert, taille: 14)
                } else {
                    Pastille(texte: "Hors connexion", icone: "wifi.slash", ton: .gris, taille: 14)
                }
            }
            if let n = model.helperName, !n.isEmpty {
                Text(n).font(rounded(16, .semibold))
            }
            Button { model.sheet = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(T.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(T.card).shadow(color: T.ombre.opacity(0.1), radius: 10, y: 3))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réglages")
        }
        .padding(.top, 24)
    }
}

/// État de la connexion quand elle ne marche pas : la vraie raison et le prochain essai.
struct LostBar: View {
    let model: HelperModel
    var body: some View {
        HStack(spacing: 12) {
            if model.linkError == nil || model.retryAt != nil {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(SupportConnection.line(model, now: ctx.date)).font(rounded(15, .semibold))
            }
            Spacer()
            if model.linkError != nil {
                Button("Réessayer maintenant") { model.reconnect() }
                    .buttonStyle(.plain).font(rounded(14, .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.ink))
    }
}

/// Les postes de l'organisation : lequel suivre en détail, lequel demande une assistance.
/// La liste vient du serveur : rien à ajouter ni à retirer ici.
struct PeopleSidebar: View {
    @Bindable var model: HelperModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer").font(rounded(18, .semibold)).foregroundStyle(T.accent)
                Text("Postes").font(rounded(18, .bold)).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(model.people.count)").font(rounded(14, .semibold)).foregroundStyle(T.muted)
            }
            .accessibilityAddTraits(.isHeader)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(model.people) { p in row(p) }
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ p: Person) -> some View {
        let here = model.isCurrent(p)
        let asking = !here && model.othersAsking[p.key] == true
        let online = here ? (model.seniorOnline == true) : (model.othersOnline[p.key] == true)
        let name = People.title(p)
        let detail = People.detail(p)
        let state = asking ? "Demande une assistance" : online ? "En ligne" : "Hors ligne"
        return Button { model.switchTo(p) } label: {
            HStack(spacing: 12) {
                Text(String(name.prefix(1)).uppercased()).font(rounded(17, .bold))
                    .foregroundStyle(here ? T.leaf : T.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(here ? Color.white : T.mint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(rounded(17, .semibold)).lineLimit(1)
                    Text(detail.map { "\($0) · \(state)" } ?? state)
                        .font(rounded(13, .medium)).lineLimit(1)
                        .foregroundStyle(here ? Color.white.opacity(0.9) : asking ? T.danger : T.muted)
                }
                Spacer(minLength: 0)
                Circle().fill(online ? Color(hex: 0x12A15E) : T.line).frame(width: 9, height: 9)
            }
            .foregroundStyle(here ? Color.white : T.ink)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(here ? AnyShapeStyle(T.primary) : AnyShapeStyle(T.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(asking ? T.danger : here ? Color.clear : T.line, lineWidth: asking ? 2 : 1))
                    .shadow(color: T.ombre.opacity(here ? 0.18 : 0.05), radius: 10, y: 4)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel([name, detail, state].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - Éléments communs

/// En-tête bleu d'une demande : qui, depuis quand, quoi.
struct RequestHead: View {
    let model: HelperModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                Text("Demande de \(model.senior) · \(ago(model.requestStart))")
                    .font(rounded(15, .medium)).opacity(0.92)
            }
            Text(model.task.isEmpty ? "\(model.seniorTitle) demande une assistance" : "« \(model.task) »")
                .font(rounded(26, .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m < 1 ? "à l’instant" : "il y a \(m) min"
    }
}

/// Capture de l'écran de l’utilisateur ; en visée, un clic place le viseur.
struct SupportCapture: View {
    @Bindable var model: HelperModel
    var aimable = false
    var body: some View {
        if let img = model.frame {
            Image(platformImage: img).resizable().aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { g in
                        ZStack {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                    guard aimable, model.aiming else { return }
                                    model.target = CGPoint(x: min(max(v.location.x / g.size.width, 0), 1),
                                                           y: min(max(v.location.y / g.size.height, 0), 1))
                                })
                            if model.aiming, let t = model.target {
                                SupportReticle().position(x: t.x * g.size.width, y: t.y * g.size.height)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(model.aiming ? T.accent : T.line, lineWidth: model.aiming ? 3 : 1))
                .shadow(color: T.ombre.opacity(0.08), radius: 14, y: 6)
                .accessibilityLabel(model.webLive ? model.webBrowserTitle : "Écran de \(model.senior)")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "display").font(.system(size: 28)).foregroundStyle(T.accent)
                Text(model.webLive ? "En attente de la première image de Chrome PapAI…"
                     : "En attente de la première capture d’écran…")
                    .font(rounded(16)).foregroundStyle(T.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.field))
        }
    }
}

struct SupportReticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(T.accent, lineWidth: 2.5).frame(width: 30, height: 30)
            Rectangle().fill(T.accent).frame(width: 2, height: 50)
            Rectangle().fill(T.accent).frame(width: 50, height: 2)
        }
        .shadow(color: .black.opacity(0.4), radius: 1).allowsHitTesting(false)
    }
}

/// Une étape du plan : numéro, titre, détail.
struct StepRow: View {
    let index: Int
    let raw: String
    var body: some View {
        let s = PlanStep(id: index, raw: raw)
        HStack(alignment: .top, spacing: 14) {
            Text("\(index + 1)").font(rounded(17, .semibold)).foregroundStyle(T.leaf)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.mint))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(rounded(18, .semibold)).fixedSize(horizontal: false, vertical: true)
                if let d = s.detail { Text(d).font(rounded(15)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.top, 7)
            Spacer(minLength: 0)
        }
    }
}

/// Le plan validé, avec l'étape que Holo exécute.
struct SupportPlanProgress: View {
    let plan: [String]
    let current: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(current.map { "Étape \(min($0, plan.count)) sur \(plan.count)" } ?? "Plan validé")
                .font(rounded(14, .semibold)).foregroundStyle(T.muted)
            ForEach(Array(plan.enumerated()), id: \.offset) { i, raw in
                let s = PlanStep(id: i, raw: raw)
                let past = current.map { i + 1 < $0 } ?? false
                let now = current == i + 1
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(now ? T.accent : past ? T.mint : T.field)
                        if past {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(T.leaf)
                        } else {
                            Text("\(i + 1)").font(rounded(14, .semibold)).foregroundStyle(now ? Color.white : T.ink)
                        }
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(rounded(16, now ? .semibold : .regular))
                            .foregroundStyle(past ? T.muted : T.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let d = s.detail { Text(d).font(rounded(13)).foregroundStyle(T.muted) }
                    }
                    .padding(.top, 5)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(now ? "En cours : \(raw)" : past ? "Fait : \(raw)" : raw)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

/// Bouton micro : un clic pour parler, un pour arrêter. Les mots s'écrivent dans le champ.
struct SupportMic: View {
    let dictation: Dictation
    var size: CGFloat = 52
    let action: () -> Void
    var body: some View {
        let listening = dictation.phase == .listening
        Button(action: action) {
            ZStack {
                Circle().fill(T.accent.opacity(0.18))
                    .frame(width: size + 22 * dictation.level + 10, height: size + 22 * dictation.level + 10)
                    .opacity(listening ? 1 : 0)
                Circle().fill(listening ? AnyShapeStyle(T.ink) : AnyShapeStyle(T.primary)).frame(width: size, height: size)
                if dictation.phase == .transcribing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: size + 34, height: size + 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(dictation.phase == .transcribing)
        .accessibilityLabel(listening ? "Arrêter la dictée" : "Dicter")
    }

    static func caption(_ d: Dictation) -> String {
        switch d.phase {
        case .idle: d.message ?? "Cliquez sur le micro et parlez"
        case .listening: "Je vous écoute… cliquez pour finir"
        case .transcribing: "J’écris ce que vous avez dit…"
        }
    }
}

/// Champ de texte et micro : la dictée s'écrit dans le champ, modifiable avant l'envoi.
/// `replacing` : le texte de départ est remplacé par la dictée tant qu'il n'a pas été retouché.
struct SupportDictationField: View {
    @Binding var text: String
    let placeholder: String
    let dictation: Dictation
    let httpBase: String
    var replacing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 14) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(3...8)
                .font(rounded(18)).padding(16).champ(actif: dictation.phase == .listening)
                .disabled(dictation.phase != .idle)
            VStack(spacing: 4) {
                SupportMic(dictation: dictation) {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let prefix = (t.isEmpty || t == replacing) ? "" : t + " "
                    dictation.toggle(httpBase: httpBase,
                                     onLive: { text = prefix + $0 },
                                     onText: { text = prefix + $0 })
                }
            }
        }
        Text(SupportMic.caption(dictation)).font(rounded(14, .medium))
            .foregroundStyle(dictation.phase == .listening ? T.leaf : T.muted)
        }
    }
}

struct SupportZoom: View {
    let image: PlatformImage?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if let image { Image(platformImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            Button("Fermer") { dismiss() }.buttonStyle(PillStyle(height: 48)).keyboardShortcut(.cancelAction)
        }
        .padding(22).frame(width: 1000, height: 680).background(T.ink)
    }
}

/// Bouton secondaire compact (blanc bordé), pour les actions à côté du bouton principal.
func supportSecondary(_ height: CGFloat = 56, icone: String? = nil) -> PillStyle {
    PillStyle(filled: false, height: height, icone: icone)
}


/// Onglet Utilisateurs, hors assistance : qui est l'utilisateur et où en est son poste.
struct ProfilUtilisateur: View {
    let model: HelperModel
    var body: some View {
        let p = model.people.first { $0.key == model.helperKey }
        HStack(spacing: 16) {
            Text(String(model.senior.prefix(1)).uppercased()).font(rounded(26, .bold)).foregroundStyle(.white)
                .frame(width: 60, height: 60).background(Circle().fill(T.accent))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.senior.isEmpty ? "Utilisateur" : model.senior).font(rounded(24, .bold))
                if let label = p?.label, !label.isEmpty {
                    Text(label).font(rounded(15)).foregroundStyle(T.muted)
                }
            }
            Spacer(minLength: 0)
            if let online = model.seniorOnline {
                Pastille(texte: online ? "Ordinateur allumé" : "Ordinateur éteint", icone: "desktopcomputer",
                         ton: online ? .vert : .gris, taille: 14)
            }
        }
        .padding(18).carte()
    }
}
