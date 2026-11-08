import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.string(forKey: "demoFile") == nil {   // pilote de test : pas de dialogue
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        return true
    }
    // Affiche aussi la bannière quand l'app est au premier plan.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct PapAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = HelperModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.light)
                .onOpenURL { model.open(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.wakeUp() }
                }
                .task {
                    model.start()
                    #if DEBUG
                    model.startDebugDriver()
                    #endif
                }
        }
    }
}
