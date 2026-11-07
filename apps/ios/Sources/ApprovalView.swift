import SwiftUI

struct ApprovalView: View {
    @Bindable var model: HelperModel
    @State private var showRefine = false
    @State private var confirmRefuse = false
    @State private var zoom = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RequestCard(model: model, onThumb: { zoom = true })
                HStack {
                    Text("Plan proposé par Holo").font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                    Spacer()
                    Text("\(model.plan.count) étape\(model.plan.count > 1 ? "s" : "")")
                        .font(.system(size: 13)).foregroundStyle(Soin.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Soin.card, in: Capsule())
                }.padding(.horizontal, 2)
                VStack(spacing: 12) {
                    ForEach(Array(model.plan.enumerated()), id: \.offset) { i, raw in
                        let s = PlanStep(id: i, raw: raw)
                        HStack(spacing: 14) {
                            Text("\(i + 1)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                                .frame(width: 38, height: 38).background(Soin.bg, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Soin.ink)
                                if let d = s.detail { Text(d).font(.system(size: 14)).foregroundStyle(Soin.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading).soinCard()
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showRefine) { RefineSheet(model: model) }
        .confirmationDialog("Refuser ce plan ?", isPresented: $confirmRefuse, titleVisibility: .visible) {
            Button("Refuser le plan", role: .destructive) { model.refusePlan() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Rien ne sera fait, et l’ordinateur de \(model.senior) l’indiquera.") }
        .fullScreenCover(isPresented: $zoom) { ZoomView(image: model.frame) }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button { model.approvePlan() } label: {
                    HStack(spacing: 10) {
                        if model.planBusy { ProgressView().tint(.white) } else { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)) }
                        Text("Valider le plan")
                    }
                }
                .buttonStyle(CapsuleButtonStyle()).disabled(model.planBusy)
                Button { showRefine = true } label: {
                    Image(systemName: "pencil").font(.system(size: 18)).foregroundStyle(Soin.ink)
                }
                .buttonStyle(RoundIconButtonStyle()).disabled(model.planBusy).accessibilityLabel("Préciser")
                Button { confirmRefuse = true } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .medium)).foregroundStyle(Soin.ink)
                }
                .buttonStyle(RoundIconButtonStyle()).disabled(model.planBusy).accessibilityLabel("Refuser")
            }
            Text("Rien ne se fait sans votre accord.").font(.system(size: 13)).foregroundStyle(Soin.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Soin.bg)
    }
}

struct RefineSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Préciser le plan").font(.system(size: 24, weight: .bold)).foregroundStyle(Soin.ink)
            Text("Dites à Holo ce qu’il doit changer. Il proposera un nouveau plan.")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
            TextField("Par exemple : les photos sont dans Images > Noël 2025", text: $text, axis: .vertical)
                .lineLimit(3...6).focused($focused)
                .font(.system(size: 17)).padding(16).soinCard(radius: 18)
            Spacer()
            Button("Envoyer à Holo") {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { model.refinePlan(t); dismiss() }
            }
            .buttonStyle(CapsuleButtonStyle()).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(24).background(Soin.bg.ignoresSafeArea())
        .presentationDetents([.medium]).onAppear { focused = true }
    }
}

struct ZoomView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Soin.ink.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: .infinity) }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                    .frame(width: 44, height: 44).background(Soin.card, in: Circle())
            }.padding(20).accessibilityLabel("Fermer")
        }.onTapGesture { dismiss() }
    }
}
