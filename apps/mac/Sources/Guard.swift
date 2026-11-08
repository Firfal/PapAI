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

/// Le gardien, côté Mac : applications ouvertes, titre de la fenêtre au premier
/// plan et site du navigateur sont comparés ici aux règles du serveur ; seul ce
/// qui correspond part. Le serveur décide (`backend/guard.py`) ; aucune capture.
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

    /// Règles reçues du serveur (`guard_rules`) : sans elles, rien ne part.
    static var rules: [String: Any]?

    /// Compare ici et ne rend que ce qui correspond aux règles ; nil si rien ne correspond.
    static func collect(withURL: Bool) async -> [String: Any]? {
        guard let rules else { return nil }
        let tools = (rules["tools"] as? [String]) ?? []
        let titles = (rules["titles"] as? [String]) ?? []
        let apps = NSWorkspace.shared.runningApplications
        var names: [String] = []
        for app in apps {
            for n in [app.localizedName, app.executableURL?.lastPathComponent] {
                if let n, !n.isEmpty, !names.contains(n),
                   tools.contains(where: { n.lowercased().contains($0) }) { names.append(n) }
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
        let alarm = titles.contains { window.lowercased().range(of: $0, options: .regularExpression) != nil }
        let site = GuardLocal.siteToReport(url, rules: rules) ? url : ""
        if names.isEmpty && !alarm && site.isEmpty { return nil }
        return ["type": "guard", "processes": names, "window": alarm ? window : "", "url": site]
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

/// Même comparaison que `apps/windows/papai/guard_local.py` : le site part au serveur
/// seulement s'il ressemble à de l'hameçonnage ; le serveur décide.
enum GuardLocal {
    static func host(_ url: String) -> String {
        URLComponents(string: url)?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
    }

    static func siteToReport(_ url: String, rules: [String: Any]) -> Bool {
        let h = host(url)
        if h.isEmpty { return false }
        if h.contains(":") || h.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            || h.contains("xn--") || !h.allSatisfy({ $0.isASCII }) { return true }
        let official = (rules["official"] as? [String]) ?? []
        if official.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return false }
        let parts = h.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
        for k in (rules["keywords"] as? [String]) ?? [] {
            for p in parts where p.contains(k) || (k.count >= 5 && distance(p, k) <= 2) { return true }
        }
        return false
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > 2 { return 3 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i]
            for j in 1...b.count {
                cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)))
            }
            prev = cur
        }
        return prev[b.count]
    }
}

/// L'alerte du gardien, par-dessus tout le reste : l’utilisateur la lit au
/// moment où son support la reçoit.
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
