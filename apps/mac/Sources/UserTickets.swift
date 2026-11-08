import SwiftUI

/// Onglet « Tickets » côté utilisateur : ses demandes en cours (`GET …/tickets`),
/// en lecture seule. Le support les traite de son côté.
struct UserTickets: View {
    @Environment(AppModel.self) private var model
    struct Item: Identifiable { var id: String; var number: Int; var task: String; var status: String; var updated: Double; var rdv: Double? }
    @State private var items: [Item] = []
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full").font(rounded(22, .semibold)).foregroundStyle(T.accent)
                Text("Mes demandes en cours").font(rounded(26, .bold))
            }
            VStack(spacing: 0) {
                if failed {
                    note("Impossible de récupérer vos demandes pour le moment.")
                } else if loaded && items.isEmpty {
                    note("Aucune demande en cours. Quand vous demandez de l’aide, elle apparaît ici jusqu’à ce que votre support la règle.")
                } else {
                    ForEach(items) { t in
                        row(t)
                        if t.id != items.last?.id { Rectangle().fill(T.line).frame(height: 1).padding(.leading, 20) }
                    }
                }
            }
            .padding(.vertical, 6)
            .carte(T.rBig)
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(rounded(17)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ t: Item) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t.task.isEmpty ? "Demande d’aide" : "« \(t.task) »").font(rounded(19, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: "T-%04d", t.number) + " · " + when(t)).font(rounded(14)).foregroundStyle(T.muted)
            }
            Spacer(minLength: 0)
            let (txt, ton) = label(t.status)
            Pastille(texte: txt, icone: "circle.fill", ton: ton, taille: 14)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func label(_ s: String) -> (String, Pastille.Ton) {
        switch s {
        case "nouveau": ("Envoyée", .bleu)
        case "en_attente": ("En attente du support", .orange)
        case "rdv": ("Rendez-vous prévu", .violet)
        case "en_cours": ("En cours", .vert)
        case "a_reprendre": ("À reprendre", .orange)
        default: (s, .gris)
        }
    }

    private func when(_ t: Item) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMMM 'à' HH:mm"
        if t.status == "rdv", let r = t.rdv { return "rendez-vous le " + f.string(from: Date(timeIntervalSince1970: r)) }
        return "mise à jour le " + f.string(from: Date(timeIntervalSince1970: t.updated))
    }

    private func load() async {
        if let demo = ProcessInfo.processInfo.environment["PAPAI_DEMO"], !demo.isEmpty {
            items = [Item(id: "a", number: 12, task: "Je n'arrive plus à imprimer", status: "en_attente", updated: Date().timeIntervalSince1970 - 3600, rdv: nil),
                     Item(id: "b", number: 11, task: "Mes photos de Noël ont disparu", status: "nouveau", updated: Date().timeIntervalSince1970 - 7200, rdv: nil)]
            loaded = true; return
        }
        guard let url = URL(string: model.httpBase + "/tickets") else { return }
        guard let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let list = obj["tickets"] as? [[String: Any]] else { failed = true; loaded = true; return }
        failed = false; loaded = true
        items = list.compactMap { t in
            guard let id = t["id"] as? String, (t["status"] as? String) != "resolu" else { return nil }
            return Item(id: id, number: (t["number"] as? NSNumber)?.intValue ?? 0, task: t["task"] as? String ?? "",
                        status: t["status"] as? String ?? "nouveau",
                        updated: (t["updated"] as? NSNumber)?.doubleValue ?? 0, rdv: (t["rdv"] as? NSNumber)?.doubleValue)
        }
    }
}
