import SwiftUI

struct DoneView: View {
    @Bindable var model: HelperModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Terminé", systemImage: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.accent)
                    if !model.task.isEmpty { Text("« \(model.task) »").font(.system(size: 14)).foregroundStyle(Soin.secondary) }
                    Text(model.doneAnswer ?? "Holo a terminé.").font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading).soinCard(Soin.accentSoft, radius: 28)

                if let saved = model.savedTitle {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Soin.accent, in: Circle())
                        Text("Automatisme « \(saved) » enregistré.").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
                } else if model.hasDraft {
                    draft
                } else {
                    Button { model.requestLesson() } label: {
                        HStack(spacing: 10) {
                            if model.lessonBusy { ProgressView().tint(.white) }
                            Text(model.lessonBusy ? "Rédaction en cours…" : "Garder comme automatisme")
                        }
                    }.buttonStyle(CapsuleButtonStyle()).disabled(model.lessonBusy)
                    Text("Holo transforme cette session en pas à pas que \(model.senior) pourra relancer sans aide.")
                        .font(.system(size: 13)).foregroundStyle(Soin.secondary)
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.scrollDismissesKeyboard(.interactively)
    }

    private var draft: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Brouillon de l’automatisme").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
            TextField("Titre", text: $model.draftTitle)
                .font(.system(size: 18, weight: .semibold)).padding(16).soinCard(radius: 18)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("La tuile ouvrira").font(.system(size: 13, weight: .semibold)).foregroundStyle(Soin.secondary)
                    Text(model.draftTarget ?? "Aucun dossier : \(model.senior) aura seulement le pas à pas.")
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
                        Image(uiImage: p).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
            }
            Button("Valider") { model.approveLesson() }.buttonStyle(CapsuleButtonStyle())
        }
    }
}
