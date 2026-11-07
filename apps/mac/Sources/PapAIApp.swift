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
                .onAppear { model.start() }
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
                if !(model.screenOK && model.axOK) && !model.permissionsDismissed && model.screen == .home {
                    PermissionsView()
                } else {
                    switch model.screen {
                    case .home: HomeView()
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
        .sheet(isPresented: $model.showSettings) { SettingsView() }
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
