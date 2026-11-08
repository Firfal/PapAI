import SwiftUI

@main
struct PapAIApp: App {
    @State private var model = AppModel()
    /// Rôle de ce Mac, fixé par le service informatique (voir `AppRole`) : l'employé par défaut.
    private let role = AppRole.current

    var body: some Scene {
        WindowGroup("PapAI") {
            Group {
                switch role {
                case .aide:
                    // L'app de l'employé : elle s'ouvre directement sur l'accueil.
                    RootView()
                        .environment(model)
                        .onAppear { model.start(); Snapshot.scheduleIfAsked(model) }
                case .support:
                    SupportApp()
                }
            }
            .preferredColorScheme(.light)
            .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 22) {
            Header()
            Group {
                if let r = model.remoteRequest {
                    RemoteRequestView(request: r)
                } else if let q = model.queued, model.queuedShown {
                    QueuedView(ticket: q)
                } else if !(model.screenOK && model.axOK) && !model.permissionsDismissed && model.screen == .home {
                    PermissionsView()
                } else {
                    switch model.screen {
                    case .home: HomeView()
                    case .consent: ConsentView()
                    case .session: SessionView()
                    case .lesson:
                        if let l = model.lesson { LessonView(lesson: l).id(l.id) } else { HomeView() }
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 28)
        .background(T.fond.ignoresSafeArea())
        .background(WindowGrabber { model.window = $0 })
        .disabled(model.guardAlert != nil)
        .overlay { if let l = model.docLesson, model.guardAlert == nil { LessonDocView(lesson: l) } }
        .overlay { if let a = model.guardAlert { GuardAlertView(alert: a) } }
        .id(model.textScale)
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environment(model)
        }
        .sheet(isPresented: $model.showRequests) {
            MesDemandesView().environment(model)
        }
    }
}

struct WindowGrabber: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
    }
}

/// Développement : PAPAI_SNAPSHOT=/chemin.png dessine la fenêtre dans un PNG
/// (sans autorisation d'enregistrement d'écran) puis quitte.
@MainActor
enum Snapshot {
    static func scheduleIfAsked(_ model: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["PAPAI_SNAPSHOT"] else { return }
        // PAPAI_SNAPSHOT_SIZE=900x640 : vérifier la plus petite fenêtre.
        if let t = ProcessInfo.processInfo.environment["PAPAI_SNAPSHOT_SIZE"]?.split(separator: "x"),
           t.count == 2, let w = Double(t[0]), let h = Double(t[1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { model.window?.setContentSize(NSSize(width: w, height: h)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let v = (model.window?.attachedSheet ?? model.window)?.contentView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
            exit(0)
        }
    }
}
