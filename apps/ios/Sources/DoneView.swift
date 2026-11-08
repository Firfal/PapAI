import SwiftUI

struct ZoomedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct DoneView: View {
    @Bindable var model: HelperModel
    @State private var zoom: ZoomedImage?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Terminé", systemImage: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Soin.leaf)
                        if !model.task.isEmpty { Text("« \(model.task) »").font(.system(size: 15)).foregroundStyle(Soin.secondary) }
                        Text(model.doneAnswer ?? "Holo a terminé.").font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Mascotte(humeur: .bravo).frame(width: Mascotte.Taille.carte, height: Mascotte.Taille.carte)
                }
                .padding(20).soinCard(Soin.peach, radius: 28)

                if let saved = model.savedTitle {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Soin.accent, in: Circle())
                        Text("Automate « \(saved) » enregistré.").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
                } else if model.hasDraft {
                    draft
                } else {
                    Button { model.requestLesson() } label: {
                        HStack(spacing: 10) {
                            if model.lessonBusy { ProgressView().tint(.white) }
                            Text(model.lessonBusy ? "Rédaction en cours…" : "Garder comme automate")
                        }
                    }.buttonStyle(CapsuleButtonStyle()).disabled(model.lessonBusy)
                    Text("Holo transforme cette assistance en automate que \(model.senior) pourra relancer sans aide.")
                        .font(.system(size: 13)).foregroundStyle(Soin.secondary)
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.scrollDismissesKeyboard(.interactively)
        .fullScreenCover(item: $zoom) { z in ZoomView(image: z.image) }
    }

    private var draft: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Brouillon de l’automate").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
            TextField("Titre", text: $model.draftTitle)
                .font(.system(size: 18, weight: .semibold)).padding(16).soinCard(radius: 18)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("La tuile ouvrira").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.secondary)
                    Text(model.draftTarget ?? "Aucun dossier : \(model.senior) aura seulement les étapes.")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
            ForEach($model.draftSteps) { $s in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Étape \((model.draftSteps.firstIndex { $0.id == s.id } ?? 0) + 1)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.accent)
                    TextField("Instruction", text: $s.instruction, axis: .vertical)
                        .font(.system(size: 16)).foregroundStyle(Soin.ink)
                    if let c = s.checkpoint { Text("\(model.seniorTitle) doit voir : \(c)").font(.system(size: 13)).foregroundStyle(Soin.secondary) }
                    if let p = s.preview {
                        // Toute la largeur, et un appui l'ouvre en plein écran.
                        Button { zoom = ZoomedImage(image: p) } label: {
                            Image(uiImage: p).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Soin.ink)
                                        .frame(width: 34, height: 34).background(Soin.card, in: Circle()).padding(8)
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, -8)
                        .accessibilityLabel("Agrandir la capture")
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
            }
            Button("Valider") { model.approveLesson() }.buttonStyle(CapsuleButtonStyle())
        }
    }
}
