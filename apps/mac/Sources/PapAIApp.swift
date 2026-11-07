import SwiftUI

@main
struct PapAIApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("PapAI") {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear { model.start(); Snapshot.scheduleIfAsked(model) }
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
            Header().padding(.top, 24)
            Group {
                if !model.onboarded {
                    OnboardingView()
                } else if let r = model.remoteRequest {
                    RemoteRequestView(request: r)
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
        .background(T.bg.ignoresSafeArea())
        .background(WindowGrabber { model.window = $0 })
        .id(model.textScale)
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $model.showHelpers) {
            VStack(alignment: .trailing, spacing: 18) {
                HelpersPanel()
                Button("Fermer") { model.stopPairing(); model.showHelpers = false }
                    .buttonStyle(PillStyle(height: 54)).keyboardShortcut(.cancelAction)
            }
            .padding(36).frame(width: 820).frame(minHeight: 460).background(T.mint)
            .environment(model)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let v = model.window?.contentView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
