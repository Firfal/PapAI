import AppKit
import Foundation

/// « Chrome PapAI » et `holo local browser` : le navigateur que l'agent web de H
/// pilote quand la demande se fait dans un navigateur (PROTOCOL.md, agent navigateur).
/// Profil dédié, jamais le profil habituel. La clé H reste dans
/// ~/.config/hai/.env : la sortie de holo ne va dans aucun journal.
@MainActor
final class WebAgentHost {
    static let debugPort = 9222
    static let browsers = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac"]

    /// Annoncé au serveur seulement quand Chrome PapAI et holo tournent.
    private(set) var sessionID: String?
    var onChange: ((String?) -> Void)?
    var onOffSite: ((String) -> Void)?
    private var sites: [String] = []
    private var hosts: [String] = []
    private var siteMonitor: Task<Void, Never>?
    private var lastOffSite = Date.distantPast

    func updateSites(_ sites: [String], hosts: [String]) {
        self.sites = sites
        self.hosts = hosts
        if sites.isEmpty {
            siteMonitor?.cancel()
            siteMonitor = nil
        } else if sessionID != nil {
            monitorSites()
        }
    }

    private func monitorSites() {
        guard siteMonitor == nil, !sites.isEmpty else { return }
        let monitorGeneration = generation
        siteMonitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == monitorGeneration else { return }
                var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.debugPort)/json/list")!)
                request.timeoutInterval = 0.4
                request.cachePolicy = .reloadIgnoringLocalCacheData
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   !Task.isCancelled, self.generation == monitorGeneration,
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let pages = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
                   !self.sites.isEmpty {
                    for page in pages where page["type"] as? String == "page" {
                        if let url = page["url"] as? String,
                           SiteCheck.classify(url, sites: self.sites, hosts: self.hosts) == "hors",
                           Date().timeIntervalSince(self.lastOffSite) >= 2 {
                            self.lastOffSite = Date()
                            self.onOffSite?(url)
                            break
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var holo: Process?
    private var chromePID: pid_t?
    private var chromeProcess: Process?
    private var starting = false
    private var generation = 0

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PapAI", isDirectory: true)
    }
    static var profile: URL { support.appendingPathComponent("Chrome", isDirectory: true) }
    static var holoBinary: URL { support.appendingPathComponent("agent-navigateur/venv/bin/holo") }
    /// La personne se connecte elle-même à ses sites : rien n'est retenu d'une assistance à l'autre.
    static func wipeProfile() {
        try? FileManager.default.removeItem(at: profile)
    }

    /// Attend (jusqu'à 5 s) que plus aucun Chrome n'utilise notre profil.
    static func waitChromeGone() async -> Bool {
        for _ in 0..<20 {
            if ourChromePID() == nil { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return ourChromePID() == nil
    }

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: holoBinary.path) }

    static func browserExecutable() -> URL? {
        for id in browsers {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
               let exe = Bundle(url: app)?.executableURL {
                return exe
            }
        }
        return nil
    }

    /// Au début d'une demande. Sans installation ni navigateur : rien, le mode bureau reste.
    func start() {
        guard Self.isInstalled, !starting, holo == nil, let exe = Self.browserExecutable() else { return }
        starting = true
        Task {
            await launch(exe)
            starting = false
        }
    }

    private func launch(_ exe: URL) async {
        let launchGeneration = generation
        var startedChrome: Process?
        var startedHolo: Process?
        if await Self.debuggerListening() {
            if abortIfStopped(launchGeneration, chrome: startedChrome, holo: startedHolo) { return }
            // Un navigateur écoute déjà sur 9222 : seulement s'il utilise notre profil,
            // et on le referme pour repartir d'un profil neuf, sans les cookies d'avant.
            guard let pid = Self.ourChromePID() else { return }
            kill(pid, SIGKILL)
            guard await Self.waitChromeGone() else { return }
            if abortIfStopped(launchGeneration, chrome: startedChrome, holo: startedHolo) { return }
        }
        do {
            // Profil neuf à chaque assistance : aucun compte, identifiant ni cookie n'est gardé.
            Self.wipeProfile()
            try? FileManager.default.createDirectory(at: Self.profile, withIntermediateDirectories: true)
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--remote-debugging-port=\(Self.debugPort)", "--user-data-dir=\(Self.profile.path)",
                           "--no-first-run", "--no-default-browser-check", "about:blank"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return }
            startedChrome = p
            chromePID = p.processIdentifier
            chromeProcess = p
            var ready = false
            for _ in 0..<60 {
                let listening = await Self.debuggerListening()
                if abortIfStopped(launchGeneration, chrome: startedChrome, holo: startedHolo) { return }
                if listening { ready = true; break }
                try? await Task.sleep(nanoseconds: 250_000_000)
                if abortIfStopped(launchGeneration, chrome: startedChrome, holo: startedHolo) { return }
            }
            guard ready else { p.terminate(); chromePID = nil; chromeProcess = nil; return }
        }
        let id = UUID().uuidString.lowercased()
        let h = Process()
        h.executableURL = Self.holoBinary
        h.arguments = ["local", "browser", "--session-id", id, "--debug-port", "\(Self.debugPort)"]
        h.standardOutput = FileHandle.nullDevice
        h.standardError = FileHandle.nullDevice
        h.terminationHandler = { [weak self] ended in
            Task { @MainActor in self?.holoEnded(ended) }
        }
        do { try h.run() } catch { return }
        startedHolo = h
        holo = h
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if abortIfStopped(launchGeneration, chrome: startedChrome, holo: startedHolo) { return }
        guard h.isRunning, holo === h else { return }
        sessionID = id
        monitorSites()
        if abortIfStopped(launchGeneration, chrome: startedChrome, holo: startedHolo) { return }
        onChange?(id)
    }

    private func abortIfStopped(_ launchGeneration: Int, chrome: Process?, holo: Process?) -> Bool {
        guard generation != launchGeneration else { return false }
        if let holo, holo.isRunning { holo.terminate() }
        if let holo, self.holo === holo { self.holo = nil }
        if let chrome, chrome.isRunning { chrome.terminate() }
        if let chrome, chromePID == chrome.processIdentifier {
            chromePID = nil
            chromeProcess = nil
        }
        return true
    }

    private func holoEnded(_ h: Process) {
        guard holo === h else { return }
        holo = nil
        siteMonitor?.cancel()
        siteMonitor = nil
        if sessionID != nil {
            sessionID = nil
            onChange?(nil)
        }
    }

    /// Arrêter, fin de session ou alerte : marche hors ligne, sans le serveur.
    func stopLocal(notifyServer: Bool = true) {
        generation += 1
        siteMonitor?.cancel()
        siteMonitor = nil
        sites = []
        hosts = []
        lastOffSite = .distantPast
        guard holo != nil || sessionID != nil || chromePID != nil || starting else { return }
        let h = holo
        holo = nil
        if sessionID != nil {
            sessionID = nil
            if notifyServer { onChange?(nil) }
        }
        h?.terminate()
        let chrome = chromePID
        let ownedChrome = chromeProcess
        chromePID = nil
        chromeProcess = nil
        if let chrome {
            NSRunningApplication(processIdentifier: chrome)?.terminate()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if let ownedChrome {
                    if ownedChrome.isRunning { kill(chrome, SIGKILL) }
                } else if Self.ourChromePID() == chrome {
                    kill(chrome, SIGKILL)
                }
                if await Self.waitChromeGone() { Self.wipeProfile() }
            }
        }
        if Self.isInstalled {
            let s = Process()
            s.executableURL = Self.holoBinary
            s.arguments = ["local", "stop"]
            s.standardOutput = FileHandle.nullDevice
            s.standardError = FileHandle.nullDevice
            try? s.run()
        }
        if let h {
            let pid = h.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if h.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    func bringToFront() {
        guard let pid = chromePID, let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }

    private static func debuggerListening() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(debugPort)/json/version") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// Le Chrome déjà lancé avec notre profil (après un redémarrage de PapAI), sinon nil.
    private static func ourChromePID() -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-o", "-f", "--", "--user-data-dir=\(profile.path)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
