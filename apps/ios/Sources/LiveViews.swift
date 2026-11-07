import SwiftUI

struct ActiveView: View {
    let model: HelperModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CaptureView(model: model)
                HStack(spacing: 12) {
                    ProgressView().tint(Soin.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Holo travaille sur l’ordinateur de \(model.senior)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Soin.ink)
                        if !model.task.isEmpty { Text("« \(model.task) »").font(.system(size: 14)).foregroundStyle(Soin.secondary) }
                    }
                    Spacer(minLength: 0)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
                if !model.plan.isEmpty { PlanProgress(plan: model.plan, current: model.planStep) }
            }.padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            Button(model.pausing ? "Pause demandée…" : "Mettre en pause") { model.pause() }
                .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink))
                .disabled(model.pausing)
                .padding(.horizontal, 20).padding(.vertical, 8).background(Soin.bg)
        }
    }
}

/// Le plan validé, avec l'étape que Holo exécute.
struct PlanProgress: View {
    let plan: [String]
    let current: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(current.map { "Étape \($0) sur \(plan.count)" } ?? "Plan validé")
                .font(.system(size: 13)).foregroundStyle(Soin.secondary)
            ForEach(Array(plan.enumerated()), id: \.offset) { i, raw in
                let s = PlanStep(id: i, raw: raw)
                let past = current.map { i + 1 < $0 } ?? false
                let now = current == i + 1
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(now ? Soin.accent : past ? Soin.accentSoft : Soin.bg)
                        if past {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Soin.accent)
                        } else {
                            Text("\(i + 1)").font(.system(size: 14, weight: .semibold)).foregroundStyle(now ? Color.white : Soin.ink)
                        }
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title)
                            .font(.system(size: 15, weight: now ? .semibold : .regular))
                            .foregroundStyle(past ? Soin.secondary : Soin.ink)
                        if let detail = s.detail { Text(detail).font(.system(size: 13)).foregroundStyle(Soin.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(now ? "En cours : \(raw)" : past ? "Fait : \(raw)" : raw)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard()
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

/// Capture de l'écran de la personne aidée, avec le viseur quand on prend la main.
struct CaptureView: View {
    let model: HelperModel
    var body: some View {
        if let img = model.frame {
            Image(uiImage: img).resizable().aspectRatio(img.size, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { g in
                        ZStack {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                    guard model.aiming else { return }
                                    model.target = CGPoint(x: min(max(v.location.x / g.size.width, 0), 1),
                                                           y: min(max(v.location.y / g.size.height, 0), 1))
                                })
                            if model.aiming, let t = model.target {
                                Reticle().position(x: t.x * g.size.width, y: t.y * g.size.height)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(model.aiming ? Soin.accent : .clear, lineWidth: 2))
        } else {
            Text("En attente de la première capture d’écran…")
                .font(.system(size: 15)).foregroundStyle(Soin.secondary)
                .frame(maxWidth: .infinity, minHeight: 180).soinCard()
        }
    }
}

struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(Soin.accent, lineWidth: 2).frame(width: 28, height: 28)
            Rectangle().fill(Soin.accent).frame(width: 2, height: 46)
            Rectangle().fill(Soin.accent).frame(width: 46, height: 2)
        }
        .shadow(color: .black.opacity(0.4), radius: 1).allowsHitTesting(false)
    }
}

/// Loupe ×3 posée au-dessus de l'image : le doigt cacherait la cible sinon.
struct Loupe: View {
    let image: UIImage
    let target: CGPoint
    let imageWidth: CGFloat
    private let z: CGFloat = 3
    var body: some View {
        let h = imageWidth * image.size.height / image.size.width
        ZStack(alignment: .topLeading) {
            Color.black
            Image(uiImage: image).resizable()
                .frame(width: imageWidth * z, height: h * z)
                .offset(x: imageWidth / 2 - target.x * imageWidth * z, y: 62 - target.y * h * z)
        }
        .overlay {
            ZStack {
                Rectangle().fill(Soin.accent.opacity(0.9)).frame(width: 1)
                Rectangle().fill(Soin.accent.opacity(0.9)).frame(height: 1)
            }
        }
        .frame(width: imageWidth, height: 124, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Soin.accent, lineWidth: 2))
    }
}

struct HelperView: View {
    @Bindable var model: HelperModel
    @State private var reply = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.aiming {
                    if let img = model.frame, let t = model.target {
                        Loupe(image: img, target: t, imageWidth: UIScreen.main.bounds.width - 40)
                    }
                } else if let q = model.question {
                    questionCard(q)
                }
                CaptureView(model: model)
                if model.aiming { aimBar } else { handButton }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func questionCard(_ q: (text: String, options: [String])) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.questionToSenior
                 ? "Question posée à \(model.senior) sur son écran. Vous pouvez aussi répondre."
                 : "\(model.seniorTitle) a besoin de vous").font(.system(size: 13)).foregroundStyle(Soin.secondary)
            Text(q.text).font(.system(size: 20, weight: .semibold)).foregroundStyle(Soin.ink)
            if !q.options.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(q.options, id: \.self) { o in
                        Button { model.answer(o) } label: {
                            Text(o).font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.ink)
                                .padding(.horizontal, 16).padding(.vertical, 11).background(Soin.card, in: Capsule())
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Votre réponse…", text: $reply).font(.system(size: 16))
                    .padding(.horizontal, 16).frame(height: 48).background(Soin.card, in: Capsule())
                    .submitLabel(.send).onSubmit(sendReply)
                Button(action: sendReply) {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(Soin.ink, in: Circle())
                }.accessibilityLabel("Envoyer")
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).soinCard(Soin.accentSoft, radius: 28)
    }

    private func sendReply() {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { model.answer(t); reply = "" }
    }

    private var handButton: some View {
        VStack(spacing: 8) {
            Button("Prendre la main") { model.setAiming(true) }.buttonStyle(CapsuleButtonStyle())
            Text("Vous pouvez cliquer vous-même sur l’écran de \(model.senior).").font(.system(size: 13)).foregroundStyle(Soin.secondary)
        }
    }

    private var aimBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let age = model.frameAt.map { ctx.date.timeIntervalSince($0) } ?? .infinity
            let stale = age >= HelperModel.frameTTL
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.target == nil ? "Touchez l’écran de \(model.senior) à l’endroit où il faut cliquer." : "Ajustez en gardant le doigt appuyé, puis confirmez.")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Soin.ink)
                    Text(stale ? "Cette capture est trop ancienne : l’écran a pu changer."
                         : "Capture d’il y a \(Int(age)) s, valable \(HelperModel.frameTTL - Double(Int(age))) s encore.".replacingOccurrences(of: ".0 s", with: " s"))
                        .font(.system(size: 13)).foregroundStyle(stale ? Soin.ink : Soin.secondary)
                    if stale { Button("Rafraîchir") { model.refresh() }.font(.system(size: 14, weight: .semibold)).foregroundStyle(Soin.accent) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).soinCard()
                HStack(spacing: 10) {
                    Button(model.sending ? "Envoi…" : "Cliquer ici") { model.confirmClick() }
                        .buttonStyle(CapsuleButtonStyle()).disabled(model.target == nil || stale || model.sending)
                        .opacity(model.target == nil || stale || model.sending ? 0.4 : 1)
                    Button("Annuler") { model.setAiming(false) }
                        .buttonStyle(CapsuleButtonStyle(fill: Soin.card, text: Soin.ink)).frame(width: 130)
                }
            }
        }
    }
}
