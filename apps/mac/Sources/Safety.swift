import Foundation
import CoreGraphics

final class StopGate: @unchecked Sendable {
    private final class Signal {
        let lock = NSLock()
        var stopped = false
    }
    private let lock = NSLock()
    private var signal = Signal()
    func raise() {
        lock.lock(); defer { lock.unlock() }
        signal.lock.lock(); defer { signal.lock.unlock() }
        signal.stopped = true
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        signal.lock.lock()
        let stopped = signal.stopped
        signal.lock.unlock()
        if stopped { signal = Signal() }
    }
    func pin() -> StopGate {
        lock.lock(); defer { lock.unlock() }
        let gate = StopGate()
        gate.signal = signal
        return gate
    }
    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        signal.lock.lock(); defer { signal.lock.unlock() }
        return signal.stopped
    }
}

enum Safety {
    struct Target {
        var pid: Int32
        var name: String
        var bundle: String?
    }
    struct Window {
        var owner: Target
        var layer: Int
        var bounds: CGRect
        var alpha: Double
    }
    static let bundles: Set<String> = [
        "com.apple.systempreferences", "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent",
        "com.apple.UserNotificationCenter", "com.apple.coreservices.uiagent", "com.apple.loginwindow",
        "com.apple.accessibility.universalAccessAuthWarn", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.agilebits.onepassword7", "com.agilebits.onepassword-osx", "com.1password.1password",
        "com.bitwarden.desktop", "com.dashlane.Dashlane", "com.lastpass.LastPass",
        "org.keepassxc.keepassxc", "in.sinew.Enpass-Desktop", "com.sinew.Enpass-Desktop",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.ScriptEditor2",
        "com.apple.Automator", "com.apple.shortcuts"
    ]
    static let names: Set<String> = [
        "System Settings", "Réglages Système", "System Preferences", "Préférences Système",
        "SecurityAgent", "coreautha", "UserNotificationCenter", "CoreServicesUIAgent", "loginwindow",
        "universalAccessAuthWarn", "Keychain Access", "Trousseaux d’accès", "Trousseaux d'accès",
        "Passwords", "Mots de passe", "1Password", "1Password 7", "Bitwarden", "Dashlane",
        "LastPass", "KeePassXC", "Enpass", "PapAI", "Terminal", "iTerm", "iTerm2",
        "Script Editor", "Éditeur de script", "Éditeur de scripts", "Automator", "Shortcuts", "Raccourcis"
    ]
    static func reason(_ target: Target, ownPID: Int32, ownBundle: String?) -> String? {
        if target.pid == ownPID || (ownBundle != nil && target.bundle == ownBundle) {
            return "PapAI ne peut pas se manipuler elle-même"
        }
        if names.contains(where: { $0.lowercased() == target.name.lowercased() }) ||
            bundles.contains(where: { $0.lowercased() == target.bundle?.lowercased() }) {
            return "cette application contient des réglages ou des informations sensibles"
        }
        return nil
    }
    static func pointerReason(_ point: CGPoint, windows: [Window], ownPID: Int32, ownBundle: String?) -> String? {
        for window in windows where window.alpha > 0 && window.bounds.contains(point) {
            if let reason = reason(window.owner, ownPID: ownPID, ownBundle: ownBundle) { return reason }
            if window.layer == 0 { break }
        }
        return nil
    }
    static func keyboardReason(secureInput: Bool, front: Target?, papaiActive: Bool,
                               ownPID: Int32, ownBundle: String?) -> String? {
        if secureInput { return "un champ protégé attend une saisie confidentielle" }
        if papaiActive { return "PapAI est encore au premier plan" }
        guard let front else { return "l’application au premier plan est inconnue" }
        return reason(front, ownPID: ownPID, ownBundle: ownBundle)
    }
}

#if !SAFETY_CLI
import AppKit
import Carbon

@MainActor
final class DesktopSafety {
    static let shared = DesktopSafety()
    private var previous: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundle = Bundle.main.bundleIdentifier

    private init() {
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }
    }
    private func remember(_ app: NSRunningApplication?) {
        if let app, app.processIdentifier != ownPID { previous = app }
    }
    private func target(_ app: NSRunningApplication) -> Safety.Target {
        Safety.Target(pid: app.processIdentifier, name: app.localizedName ?? "", bundle: app.bundleIdentifier)
    }
    func checkPointer(_ point: CGPoint) throws {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            throw ActionError.sensitive("les fenêtres ne peuvent pas être vérifiées")
        }
        let windows = list.compactMap { w -> Safety.Window? in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return Safety.Window(owner: .init(pid: pid, name: w[kCGWindowOwnerName as String] as? String ?? "",
                                             bundle: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier),
                                 layer: w[kCGWindowLayer as String] as? Int ?? 0,
                                 bounds: rect, alpha: w[kCGWindowAlpha as String] as? Double ?? 1)
        }
        if let reason = Safety.pointerReason(point, windows: windows, ownPID: ownPID, ownBundle: ownBundle) {
            throw ActionError.sensitive(reason)
        }
    }
    func prepareKeyboard() async throws {
        if NSApp.isActive {
            let app = previous.flatMap { $0.isTerminated ? nil : $0 }
                ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
            if let app {
                NSApp.yieldActivation(to: app)
                app.activate(options: [])
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try checkKeyboard()
    }
    func checkKeyboard() throws {
        if let reason = Safety.keyboardReason(secureInput: IsSecureEventInputEnabled(),
                                              front: NSWorkspace.shared.frontmostApplication.map(target),
                                              papaiActive: NSApp.isActive, ownPID: ownPID, ownBundle: ownBundle) {
            throw ActionError.sensitive(reason)
        }
    }
}
#endif
