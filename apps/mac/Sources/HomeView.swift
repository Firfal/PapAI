import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var request = ""
    @State private var warning: String?
    @FocusState private var focused: Bool
    @State private var dictation = Dictation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            helpCard
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) { shortcuts; apps }
                    .padding(.bottom, 8)
            }
            .frame(width: 400)
        }
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Bonjour \(model.firstName)")
                .font(rounded(52, .semibold)).tracking(-0.8)
            Text("Un souci sur l'ordinateur ? Dites-le simplement, un message part tout de suite à \(model.helperName).")
                .font(rounded(21)).foregroundStyle(T.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Par exemple : je ne retrouve pas mes photos", text: $request, axis: .vertical)
                .textFieldStyle(.plain).font(rounded(22)).lineLimit(1...3)
                .focused($focused)
                .padding(.horizontal, 24).padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                .padding(.top, 8)
            if let warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(rounded(17, .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(T.card))
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                micButton
                Button(action: submit) {
                    Text("J'ai besoin d'aide").font(rounded(26, .semibold))
                        .padding(.horizontal, 28).frame(maxWidth: .infinity).frame(height: 78)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(T.ink))
                }
                .buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(T.ink)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))
    }

    private var micButton: some View {
        let listening = dictation.phase == .listening
        return Button {
            warning = nil
            dictation.toggle(httpBase: model.httpBase) { text in
                request = request.isEmpty ? text : request + " " + text
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if listening {
                        Circle().fill(T.accent.opacity(0.25))
                            .frame(width: 78, height: 78)
                            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.12 : 0.9))
                    }
                    Circle().fill(listening ? T.accent : .white).frame(width: 62, height: 62)
                    if dictation.phase == .transcribing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: listening ? "stop.fill" : "mic.fill")
                            .foregroundStyle(listening ? .white : T.ink).font(.system(size: 24))
                    }
                }
                .frame(width: 78, height: 78)
                if listening {
                    Text("Je vous écoute…").font(rounded(20, .semibold)).foregroundStyle(T.accent)
                } else if dictation.phase == .transcribing {
                    Text("Je note…").font(rounded(20, .semibold)).foregroundStyle(T.muted)
                }
            }
            .padding(.trailing, dictation.phase == .idle ? 0 : 14)
        }
        .buttonStyle(PressStyle())
        .disabled(dictation.phase == .transcribing)
        .accessibilityLabel(listening ? "Arrêter la dictée" : "Dicter ma demande")
        .onChange(of: listening) { _, on in
            if on, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            } else { withAnimation(.none) { pulse = false } }
        }
        .onChange(of: dictation.message) { _, m in if let m { warning = m; dictation.message = nil } }
    }

    private func submit() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { warning = "Dites en quelques mots ce qui ne va pas."; focused = true; return }
        if !model.connected { warning = "Je ne joins pas \(model.helperName) pour le moment. Réessayez dans un instant."; return }
        warning = nil
        // Étape 4 : l'écran de consentement passe avant tout partage.
        model.requestConsent(task: text)
        request = ""
    }

    // MARK: Droite

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mes tutoriels").font(rounded(24, .semibold))
            if let n = model.notice {
                Text(n).font(rounded(17, .medium))
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.mint))
            }
            if model.lessons.isEmpty {
                Text("\(model.HelperName) pourra ajouter ici ce que vous avez fait ensemble, pour le refaire sans aide.")
                    .font(rounded(17)).foregroundStyle(T.muted)
                    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
            }
            ForEach(model.lessons) { l in tile(l) }
        }
        .foregroundStyle(T.ink)
    }

    private func tile(_ l: Lesson) -> some View {
        VStack(spacing: 12) {
            Button { model.runShortcut(l) } label: {
                HStack(spacing: 16) {
                    Circle().fill(T.mint).frame(width: 56, height: 56)
                        .overlay(Image(systemName: Shortcuts.symbol(for: l.shortcut?.folder))
                            .font(.system(size: 22, weight: .medium)).foregroundStyle(T.accent))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.title).font(rounded(20, .semibold)).multilineTextAlignment(.leading)
                        Text("Un clic, sans attendre").font(rounded(15)).foregroundStyle(T.muted)
                    }
                    Spacer(minLength: 0)
                    Circle().fill(T.ink).frame(width: 42, height: 42)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.white))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(l.title)
            if !(l.steps ?? []).isEmpty {
                Button { model.openLesson(l) } label: {
                    Text("Montrez-moi").font(rounded(16, .semibold)).foregroundStyle(T.accent)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(T.mint))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
    }

    private static let apps: [(String, String)] = [
        ("Mail", "com.apple.mail"), ("Photos", "com.apple.Photos"), ("Safari", "com.apple.Safari"),
        ("FaceTime", "com.apple.FaceTime"), ("Finder", "com.apple.finder"), ("Calendrier", "com.apple.iCal"),
    ]

    private var apps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mes applications").font(rounded(24, .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(Self.apps, id: \.1) { name, bundle in
                    Button { openApp(bundle) } label: {
                        VStack(spacing: 8) {
                            Circle().fill(T.card).frame(width: 88, height: 88)
                                .overlay(Image(nsImage: icon(bundle)).resizable().frame(width: 52, height: 52))
                            Text(name).font(rounded(15, .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Ouvrir \(name)")
                }
            }
        }
        .foregroundStyle(T.ink)
    }

    private func icon(_ bundle: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func openApp(_ bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            model.showNotice("Cette application n'est pas disponible sur cet ordinateur.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}
