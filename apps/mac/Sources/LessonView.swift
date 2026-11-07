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
            // La capture prend toute la place : c'est elle qui montre où cliquer.
            // Le texte tient dans une colonne à droite.
            HStack(alignment: .top, spacing: 28) {
                if let image {
                    Button { zoomed = true } label: {
                        Image(nsImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: T.r, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(rounded(14, .semibold)).foregroundStyle(T.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(T.card)).padding(12)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Agrandir la capture")
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(lesson.title).font(rounded(18, .semibold)).foregroundStyle(T.muted)
                    if steps.isEmpty {
                        Text("Pas de pas à pas pour ce raccourci.").font(rounded(30, .semibold))
                    } else {
                        let step = steps[min(i, steps.count - 1)]
                        Text("Étape \(i + 1) sur \(steps.count)").font(rounded(18, .semibold)).foregroundStyle(T.accent)
                        Text(step.instruction ?? "").font(rounded(image == nil ? 36 : 28, .semibold)).tracking(-0.4)
                            .fixedSize(horizontal: false, vertical: true)
                        if let c = step.checkpoint, !c.isEmpty {
                            Text("Vous devriez voir : \(c)").font(rounded(18))
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: image == nil ? nil : 300, alignment: .topLeading)
                .frame(maxWidth: image == nil ? .infinity : 300, alignment: .topLeading)
            }
            .foregroundStyle(T.ink)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))
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
                .buttonStyle(PillStyle(height: 72)).keyboardShortcut(.defaultAction)
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
