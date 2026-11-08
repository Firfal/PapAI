import Foundation

@main
struct SupportPairingTest {
    @MainActor static func main() {
        let model = AppModel()
        model.connected = false
        model.openSupportPairing()
        precondition(model.showHelpers && model.pairingWhenConnected)
        precondition(model.pairCode == nil)
        model.startPendingPairing()
        precondition(model.pairingWhenConnected)
        model.connected = true
        model.startPendingPairing()
        precondition(!model.pairingWhenConnected)

        model.connected = false
        model.openSupportPairing()
        model.stopPairing()
        model.connected = true
        model.startPendingPairing()
        precondition(!model.pairingWhenConnected && model.pairCode == nil)

        model.pairAdded = "Claire"
        model.openSupportPairing()
        precondition(model.showHelpers && !model.pairingWhenConnected)
        precondition(model.pairAdded == nil)
        model.pairCode = "482913"
        model.pairURL = "https://papai.example/p/482913"
        model.pairAppURL = AppModel.appPairingURL(model.pairURL!)
        model.stopPairing()
        precondition(model.pairCode == nil && model.pairURL == nil && model.pairAppURL == nil)
        print("Appairage depuis les Réglages : connecté, attente, reconnexion et annulation OK")
    }
}
