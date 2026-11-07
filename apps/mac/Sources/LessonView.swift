import SwiftUI

/// « Montrez-moi » : le pas à pas d'un automatisme. N'exécute aucun clic.
struct LessonView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @State private var i = 0
    @State private var image: NSImage?

    private var steps: [Lesson.Step] { lesson.steps ?? [] }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 20) {
                Text(lesson.title).font(rounded(18, .semibold)).foregroundStyle(T.muted)
                if steps.isEmpty {
                    Text("Pas de pas à pas pour ce raccourci.").font(rounded(30, .semibold))
                } else {
                    let step = steps[min(i, steps.count - 1)]
                    Text("Étape \(i + 1) sur \(steps.count)").font(rounded(18, .semibold)).foregroundStyle(T.accent)
                    Text(step.instruction ?? "").font(rounded(36, .semibold)).tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let c = step.checkpoint, !c.isEmpty {
                        Text("Vous devriez voir : \(c)").font(rounded(19))
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
                    }
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: T.r, style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { Spacer(minLength: 0) }
                }
            }
            .foregroundStyle(T.ink)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: T.rBig, style: .continuous).fill(T.mint))

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
        .task(id: i) { await loadImage() }
    }

    private func loadImage() async {
        image = nil
        guard !steps.isEmpty, let name = steps[min(i, steps.count - 1)].image,
              let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(model.httpBase)/lessons/\(lesson.id)/\(enc)") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url) { image = NSImage(data: data) }
    }
}
