import SwiftUI

struct MesDemandesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mes demandes").font(rounded(30, .bold))
                Spacer()
                Button("Fermer") { dismiss() }
                    .buttonStyle(PillStyle(filled: false, height: 44))
                    .keyboardShortcut(.cancelAction)
            }
            .foregroundStyle(.white)
            .padding(24).frame(maxWidth: .infinity).background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.requestsLoading {
                        HStack(spacing: 12) { ProgressView(); Text("Chargement…") }
                    } else if model.requestsError {
                        Text("Liste indisponible pour l'instant.")
                    } else if model.requests.isEmpty {
                        Text("Aucune demande pour l'instant.")
                    } else {
                        ForEach(model.requests) { request in card(request) }
                    }
                }
                .font(rounded(20)).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(T.ink)
        .frame(width: 720, height: 660).background(T.bg)
        .task { await model.refreshRequests() }
    }

    private func card(_ request: UserRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: request.dateText).foregroundStyle(T.muted)
                Spacer()
                Text(verbatim: request.statusText).font(rounded(17, .semibold)).foregroundStyle(T.leaf)
            }
            Text(verbatim: request.task).font(rounded(22, .semibold))
            if let solution = request.solution {
                switch solution.kind {
                case "automate":
                    Text(verbatim: "Réglée par l'automate « \(solution.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Automate") »")
                case "plan":
                    Text("Plan exécuté").font(rounded(18, .semibold))
                    ForEach(Array((solution.steps ?? []).enumerated()), id: \.offset) { index, step in
                        Text(verbatim: "\(index + 1). \(step)")
                    }
                case "answer":
                    Text("Réponse validée par le support").font(rounded(18, .semibold))
                    Text(verbatim: solution.text ?? "")
                    ForEach(Array((solution.sources ?? []).enumerated()), id: \.offset) { _, source in
                        Text(verbatim: [source.title, source.url].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(rounded(17)).foregroundStyle(T.muted)
                    }
                default: EmptyView()
                }
            }
            if request.relaunchID(availableIDs: Set(model.lessons.map(\.id))) != nil {
                Button("Relancer") { model.relaunchRequest(request); dismiss() }
                    .buttonStyle(PillStyle(height: 44))
            }
        }
        .font(rounded(18)).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).carte()
    }
}
