import AppKit
import SwiftUI
import CoreGraphics
import Foundation

struct GuardAlert: Equatable {
    var level: String
    var title: String
    var detail: String
    var id: String? = nil
    var blocked: Bool = false
    var acknowledged: Bool = false
    var isDanger: Bool { level == "danger" }
}

/// Le gardien anti-arnaque, côté Mac : trois signaux textuels (applications
/// ouvertes, titre de la fenêtre au premier plan, adresse du navigateur), et
/// rien d'autre. Le serveur évalue (`backend/guard.py`) ; aucune capture ne
/// part d'ici.
@MainActor
enum GuardSignals {
    static let period: UInt64 = 8_000_000_000

    /// Protection en temps réel : activée par défaut, comme un antivirus.
    /// Coupée, aucun signal ne part de l'ordinateur.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "realtimeProtection") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "realtimeProtection") }
    }

    nonisolated private static let browsers: [String: String] = [
        "com.apple.Safari": #"tell application id "com.apple.Safari" to return URL of front document"#,
        "com.google.Chrome": #"tell application id "com.google.Chrome" to return URL of active tab of front window"#,
        "com.microsoft.edgemac": #"tell application id "com.microsoft.edgemac" to return URL of active tab of front window"#,
        "com.brave.Browser": #"tell application id "com.brave.Browser" to return URL of active tab of front window"#,
        "company.thebrowser.Browser": #"tell application id "company.thebrowser.Browser" to return URL of active tab of front window"#,
    ]

    /// `withURL` à faux pendant une session : la première lecture de l'adresse
    /// fait apparaître une demande d'autorisation macOS, qu'on ne veut pas voir
    /// surgir pendant que Holo agit.
    /// Titre de fenêtre et AppleScript hors du fil principal : la demande
    /// d'autorisation d'automatisation de macOS ne gèle plus la fenêtre.
    nonisolated private static let queue = DispatchQueue(label: "papai.guard.signals", qos: .utility)

    static func collect(withURL: Bool) async -> [String: Any] {
        let apps = NSWorkspace.shared.runningApplications
        var names: [String] = []
        for app in apps {
            for n in [app.localizedName, app.executableURL?.lastPathComponent] {
                if let n, !n.isEmpty, !names.contains(n) { names.append(n) }
            }
        }
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.processIdentifier
        let source = withURL ? front?.bundleIdentifier.flatMap { browsers[$0] } : nil
        let (window, url) = await withCheckedContinuation { (c: CheckedContinuation<(String, String), Never>) in
            queue.async {
                let window = pid.map { frontWindowTitle(pid: $0) } ?? ""
                let url = source.map { siteOnly(browserURL($0)) } ?? ""
                c.resume(returning: (window, url))
            }
        }
        return ["type": "guard", "processes": names, "window": window, "url": url]
    }

    /// Le titre exige l'autorisation d'enregistrement de l'écran, déjà donnée à PapAI.
    nonisolated private static func frontWindowTitle(pid: pid_t) -> String {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return "" }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
            if let name = w[kCGWindowName as String] as? String, !name.isEmpty { return name }
        }
        return ""
    }

    /// Le gardien ne juge que le site : chemin et paramètres, qui peuvent
    /// porter des jetons, restent sur le Mac.
    nonisolated private static func siteOnly(_ address: String) -> String {
        guard let c = URLComponents(string: address), let host = c.host, !host.isEmpty else { return "" }
        return "\(c.scheme ?? "https")://\(host)"
    }

    nonisolated private static func browserURL(_ command: String) -> String {
        // Sans délai court, un navigateur figé bloquerait la fenêtre PapAI.
        let source = "with timeout of 2 seconds\n\(command)\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? (result?.stringValue ?? "") : ""
    }
}

/// L'alerte du gardien, par-dessus tout le reste : l’utilisateur la lit au
/// moment où son proche la reçoit.
struct GuardAlertView: View {
    @Environment(AppModel.self) private var model
    let alert: GuardAlert

    var body: some View {
        ZStack {
            T.ink.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: alert.isDanger ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 26))
                    Text(alert.isDanger ? "Attention, danger" : "Attention").font(rounded(20, .semibold))
                }
                .foregroundStyle(alert.isDanger ? T.danger : T.accent)
                Text(alert.title).font(rounded(32, .semibold)).tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    Text(alert.detail).font(rounded(20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 260)
                if alert.acknowledged {
                    Text("Votre support a vu l'alerte et s'en occupe")
                        .font(rounded(22, .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                Text(alert.blocked ? "Votre support a été prévenu. Attendez de lui avoir parlé." : "Ne faites rien d'autre et appelez \(model.helperName).")
                    .font(rounded(18)).foregroundStyle(T.muted)
                if model.sessionOpen && !alert.blocked {
                    Button { model.stop() } label: {
                        Text("Arrêter l'assistance").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillStyle(height: 72))
                }
                if !alert.blocked {
                    Button { model.guardAlert = nil } label: { Text("J'ai compris").frame(maxWidth: .infinity) }
                        .buttonStyle(PillStyle(height: 72))
                }
            }
            .foregroundStyle(T.ink)
            .padding(40)
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.card)
                    .overlay(alignment: .top) {
                        Rectangle().fill(alert.isDanger ? T.danger : T.accent).frame(height: 10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: T.rBig, style: .continuous))
            )
            .padding(40)
        }
    }
}
