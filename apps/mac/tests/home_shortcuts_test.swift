import AVFoundation
import Foundation

@main
struct HomeShortcutsTest {
    @MainActor static func main() {
        let raccourcis = HomeShortcuts.shared
        let attendu: Bool
        switch CommandLine.arguments.last {
        case "absent": attendu = false
        case "present": attendu = true
        default:
            attendu = !AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                mediaType: .audio, position: .unspecified).devices.isEmpty
        }
        precondition(raccourcis.microPresent == attendu, "Présence initiale du micro")
        for nom in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.post(name: nom, object: nil)
            precondition(raccourcis.microPresent == attendu, "Actualisation du micro")
        }
        precondition(!raccourcis.demande)
        raccourcis.demande = true
        precondition(raccourcis.demande)
        raccourcis.demande = false
        precondition(!raccourcis.demande)
        print("Présence micro et signal d'accueil : OK (\(CommandLine.arguments.last ?? "réel"))")
    }
}
