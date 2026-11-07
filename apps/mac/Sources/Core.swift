import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Verrou d'arrêt

/// Le verrou d'arrêt. Levé depuis l'interface AVANT d'envoyer `stop` au serveur,
/// lu avant chaque action : il ne dépend d'aucun réseau.
final class StopGate: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func raise() { lock.lock(); stopped = true; lock.unlock() }
    func reset() { lock.lock(); stopped = false; lock.unlock() }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

// MARK: - Automatismes

struct Lesson: Decodable, Identifiable {
    struct Step: Decodable {
        var instruction: String?
        var image: String?
        var checkpoint: String?
    }
    struct Shortcut: Decodable {
        var folder: String?
        var subfolder: String?
    }
    /// Action de premier niveau d'un automatisme importé par un support.
    /// Jamais de commande ni de script : l'app ne connaît que ces actions-là.
    struct Action: Decodable {
        var kind: String
        var folder: String?
        var subfolder: String?
        var page: String?
        var url: String?
        var goal: String?
        var files: [String]?
        enum CodingKeys: String, CodingKey { case kind = "do", folder, subfolder, page, url, goal, files }
    }
    var id: String
    var title: String
    var steps: [Step]?
    var shortcut: Shortcut?
    var actions: [Action]?
    var publisher: String?
    var platforms: [String]?
}

enum Shortcuts {
    static func directory(for name: String) -> FileManager.SearchPathDirectory? {
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case "pictures": .picturesDirectory
        case "documents": .documentDirectory
        case "downloads": .downloadsDirectory
        case "desktop": .desktopDirectory
        case "videos": .moviesDirectory
        case "music": .musicDirectory
        default: nil
        }
    }

    static func symbol(for folder: String?) -> String {
        switch (folder ?? "").lowercased() {
        case "pictures": "photo"
        case "documents": "doc.text"
        case "downloads": "arrow.down.circle"
        case "desktop": "menubar.dock.rectangle"
        case "videos": "film"
        case "music": "music.note"
        default: "list.number"
        }
    }

    /// Ouvre le dossier enregistré. Le modèle ne fournit jamais de chemin :
    /// un dossier connu du système, et au plus un nom de sous-dossier.
    @MainActor
    static func open(_ shortcut: Lesson.Shortcut) -> (ok: Bool, detail: String) {
        guard let dir = directory(for: shortcut.folder ?? ""),
              let base = FileManager.default.urls(for: dir, in: .userDomainMask).first
        else { return (false, "Aucun raccourci enregistré.") }
        var target = base
        let sub = (shortcut.subfolder ?? "").trimmingCharacters(in: .whitespaces)
        if !sub.isEmpty {
            if sub.contains("/") || sub.contains("\\") || sub.contains(":") || sub == "." || sub == ".." || sub.contains("..") {
                return (false, "Nom de dossier invalide.")
            }
            target = base.appendingPathComponent(sub, isDirectory: true)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            let quoi = sub.isEmpty ? "Ce dossier" : "« \(sub) »"
            return (false, "\(quoi) n'existe pas (ou plus) sur cet ordinateur.")
        }
        return (NSWorkspace.shared.open(target), target.path)
    }
}

// MARK: - Description des actions

func describeAction(_ name: String, _ args: [String: Any]) -> String {
    // Une phrase simple, à la première personne : la personne aidée lit ce
    // que fait Holo pendant qu'il le fait.
    let cible = (args["element"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    switch name {
    case "click":
        return cible.isEmpty ? "Je clique sur l'écran" : "Je clique sur \(cible)"
    case "double_click":
        return cible.isEmpty ? "J'ouvre l'élément" : "J'ouvre \(cible)"
    case "type_text":
        let t = (args["text"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.isEmpty ? "J'écris au clavier" : "J'écris « \(t) »"
    case "press_key":
        let k = (args["keys"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        switch k {
        case "enter", "return": return "Je valide avec la touche Entrée"
        case "esc", "escape": return "Je ferme avec la touche Échap"
        case "cmd+space": return "J'ouvre la recherche du Mac"
        case "": return "J'appuie sur une touche"
        default: return "J'appuie sur \(k)"
        }
    case "scroll": return "Je fais défiler la page"
    case "wait": return "J'attends que l'ordinateur réponde…"
    default: return "Je regarde l'écran…"
    }
}

// MARK: - Permissions

enum Permissions {
    static var screenOK: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibilityOK: Bool { AXIsProcessTrusted() }

    static func requestScreen() {
        _ = CGRequestScreenCaptureAccess()
        open("Privacy_ScreenCapture")
    }
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        open("Privacy_Accessibility")
    }
    private static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Capture d'écran

enum ScreenGrabber {
    struct Frame { var pngB64: String; var width: Int; var height: Int }
    struct CaptureError: Error { var message: String }

    /// Écran principal, sans aucune fenêtre de PapAI, réduit à 1280 px de large.
    static func capture() async throws -> Frame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { throw CaptureError(message: "Aucun écran") }
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let w = min(1280, display.width)
        config.width = w
        config.height = max(1, Int((Double(display.height) * Double(w) / Double(display.width)).rounded()))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError(message: "Encodage PNG impossible")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError(message: "Encodage PNG impossible") }
        return Frame(pngB64: (data as Data).base64EncodedString(), width: image.width, height: image.height)
    }
}

// MARK: - Actions (CGEvent)

enum ActionError: Error {
    case stopped
    case protectedZone
    case noAccessibility
    case unknownKey(String)
}

enum Actuator {
    /// Marque posée sur chaque événement envoyé par Holo, pour que le verrou des
    /// entrées (`InputLock`) le laisse passer et bloque seulement la vraie souris.
    static let marker: Int64 = 0x5041_5041_49
    /// Exécute une action. `protected` : cadre de la fenêtre PapAI, en points
    /// écran (origine en haut à gauche), que l'agent n'a pas le droit de viser.
    static func run(name: String, args: [String: Any], gate: StopGate, protected: CGRect?) async throws -> String {
        if gate.isStopped { throw ActionError.stopped }
        let source = CGEventSource(stateID: .hidSystemState)

        switch name {
        case "click", "double_click":
            let p = try point(args, protected: protected)
            guard AXIsProcessTrusted() else { throw ActionError.noAccessibility }
            post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
            try await Task.sleep(nanoseconds: 200_000_000)
            if gate.isStopped { throw ActionError.stopped }
            let count = name == "double_click" ? 2 : 1
            for i in 1...count {
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
                    e?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                    post(e)
                }
            }
            return "\(name) à (\(Int(p.x)), \(Int(p.y))) sur « \(args["element"] as? String ?? "") »"

        case "type_text":
            guard AXIsProcessTrusted() else { throw ActionError.noAccessibility }
            let text = args["text"] as? String ?? ""
            for ch in text {
                if gate.isStopped { throw ActionError.stopped }
                if ch == "\n" {
                    key(36, [], source)
                } else {
                    let utf16 = Array(String(ch).utf16)
                    for down in [true, false] {
                        let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                        e?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                        e?.flags = []
                        post(e)
                    }
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            return "texte tapé : \(text)"

        case "press_key":
            guard AXIsProcessTrusted() else { throw ActionError.noAccessibility }
            let spec = args["keys"] as? String ?? ""
            let (code, flags) = try parseKeys(spec)
            key(code, flags, source)
            return "touche : \(spec)"

        case "scroll":
            let p = try point(args, protected: protected)
            guard AXIsProcessTrusted() else { throw ActionError.noAccessibility }
            post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
            let dir = (args["direction"] as? String ?? "down").lowercased()
            let amount: Int32 = 400
            let (dy, dx): (Int32, Int32) = switch dir {
            case "up": (amount, 0)
            case "left": (0, amount)
            case "right": (0, -amount)
            default: (-amount, 0)
            }
            post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
            return "scroll \(dir)"

        case "wait":
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return "attente 2 s"

        default:
            return "outil inconnu : \(name)"
        }
    }

    private static func post(_ e: CGEvent?) {
        e?.setIntegerValueField(.eventSourceUserData, value: marker)
        e?.post(tap: .cghidEventTap)
    }

    private static func key(_ code: CGKeyCode, _ flags: CGEventFlags, _ source: CGEventSource?) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            e?.flags = flags
            post(e)
        }
    }

    /// [0,1000] -> points de l'écran principal, avec refus sur la fenêtre PapAI.
    private static func point(_ args: [String: Any], protected: CGRect?) throws -> CGPoint {
        func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
        let b = CGDisplayBounds(CGMainDisplayID())
        let p = CGPoint(x: b.minX + (num(args["x"]) / 1000 * b.width).rounded(),
                        y: b.minY + (num(args["y"]) / 1000 * b.height).rounded())
        if let r = protected, r.contains(p) { throw ActionError.protectedZone }
        return p
    }

    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "enter": 36, "return": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "esc": 53, "escape": 53, "forwarddelete": 117, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "arrowleft": 123, "arrowright": 124, "arrowdown": 125, "arrowup": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    static func parseKeys(_ spec: String) throws -> (CGKeyCode, CGEventFlags) {
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        let parts = spec.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        for (i, part) in parts.enumerated() {
            switch part {
            case "cmd", "command", "super", "win", "windows", "meta": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default:
                // « cmd++ » : le dernier élément vide est le signe plus lui-même.
                let name = (part.isEmpty && i == parts.count - 1) ? "=" : part
                guard let c = codes[name] else { throw ActionError.unknownKey(spec) }
                code = c
            }
        }
        guard let code else { throw ActionError.unknownKey(spec) }
        return (code, flags)
    }
}


/// Automatismes importés par un support (service IT, proche). Le serveur a
/// vérifié chaque action à l'import ; on revérifie ici avant de la jouer.
enum Automations {
    static let templateExt = [".dotx", ".potx", ".xltx"]

    static func settingsURL(_ page: String) -> URL? {
        let id: String? = switch page.lowercased() {
        case "printers": "com.apple.Print-Scan-Settings.extension"
        case "default_apps": "com.apple.Desktop-Settings.extension"
        case "updates": "com.apple.Software-Update-Settings.extension"
        case "wifi": "com.apple.wifi-settings-extension"
        case "bluetooth": "com.apple.BluetoothSettings"
        case "sound": "com.apple.Sound-Settings.extension"
        case "display": "com.apple.Displays-Settings.extension"
        default: nil
        }
        return id.flatMap { URL(string: "x-apple.systempreferences:\($0)") }
    }

    /// Le dossier des modèles personnels de Word pour Mac.
    static var wordTemplates: URL? {
        let office = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office", isDirectory: true)
        guard FileManager.default.fileExists(atPath: office.path) else { return nil }
        return office.appendingPathComponent("User Content.localized/Templates.localized", isDirectory: true)
    }

    static func nameOK(_ n: String) -> Bool {
        !n.isEmpty && !n.hasPrefix(".") && !n.contains("..") &&
            n.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:*?\"<>|")) == nil &&
            templateExt.contains { n.lowercased().hasSuffix($0) }
    }

    static func installTemplates(lessonID: String, files: [String], base: String) async -> (ok: Bool, detail: String) {
        guard let dest = wordTemplates else { return (false, "Microsoft Word n'est pas installé sur ce Mac.") }
        var got: [(String, Data)] = []
        for n in files where nameOK(n) {
            guard let enc = n.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(base)/lessons/\(lessonID)/\(enc)"),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  data.starts(with: [0x50, 0x4B])
            else { return (false, "Modèle introuvable : \(n)") }
            got.append((n, data))
        }
        guard !got.isEmpty else { return (false, "Aucun modèle valable.") }
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            for (n, d) in got {
                let target = dest.appendingPathComponent(n)
                if let old = try? Data(contentsOf: target), old != d {
                    // Jamais rien de perdu : une copie de l'ancien modèle est gardée à côté.
                    let ext = target.pathExtension, stem = target.deletingPathExtension().lastPathComponent
                    var n = 1
                    var backup = dest.appendingPathComponent("\(stem) (avant PapAI).\(ext)")
                    while FileManager.default.fileExists(atPath: backup.path) {
                        n += 1
                        backup = dest.appendingPathComponent("\(stem) (avant PapAI \(n)).\(ext)")
                    }
                    try FileManager.default.copyItem(at: target, to: backup)
                }
                try d.write(to: target, options: .atomic)
            }
        } catch { return (false, error.localizedDescription) }
        return (true, got.count > 1 ? "\(got.count) modèles ajoutés dans Word." : "Modèle ajouté dans Word.")
    }

    /// Joue les actions locales, dans l'ordre. L'action `holo` est confiée ensuite au serveur.
    @MainActor
    static func play(_ l: Lesson, base: String, gate: StopGate) async -> (ok: Bool, detail: String) {
        var detail = ""
        for a in l.actions ?? [] {
            if gate.isStopped { return (false, "Arrêté.") }
            switch a.kind {
            case "open_folder":
                let r = Shortcuts.open(Lesson.Shortcut(folder: a.folder, subfolder: a.subfolder))
                if !r.ok { return r }
            case "open_settings":
                guard let u = settingsURL(a.page ?? ""), NSWorkspace.shared.open(u)
                else { return (false, "Cette page de Réglages n'existe pas sur ce Mac.") }
            case "open_url":
                guard let u = URL(string: a.url ?? ""), u.scheme == "https", u.host != nil,
                      u.user == nil, u.password == nil, NSWorkspace.shared.open(u)
                else { return (false, "Lien refusé : seulement https://.") }
            case "install_templates":
                let r = await installTemplates(lessonID: l.id, files: a.files ?? [], base: base)
                if !r.ok { return r }
                detail = r.detail
            case "holo":
                continue
            default:
                return (false, "Cette action n'existe pas sur Mac : \(a.kind)")
            }
        }
        return (true, detail)
    }
}
