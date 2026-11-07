import AppKit
import CoreGraphics

/// Pendant que Holo agit, la souris et le clavier sont à lui (et à l'aidant) :
/// si la personne aidée clique ou tape ailleurs, Holo perd le fil et tourne en rond.
///
/// Un « event tap » de session filtre les entrées :
/// - les événements envoyés par Holo (marqués `Actuator.marker`) passent ;
/// - dans la fenêtre PapAI, tout passe : Pause, Reprendre, Arrêter restent à portée ;
/// - le clavier passe quand PapAI est au premier plan (répondre à une question) ;
/// - Échap arrête tout, où que soit la souris ;
/// - le reste (clics, défilement, frappe ailleurs) est bloqué. Le pointeur, lui,
///   bouge toujours : la personne peut aller jusqu'au bouton Arrêter.
/// Nécessite l'autorisation Accessibilité, déjà demandée pour les clics de Holo.
final class InputLock {
    static let shared = InputLock()

    /// Cadre de la fenêtre PapAI, en points écran, origine en haut à gauche.
    var allowedRect: () -> CGRect? = { nil }
    var onEscape: () -> Void = {}
    private(set) var isOn = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func set(_ on: Bool) { on ? start() : stop() }

    private func start() {
        guard tap == nil, AXIsProcessTrusted() else { isOn = tap != nil; return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .leftMouseDragged,
                                    .rightMouseDragged, .otherMouseDragged, .scrollWheel,
                                    .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: { _, type, event, ref in
            guard let ref else { return Unmanaged.passUnretained(event) }
            return Unmanaged<InputLock>.fromOpaque(ref).takeUnretainedValue().filter(type, event)
        }, userInfo: me) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t; source = src; isOn = true
    }

    private func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil; isOn = false
    }

    private func filter(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        // macOS coupe un tap trop lent : on le relance.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Actuator.marker { return pass }

        if type == .keyDown || type == .keyUp {
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 {  // Échap
                if type == .keyDown { DispatchQueue.main.async { self.onEscape() } }
                return nil
            }
            let papaiFront = NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
            return papaiFront ? pass : nil
        }
        if let r = allowedRect(), r.contains(event.location) { return pass }
        return nil
    }
}
