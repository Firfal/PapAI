import AVFoundation
import Observation

@MainActor @Observable
final class MicPresence {
    static let shared = MicPresence()
    var demande = false
    private(set) var microPresent = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        actualiser()
        for nom in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: nom, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.actualiser() }
            })
        }
    }

    private func actualiser() {
        let env = ProcessInfo.processInfo.environment
        let simulation = env["PAPAI_DEMO"] != nil && env["PAPAI_DEMO_MIC"] == "1"
        microPresent = env["PAPAI_NOMIC"] != "1" && (simulation ||
            !AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                              position: .unspecified).devices.isEmpty)
    }
}
