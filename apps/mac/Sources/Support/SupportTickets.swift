import SwiftUI

/// Premier onglet de l'accueil support : tous les tickets formulés par tous
/// les utilisateurs reliés à ce poste, les plus récents d'abord.
struct SupportTickets: View {
    let model: HelperModel
    var openUser: (Person) -> Void

    @State private var board = TicketBoard()
    @State private var filter = 0   // 0 ouverts, 1 tous

    private var tickets: [SupportTicket] { board.tickets }
    private var loading: Bool { board.loading }
    private var errors: [String] { board.errors }
    private var busy: String? { board.busy }

    private var shown: [SupportTicket] { filter == 0 ? tickets.filter(\.isOpen) : tickets }

    var body: some View {
        Panneau {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tickets").font(rounded(30, .bold))
                    let open = tickets.filter(\.isOpen).count
                    Text(open == 0 ? "Aucune demande en attente." :
                         "\(open) demande\(open > 1 ? "s" : "") ouverte\(open > 1 ? "s" : "") chez vos utilisateurs.")
                        .font(rounded(17, .medium)).opacity(0.92)
                }
                Spacer(minLength: 0)
                if loading { ProgressView().controlSize(.small).tint(.white) }
            }
        } corps: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Onglets(options: [("Ouverts", 0), ("Tous", 1)], selection: $filter).frame(maxWidth: 260)
                    Spacer()
                    Button("Actualiser") { Task { await load() } }
                        .buttonStyle(.plain).font(rounded(14, .semibold)).foregroundStyle(T.leaf)
                }
                ForEach(errors, id: \.self) { e in
                    Label(e, systemImage: "exclamationmark.triangle").font(rounded(14)).foregroundStyle(T.danger)
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if model.people.isEmpty {
                            empty("Aucun utilisateur relié. Reliez un ordinateur depuis l’onglet Utilisateurs.")
                        } else if shown.isEmpty && !loading {
                            empty(filter == 0 ? "Rien à traiter. Les nouvelles demandes de vos utilisateurs arriveront ici."
                                              : "Aucun ticket pour l’instant.")
                        }
                        ForEach(shown) { t in row(t) }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(rounded(16)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }

    private func row(_ t: SupportTicket) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(t.label).font(rounded(14, .semibold)).foregroundStyle(T.muted).monospacedDigit()
                    status(t)
                    Text(t.person.name.isEmpty ? "Utilisateur" : t.person.name).font(rounded(14, .semibold))
                    if !t.assignee.isEmpty {
                        Text("· pris par \(t.assignee)").font(rounded(13)).foregroundStyle(T.muted)
                    }
                }
                Text(t.task.isEmpty ? "Demande sans texte" : "« \(t.task) »").font(rounded(18, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(when(t)).font(rounded(13)).foregroundStyle(T.muted)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if t.isOpen && t.status != "en_cours" {
                    Button(busy == t.id ? "…" : "Prendre en charge") { Task { await act(t, "take") } }
                        .buttonStyle(PillStyle(height: 40)).disabled(busy != nil)
                }
                Button("Voir l’utilisateur") { openUser(t.person) }
                    .buttonStyle(PillStyle(filled: false, height: 36))
                if t.isOpen && t.status != "en_cours" {
                    Button("Clore") { Task { await act(t, "close") } }
                        .buttonStyle(.plain).font(rounded(13, .semibold)).foregroundStyle(T.muted).disabled(busy != nil)
                } else if !t.isOpen {
                    Button("Rouvrir") { Task { await act(t, "reopen") } }
                        .buttonStyle(.plain).font(rounded(13, .semibold)).foregroundStyle(T.muted).disabled(busy != nil)
                }
            }
        }
        .padding(14).carte()
    }

    private func status(_ t: SupportTicket) -> some View {
        Pastille(texte: t.statut.texte, icone: "circle.fill", ton: t.statut.ton, taille: 12)
    }

    private func when(_ t: SupportTicket) -> String { t.quand }

    // MARK: Réseau

    private func load() async { await board.load(model.people) }

    private func act(_ t: SupportTicket, _ action: String) async {
        if let e = await board.act(t, action, by: model.helperName ?? "Support", people: model.people) {
            model.showToast(e)
        } else if action == "take" {
            model.showToast("Demande proposée à \(t.person.name.isEmpty ? "l’utilisateur" : t.person.name)")
            openUser(t.person)
        }
    }
}
