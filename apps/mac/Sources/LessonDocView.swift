import SwiftUI

/// La fiche d'un automate, ouverte d'un clic sur sa ligne : à quoi il sert, ses
/// étapes, puis « Montrez-moi » (le pas à pas) ou « Exécuter ». L'arrière-plan
/// s'assombrit ; un clic dehors ou Échap referme.
struct LessonDocView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    /// Le clic qui ouvre la fiche ne doit pas déclencher un de ses boutons.
    @State private var pret = false

    private var steps: [String] {
        (lesson.steps ?? []).compactMap { $0.instruction?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            T.ink.opacity(0.45).ignoresSafeArea()
                .onTapGesture { fermer() }
                .accessibilityHidden(true)
            Panneau(padding: 28) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Automate").font(rounded(15, .semibold)).opacity(0.85)
                        Text(lesson.title).font(rounded(30, .bold)).tracking(-0.4)
                            .fixedSize(horizontal: false, vertical: true)
                        if let p = lesson.publisher, !p.isEmpty {
                            Text("Fourni par \(p)").font(rounded(15)).opacity(0.85)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(action: fermer) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(Circle().fill(.white.opacity(0.22)))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Fermer")
                }
            } corps: {
                VStack(alignment: .leading, spacing: 18) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let d = lesson.description, !d.isEmpty {
                                Text(d).font(rounded(19)).foregroundStyle(T.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !steps.isEmpty {
                                Text("Les étapes").font(rounded(17, .semibold)).foregroundStyle(T.muted)
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(i + 1)").font(rounded(16, .semibold)).foregroundStyle(T.leaf)
                                                .frame(width: 32, height: 32)
                                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(T.mint))
                                            Text(s).font(rounded(18)).fixedSize(horizontal: false, vertical: true)
                                                .padding(.top, 4)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    HStack(spacing: 12) {
                        if !steps.isEmpty {
                            Button {
                                fermer(); model.openLesson(lesson)
                            } label: { Text("Montrez-moi").frame(maxWidth: .infinity) }
                            .buttonStyle(PillStyle(filled: false, height: 58))
                        }
                        Button {
                            fermer(); model.runShortcut(lesson)
                        } label: { Text("Exécuter").frame(maxWidth: .infinity) }
                        .buttonStyle(PillStyle(height: 58, icone: "play.circle", plein: true))
                    }
                }
            }
            .frame(maxWidth: 620, maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)
            .padding(32)
        }
        .allowsHitTesting(pret)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            pret = true
        }
        .transition(.opacity)
    }

    private func fermer() {
        withAnimation(.easeOut(duration: 0.18)) { model.docLesson = nil }
    }
}
