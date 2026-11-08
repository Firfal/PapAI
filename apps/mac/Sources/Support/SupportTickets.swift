import SwiftUI

/// Un ticket d'un utilisateur (`GET …/k/<clé>/tickets`), avec la personne d'où il vient.
struct SupportTicket: Identifiable {
    var id: String { person.key + "/" + tid }
    var tid: String
    var number: Int
    var task: String
    var status: String
    var source: String
    var updated: Double
    var created: Double
    var rdv: Double?
    var assignee: String
    /// Où un automate s'est arrêté : « Étape 2 (Ouvrir Photos) : bouton introuvable ».
    var blocked: String?
    var person: Person

    var label: String { String(format: "T-%04d", number) }
    var isOpen: Bool { status != "resolu" }

    init?(_ d: [String: Any], person: Person) {
        guard let id = d["id"] as? String else { return nil }
        tid = id
        number = (d["number"] as? NSNumber)?.intValue ?? 0
        task = d["task"] as? String ?? ""
        status = d["status"] as? String ?? "nouveau"
        source = d["source"] as? String ?? ""
        updated = (d["updated"] as? NSNumber)?.doubleValue ?? 0
        created = (d["created"] as? NSNumber)?.doubleValue ?? updated
        rdv = (d["rdv"] as? NSNumber)?.doubleValue
        assignee = d["assignee"] as? String ?? ""
        if let b = d["blocked"] as? [String: Any], let n = (b["step"] as? NSNumber)?.intValue {
            let label = (b["label"] as? String).flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
            let reason = (b["reason"] as? String).flatMap { $0.isEmpty ? nil : " : \($0)" } ?? ""
            blocked = "Bloqué à l’étape \(n)\(label)\(reason)"
        }
        self.person = person
    }
}

/// Premier onglet de l'accueil support : tous les tickets formulés par tous
/// les utilisateurs reliés à ce poste, les plus récents d'abord.
struct SupportTickets: View {
    let model: HelperModel
    var openUser: (Person) -> Void

    @State private var tickets: [SupportTicket] = []
    @State private var loading = false
    @State private var errors: [String] = []
    @State private var filter = 0   // 0 ouverts, 1 tous
    @State private var busy: String?

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
                if let b = t.blocked {
                    Label(b, systemImage: "exclamationmark.circle").font(rounded(14, .medium))
                        .foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
                }
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
        let (txt, ton): (String, Pastille.Ton) = switch t.status {
        case "nouveau": ("Nouveau", .bleu)
        case "en_attente": ("En attente", .orange)
        case "rdv": ("Rendez-vous", .violet)
        case "en_cours": ("En cours", .vert)
        case "a_reprendre": ("À reprendre", .orange)
        case "resolu": ("Résolu", .gris)
        default: (t.status, .gris)
        }
        return Pastille(texte: txt, icone: "circle.fill", ton: ton, taille: 12)
    }

    private func when(_ t: SupportTicket) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM 'à' HH:mm"
        if t.status == "rdv", let r = t.rdv { return "Rendez-vous le " + f.string(from: Date(timeIntervalSince1970: r)) }
        return "Mis à jour le " + f.string(from: Date(timeIntervalSince1970: t.updated))
    }

    // MARK: Réseau

    private func load() async {
        let people = model.people
        guard !people.isEmpty else { tickets = []; return }
        loading = true; defer { loading = false }
        var all: [SupportTicket] = []
        var errs: [String] = []
        await withTaskGroup(of: ([SupportTicket], String?).self) { g in
            for p in people {
                g.addTask {
                    guard let url = URL(string: AutomateLibrary.base(p) + "/tickets"),
                          let (d, r) = try? await URLSession.shared.data(from: url),
                          (r as? HTTPURLResponse)?.statusCode == 200,
                          let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                          let list = obj["tickets"] as? [[String: Any]]
                    else { return ([], "Tickets de \(p.name.isEmpty ? "un utilisateur" : p.name) indisponibles") }
                    return (list.compactMap { SupportTicket($0, person: p) }, nil)
                }
            }
            for await (l, e) in g { all += l; if let e { errs.append(e) } }
        }
        tickets = all.sorted { $0.updated > $1.updated }
        errors = errs
    }

    private func act(_ t: SupportTicket, _ action: String) async {
        guard let url = URL(string: AutomateLibrary.base(t.person) + "/tickets/" + t.tid) else { return }
        busy = t.id; defer { busy = nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "by": model.helperName ?? "Support"])
        if let (d, r) = try? await URLSession.shared.data(for: req) {
            if (r as? HTTPURLResponse)?.statusCode != 200 {
                let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                model.showToast(obj?["error"] as? String ?? "Action refusée")
            } else if action == "take" {
                model.showToast("Demande proposée à \(t.person.name.isEmpty ? "l’utilisateur" : t.person.name)")
                openUser(t.person)
            }
        } else {
            model.showToast("Serveur injoignable")
        }
        await load()
    }
}
