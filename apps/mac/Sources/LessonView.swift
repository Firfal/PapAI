import SwiftUI

/// « Montrez-moi » : le pas à pas d'un automatisme. N'exécute aucun clic.
struct LessonView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @State private var i = 0
    @State private var image: NSImage?
    @State private var zoomed = false

    private var steps: [Lesson.Step] { lesson.steps ?? [] }

    var body: some View {
        VStack(spacing: 18) {
            Panneau(padding: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    if !steps.isEmpty {
                        Pastille(texte: "Étape \(min(i, steps.count - 1) + 1) sur \(steps.count)", ton: .bleu, taille: 16)
                    }
                    Text(lesson.title).font(rounded(30, .bold)).tracking(-0.4)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            } corps: {
                // La capture prend toute la place : c'est elle qui montre où cliquer.
                // Le texte tient dans une colonne à droite.
                HStack(alignment: .top, spacing: 28) {
                    if let image {
                        Button { zoomed = true } label: {
                            Image(nsImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: T.r, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: T.r, style: .continuous).strokeBorder(T.line))
                                .overlay(alignment: .bottomTrailing) {
                                    Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(rounded(14, .semibold)).foregroundStyle(T.ink)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Capsule().fill(T.card).shadow(color: T.ombre.opacity(0.15), radius: 8, y: 3)).padding(12)
                                }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Agrandir la capture")
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        if steps.isEmpty {
                            Text("Cet automate n'a pas encore d'étapes.").font(rounded(30, .semibold))
                        } else {
                            let step = steps[min(i, steps.count - 1)]
                            Text(step.instruction ?? "").font(rounded(image == nil ? 36 : 28, .semibold)).tracking(-0.4)
                                .fixedSize(horizontal: false, vertical: true)
                            if let c = step.checkpoint, !c.isEmpty {
                                Label("Vous devriez voir : \(c)", systemImage: "eye")
                                    .font(rounded(18))
                                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .champ(T.r)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: image == nil ? nil : 300, alignment: .topLeading)
                    .frame(maxWidth: image == nil ? .infinity : 300, alignment: .topLeading)
                }
            }
            .overlay {
                if zoomed, let image {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.ink)
                        Image(nsImage: image).resizable().scaledToFit().padding(16)
                        Button("Fermer") { zoomed = false }.buttonStyle(PillStyle(filled: false, height: 52))
                            .frame(width: 140).padding(20)
                    }
                    .onTapGesture { zoomed = false }
                }
            }

            HStack(spacing: 14) {
                Button("Fermer") { model.screen = .home }.buttonStyle(PillStyle(filled: false, height: 72))
                    .keyboardShortcut(.cancelAction)
                if i > 0 {
                    Button("Précédent") { i -= 1 }.buttonStyle(PillStyle(filled: false, height: 72))
                }
                Button {
                    if i >= steps.count - 1 { model.screen = .home } else { i += 1 }
                } label: {
                    Text(i >= steps.count - 1 ? "Terminé" : "Suivant").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 72, icone: i >= steps.count - 1 ? "checkmark.circle" : "arrow.right.circle", plein: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .task(id: i) { zoomed = false; await loadImage() }
    }

    private func loadImage() async {
        image = nil
        guard !steps.isEmpty, let name = steps[min(i, steps.count - 1)].image,
              let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(model.httpBase)/lessons/\(lesson.id)/\(enc)") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url) { image = NSImage(data: data) }
    }
}
