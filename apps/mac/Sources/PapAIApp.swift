import SwiftUI

@main
struct PapAIApp: App {
    @State private var model = AppModel()
    /// Rôle de ce Mac : rien tant qu'il n'est pas choisi (voir `AppRole`).
    @State private var role = AppRole.saved

    var body: some Scene {
        WindowGroup("PapAI") {
            Group {
                switch role {
                case .aide:
                    // L'app de la personne aidée, inchangée.
                    RootView()
                        .environment(model)
                        .onAppear { model.start(); Snapshot.scheduleIfAsked(model) }
                case .support:
                    SupportApp()
                case nil:
                    RoleChoiceView { r in
                        UserDefaults.standard.set(r.rawValue, forKey: AppRole.key)
                        withAnimation(.easeInOut(duration: 0.25)) { role = r }
                    }
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
                if !model.onboarded {
                    OnboardingView()
                } else if let r = model.remoteRequest {
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
        .sheet(isPresented: Binding(
            get: { model.showSettings || model.showHelpers || model.pairRequest != nil },
            set: { if !$0 { model.showSettings = false; model.showHelpers = false } }
        )) {
            Group {
                if let p = model.pairRequest {
                    PairRequestView(request: p).padding(24)
                        .frame(width: 820, height: 580).background(T.bg)
                } else if model.showSettings {
                    SettingsView()
                } else {
                    VStack(alignment: .trailing, spacing: 18) {
                        ScrollView { HelpersPanel() }
                        Button("Fermer") { model.stopPairing(); model.showHelpers = false }
                            .buttonStyle(PillStyle(height: 54)).keyboardShortcut(.cancelAction)
                    }
                    .padding(24).frame(width: 820, height: 580).background(T.bg)
                    .onDisappear { model.stopPairing() }
                }
            }
            .environment(model)
            .interactiveDismissDisabled(model.pairRequest != nil)
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
