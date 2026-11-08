import Foundation

@main
struct SafetyTest {
    static func main() {
        var total = 0
        func verifier(_ value: Bool, _ name: String) {
            precondition(value, name)
            total += 1
            print("  OK      \(name)")
        }
        let ownPID: Int32 = 42
        let ownBundle = "test.papai"
        let finder = Safety.Target(pid: 1, name: "Finder", bundle: "com.apple.finder")
        let safari = Safety.Target(pid: 2, name: "Safari", bundle: "com.apple.Safari")
        func reason(_ target: Safety.Target) -> String? {
            Safety.reason(target, ownPID: ownPID, ownBundle: ownBundle)
        }
        for bundle in Safety.bundles {
            verifier(reason(.init(pid: 3, name: "", bundle: bundle)) != nil, "bundle sensible : \(bundle)")
        }
        for name in Safety.names {
            verifier(reason(.init(pid: 3, name: name, bundle: nil)) != nil, "propriétaire sensible : \(name)")
        }
        verifier(reason(finder) == nil && reason(safari) == nil, "Finder et Safari autorisés")
        verifier(reason(.init(pid: ownPID, name: "", bundle: nil)) != nil, "PID PapAI refusé")
        verifier(reason(.init(pid: 5, name: "", bundle: ownBundle)) != nil, "bundle PapAI refusé")
        let rect = CGRect(x: 0, y: 0, width: 500, height: 500)
        func window(_ target: Safety.Target, _ layer: Int, _ alpha: Double = 1) -> Safety.Window {
            .init(owner: target, layer: layer, bounds: rect, alpha: alpha)
        }
        let auth = Safety.Target(pid: 3, name: "SecurityAgent", bundle: nil)
        let overlays = [window(.init(pid: 6, name: "Dock", bundle: "com.apple.dock"), 20),
                        window(.init(pid: 7, name: "Notification Center", bundle: nil), 21)]
        func pointer(_ windows: [Safety.Window], _ p: CGPoint = CGPoint(x: 50, y: 50)) -> String? {
            Safety.pointerReason(p, windows: windows, ownPID: ownPID, ownBundle: ownBundle)
        }
        verifier(pointer(overlays + [window(finder, 0)]) == nil, "calques 20/21 traversés")
        verifier(pointer(overlays + [window(auth, 100), window(finder, 0)]) != nil, "autorisation au-dessus de Finder refusée")
        verifier(pointer([window(finder, 0), window(auth, 100)]) == nil, "arrêt au premier calque zéro")
        verifier(pointer([window(auth, 100, 0), window(finder, 0)]) == nil, "fenêtre transparente ignorée")
        verifier(pointer([window(auth, 100)], CGPoint(x: 600, y: 600)) == nil, "point hors fenêtre autorisé")
        verifier(pointer([]) == nil, "liste vide autorisée")
        verifier(pointer([window(.init(pid: ownPID, name: "", bundle: nil), 0)]) != nil, "fenêtre PapAI refusée")
        func keyboard(_ secure: Bool, _ front: Safety.Target?, _ active: Bool = false) -> String? {
            Safety.keyboardReason(secureInput: secure, front: front, papaiActive: active,
                                  ownPID: ownPID, ownBundle: ownBundle)
        }
        verifier(keyboard(false, finder) == nil && keyboard(false, safari) == nil, "clavier Finder/Safari autorisé")
        verifier(keyboard(true, finder) != nil, "saisie sécurisée refusée")
        verifier(keyboard(false, auth) != nil, "clavier sensible refusé")
        verifier(keyboard(false, finder, true) != nil, "PapAI active refusée")
        verifier(keyboard(false, nil) != nil, "premier plan inconnu refusé")
        for (bundle, name) in [("com.apple.Terminal", "Terminal"), ("com.googlecode.iterm2", "iTerm2"),
                               ("com.apple.ScriptEditor2", "Éditeur de script"), ("com.apple.Automator", "Automator"),
                               ("com.apple.shortcuts", "Raccourcis")] {
            let target = Safety.Target(pid: 8, name: "", bundle: bundle)
            verifier(pointer([window(target, 0)]) != nil, "outil de script refusé au pointeur : \(bundle)")
            verifier(keyboard(false, target) != nil, "outil de script refusé au clavier : \(bundle)")
            verifier(reason(.init(pid: 8, name: name, bundle: nil)) != nil, "nom français refusé : \(name)")
        }
        for name in ["iTerm", "Script Editor", "Shortcuts"] {
            verifier(reason(.init(pid: 8, name: name, bundle: nil)) != nil, "nom anglais refusé : \(name)")
        }
        func focusedKeyboard(_ focused: Safety.Target?, _ front: Safety.Target? = finder) -> String? {
            Safety.keyboardReason(secureInput: false, front: front, papaiActive: false,
                                  ownPID: ownPID, ownBundle: ownBundle, focused: focused)
        }
        for bundle in Safety.bundles {
            verifier(focusedKeyboard(.init(pid: 9, name: "", bundle: bundle)) != nil,
                     "focus AX sensible avec Finder devant : \(bundle)")
        }
        verifier(focusedKeyboard(auth) != nil, "focus AX refusé par nom du processus")
        verifier(focusedKeyboard(.init(pid: ownPID, name: "", bundle: nil)) != nil, "focus AX PapAI refusé par PID")
        verifier(focusedKeyboard(safari) == nil, "focus AX autorisé dans une app normale")
        verifier(focusedKeyboard(nil) == nil, "aucun élément actif : Finder reste autorisé")
        verifier(Safety.keyboardReason(secureInput: false, front: finder, papaiActive: false, ownPID: ownPID,
                                       ownBundle: ownBundle, focused: nil, focusUnreadable: true) != nil,
                 "lecture AX en échec : frappe refusée")
        for name in ["Programme d’installation", "Moniteur d’activité", "Utilitaire de disque",
                     "AnyDesk", "TeamViewer", "RustDesk", "Splashtop Business"] {
            verifier(reason(.init(pid: 8, name: name, bundle: nil)) != nil, "outil système ou de prise en main refusé : \(name)")
        }
        verifier(focusedKeyboard(nil, auth) != nil, "focus AX illisible : premier plan sensible reste refusé")
        verifier(focusedKeyboard(finder, auth) != nil, "focus AX normal ne contourne pas le premier plan sensible")
        verifier(focusedKeyboard(nil, nil) != nil, "focus AX illisible et premier plan inconnu restent refusés")
        let gate = StopGate()
        let pinned = gate.pin()
        verifier(!pinned.isStopped, "verrou initial ouvert")
        gate.raise()
        verifier(pinned.isStopped, "arrêt transmis au verrou épinglé")
        gate.reset()
        verifier(!gate.isStopped && pinned.isStopped, "reset ne reprend pas une action en cours")
        let next = gate.pin()
        gate.raise()
        verifier(next.isStopped && pinned.isStopped, "nouvelle génération arrêtée")
        print("\(total) contrôles sécurité passés, 0 échec(s)")
    }
}
