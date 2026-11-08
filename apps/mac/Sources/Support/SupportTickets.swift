import SwiftUI

struct SupportTicketSuggestion: Identifiable {
    var id: String
    var title: String
}

struct SupportTicketProposal {
    var title: String
    var steps: [String]
    var warning: String
}

struct SupportTicketDecision {
    var kind: String
    var by: String
    var steps: [String]
    var slots: [Double]
    var rdv: Double?
    var other: Bool
}

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
    var suggestions: [SupportTicketSuggestion] = []
    var suggestionLancee: String?
    var proposal: SupportTicketProposal?
    var decision: SupportTicketDecision?
    var category: String
    var categoryBy: String
    var resolved: Double?
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
        suggestions = (d["suggestions"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
            return SupportTicketSuggestion(id: id, title: title)
        }
        suggestionLancee = d["suggestion_lancee"] as? String
        if let proposal = d["proposal"] as? [String: Any] {
            self.proposal = SupportTicketProposal(title: proposal["title"] as? String ?? "",
                                                  steps: proposal["steps"] as? [String] ?? [],
                                                  warning: proposal["warning"] as? String ?? "")
        }
        if let decision = d["decision"] as? [String: Any] {
            self.decision = SupportTicketDecision(kind: decision["kind"] as? String ?? "",
                                                  by: decision["by"] as? String ?? "",
                                                  steps: decision["steps"] as? [String] ?? [],
                                                  slots: (decision["slots"] as? [NSNumber] ?? []).map(\.doubleValue),
                                                  rdv: (decision["rdv"] as? NSNumber)?.doubleValue
                                                    ?? (d["rdv"] as? NSNumber)?.doubleValue,
                                                  other: decision["other"] as? Bool ?? false)
        }
        category = d["category"] as? String ?? "autre"
        categoryBy = d["category_by"] as? String ?? ""
        resolved = (d["resolved"] as? NSNumber)?.doubleValue
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
    @State private var stats: TicketStats?
    @State private var focus: String?        // catégorie choisie dans les statistiques
    @State private var highlight: String?    // ticket ouvert depuis un exemple
    @State private var suggestion: TicketStats.Suggestion?
    @State private var applying: AutomateLibrary.Entry?
    @State private var refineTarget: SupportTicket?
    @State private var refineText = ""
    @State private var liveTicket: String?
    @State private var liveSlots: [Date] = [Date().addingTimeInterval(3600)]

    private var shown: [SupportTicket] {
        (filter == 0 ? tickets.filter(\.isOpen) : tickets).filter { focus == nil || $0.category == focus }
    }

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
                ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if let stats {
                            TicketWeekCard(week: stats.thisWeek, suggest: { suggestion = $0 })
                        }
                        if let stats, stats.count > 0 {
                            TicketStatsPanel(stats: stats, focus: $focus,
                                             openExample: { ex in
                                                 filter = 1; focus = nil; highlight = ex.id
                                                 // La liste « Tous » doit être affichée avant de défiler.
                                                 Task { @MainActor in
                                                     try? await Task.sleep(nanoseconds: 150_000_000)
                                                     withAnimation { proxy.scrollTo(ex.id, anchor: .center) }
                                                 }
                                             },
                                             suggest: { suggestion = $0 })
                        }
                        if model.people.isEmpty {
                            empty("Aucun utilisateur relié. Reliez un ordinateur depuis l’onglet Utilisateurs.")
                        } else if shown.isEmpty && !loading {
                            empty(filter == 0 ? "Rien à traiter. Les nouvelles demandes de vos utilisateurs arriveront ici."
                                              : "Aucun ticket pour l’instant.")
                        }
                        ForEach(shown) { t in row(t).id(t.id) }
                    }
                    .padding(.bottom, 8)
                }
                }
            }
        }
        .sheet(item: $suggestion) { sug in
            SupportCreateAutomate(model: model, prefill: sug.draft) { pack in
                suggestion = nil
                if let pack, let d = try? JSONSerialization.data(withJSONObject: pack),
                   let e = AutomateLibrary.shared.add(pack: d) {
                    model.showToast("« \(e.title) » ajouté à vos automates")
                    applying = e
                }
            }
        }
        .sheet(item: $applying) { e in
            ApplyAutomateSheet(model: model, entry: e) { applying = nil }
        }
        .alert("Préciser le plan", isPresented: Binding(
            get: { refineTarget != nil },
            set: { if !$0 { refineTarget = nil } }
        )) {
            TextField("Que faut-il préciser à Holo ?", text: $refineText)
            Button("Annuler", role: .cancel) { refineTarget = nil }
            Button("Envoyer") {
                guard let t = refineTarget else { return }
                let text = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
                refineTarget = nil
                if !text.isEmpty { Task { await act(t, "refine", ["text": text]) } }
            }
        } message: {
            Text("Holo proposera un nouveau plan à partir de cette précision.")
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
                    Pastille(texte: TicketCategory.label(t.category) + (t.categoryBy == "doute" ? " ?" : ""),
                             icone: "tag.fill", ton: t.categoryBy == "doute" ? .gris : .bleu, taille: 12)
                        .help(t.categoryBy == "support" ? "Catégorie corrigée par le support"
                              : t.categoryBy == "holo" ? "Catégorie choisie par Holo"
                              : t.categoryBy == "doute" ? "Catégorie à vérifier" : "Catégorie choisie par les règles")
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
                ForEach(t.suggestions) { suggestion in
                    Text("Automate proposé : \(suggestion.title) · \(t.suggestionLancee == suggestion.id ? "lancé" : "pas lancé")")
                        .font(rounded(14)).foregroundStyle(T.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let proposal = t.proposal {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(proposal.title.isEmpty ? "Plan proposé par Holo" : proposal.title)
                            .font(rounded(15, .semibold))
                        ForEach(Array(proposal.steps.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)").font(rounded(14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !proposal.warning.isEmpty {
                            Label(proposal.warning, systemImage: "exclamationmark.triangle")
                                .font(rounded(14, .semibold)).foregroundStyle(T.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).champ(T.r)
                }
                if let decision = t.decision {
                    VStack(alignment: .leading, spacing: 6) {
                        if decision.kind == "plan" {
                            Text("Plan validé par \(decision.by.isEmpty ? "le support" : decision.by)")
                                .font(rounded(14, .semibold))
                            ForEach(Array(decision.steps.enumerated()), id: \.offset) { i, step in
                                Text("\(i + 1). \(step)").font(rounded(14))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else if decision.kind == "live" {
                            Text("Assistance en direct obligatoire").font(rounded(14, .semibold))
                            if let rdv = decision.rdv {
                                Text("Rendez-vous choisi : \(slotText(rdv))")
                            } else if decision.other {
                                Text("Aucun créneau ne convient.")
                            } else {
                                Text("Créneaux proposés :")
                                ForEach(Array(decision.slots.enumerated()), id: \.offset) { _, at in
                                    Text(slotText(at))
                                }
                            }
                        }
                    }
                    .font(rounded(14)).padding(10).frame(maxWidth: .infinity, alignment: .leading).champ(T.r)
                }
                Text(when(t)).font(rounded(13)).foregroundStyle(T.muted)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if t.isOpen && t.status != "en_cours" {
                    Button(busy == t.id ? "…" : "Prendre en charge") { Task { await act(t, "take") } }
                        .buttonStyle(PillStyle(height: 40)).disabled(busy != nil)
                    if let proposal = t.proposal {
                        if !proposal.steps.isEmpty {
                            Button("Valider") { Task { await act(t, "validate") } }
                                .buttonStyle(PillStyle(height: 40)).disabled(busy != nil)
                        }
                        Button("Préciser") {
                            refineTarget = t
                            refineText = ""
                        }
                        .buttonStyle(PillStyle(filled: false, height: 36)).disabled(busy != nil)
                    } else if t.proposal == nil {
                        Button("Proposer un plan") { Task { await act(t, "draft") } }
                            .buttonStyle(PillStyle(filled: false, height: 36)).disabled(busy != nil)
                    }
                    Button("Assistance en direct obligatoire") {
                        liveTicket = liveTicket == t.id ? nil : t.id
                        liveSlots = [Date().addingTimeInterval(3600)]
                    }
                    .buttonStyle(PillStyle(filled: false, height: 36)).disabled(busy != nil)
                    if liveTicket == t.id {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(liveSlots.indices, id: \.self) { i in
                                HStack {
                                    DatePicker("Créneau \(i + 1)", selection: slotBinding(i),
                                               in: Date().addingTimeInterval(60)...Date().addingTimeInterval(30 * 86400))
                                        .datePickerStyle(.compact)
                                    if liveSlots.count > 1 {
                                        Button("Retirer") { liveSlots.remove(at: i) }
                                            .buttonStyle(.plain).disabled(busy != nil)
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                if liveSlots.count < 3 {
                                    Button("Ajouter un créneau") {
                                        liveSlots.append(Date().addingTimeInterval(3600))
                                    }
                                    .buttonStyle(.plain).disabled(busy != nil)
                                }
                                Button("Proposer") {
                                    let slots = liveSlots.map { Int($0.timeIntervalSince1970) }
                                    Task { await act(t, "live", ["slots": slots]) }
                                    liveTicket = nil
                                }
                                .buttonStyle(PillStyle(height: 36)).disabled(busy != nil)
                            }
                        }
                    }
                }
                Button("Voir l’utilisateur") { openUser(t.person) }
                    .buttonStyle(PillStyle(filled: false, height: 36))
                Menu("Catégorie") {
                    ForEach(TicketCategory.all, id: \.id) { c in
                        Button(c.label + (c.id == t.category ? " ✓" : "")) {
                            Task { await act(t, "category", ["category": c.id]) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().font(rounded(13, .semibold)).disabled(busy != nil)
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
        .overlay(RoundedRectangle(cornerRadius: T.r).stroke(T.accent, lineWidth: highlight == t.id ? 3 : 0))
    }

    private func status(_ t: SupportTicket) -> some View {
        let (txt, ton): (String, Pastille.Ton) = switch t.status {
        case "nouveau": ("Nouveau", .bleu)
        case "en_attente": ("En attente", .orange)
        case "rdv": ("Rendez-vous", .violet)
        case "en_cours": ("En cours", .vert)
        case "a_reprendre": ("À reprendre", .orange)
        case "plan_valide": ("Plan validé", .vert)
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

    private func slotBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { liveSlots.indices.contains(index) ? liveSlots[index] : Date().addingTimeInterval(3600) },
            set: { if liveSlots.indices.contains(index) { liveSlots[index] = $0 } }
        )
    }

    private func slotText(_ at: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM 'à' HH:mm"
        return f.string(from: Date(timeIntervalSince1970: at))
    }

    // MARK: Réseau

    private func load() async {
        let people = model.people
        guard !people.isEmpty else { tickets = []; stats = nil; return }
        loading = true; defer { loading = false }
        var all: [SupportTicket] = []
        var errs: [String] = []
        var parts: [TicketStats] = []
        await withTaskGroup(of: TicketStats?.self) { g in
            for p in people {
                let base = AutomateLibrary.base(p)
                g.addTask {
                    guard let url = URL(string: base + "/tickets/stats"),
                          let (d, r) = try? await URLSession.shared.data(from: url),
                          (r as? HTTPURLResponse)?.statusCode == 200,
                          let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                    else { return nil }
                    return TicketStats(obj, personKey: p.key)
                }
            }
            for await s in g { if let s { parts.append(s) } }
        }
        await withTaskGroup(of: ([SupportTicket], String?).self) { g in
            for p in people {
                let base = AutomateLibrary.base(p)
                g.addTask {
                    guard let url = URL(string: base + "/tickets"),
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
        stats = parts.isEmpty ? nil : TicketStats.merge(parts)
    }

    private func act(_ t: SupportTicket, _ action: String, _ extra: [String: Any] = [:]) async {
        guard let url = URL(string: AutomateLibrary.base(t.person) + "/tickets/" + t.tid) else { return }
        busy = t.id; defer { busy = nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: extra.merging(["action": action, "by": model.helperName ?? "Support"]) { a, _ in a })
        if let (d, r) = try? await URLSession.shared.data(for: req) {
            if (r as? HTTPURLResponse)?.statusCode != 200 {
                let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                model.showToast(obj?["error"] as? String ?? "Action refusée")
            } else if action == "category" {
                model.showToast("Catégorie : \(TicketCategory.label(extra["category"] ?? ""))")
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

/// Carte « Cette semaine » en tête de l'accueil support : demandes reçues,
/// réglées, part réglée par un automate, temps moyen, catégories en tête,
/// automate le plus utile et suggestion d'automate. Rien n'est envoyé par mail.
struct TicketWeekCard: View {
    let week: TicketStats.WeekSummary
    var suggest: (TicketStats.Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cette semaine").font(rounded(20, .bold))
            if week.isEmpty {
                Text("Aucune demande ces 7 derniers jours.").font(rounded(15)).foregroundStyle(T.muted)
            } else {
                HStack(spacing: 10) {
                    kpi("\(week.count)", "demandes reçues")
                    kpi("\(week.resolved)", "réglées")
                    kpi("\(Int((week.automateShare * 100).rounded())) %", "réglées par un automate")
                    kpi(TicketStatsPanel.duration(week.meanResolution), "temps moyen")
                }
                if !week.top.isEmpty {
                    line("En tête", week.top.map { "\($0.label) (\($0.count))" }.joined(separator: ", "))
                }
                line("Automate le plus utile", week.automate.map {
                    "« \($0.title) », \($0.count) demande\($0.count > 1 ? "s" : "") réglée\($0.count > 1 ? "s" : "")"
                } ?? "aucun cette semaine")
            }
            if let s = week.suggestion {
                HStack(spacing: 12) {
                    Label(s.text, systemImage: "sparkles").font(rounded(16, .semibold))
                    Spacer(minLength: 0)
                    if SupportAutomates.creationActive {
                        Button("Créer l’automate") { suggest(s) }.buttonStyle(PillStyle(height: 38))
                    }
                }
                .padding(12).background(T.mint, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).carte()
        .accessibilityElement(children: .contain)
    }

    private func kpi(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(rounded(22, .bold)).monospacedDigit()
            Text(l).font(rounded(12)).foregroundStyle(T.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ value: String) -> some View {
        (Text(title + " : ").font(rounded(15, .semibold)) + Text(value).font(rounded(15)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Statistiques en tête de l'onglet Tickets : chiffres clés, suggestion
/// d'automate, tickets par semaine et catégories, avec des demandes réelles.
struct TicketStatsPanel: View {
    let stats: TicketStats
    @Binding var focus: String?
    var openExample: (TicketStats.Example) -> Void
    var suggest: (TicketStats.Suggestion) -> Void

    static func duration(_ s: Double?) -> String {
        guard let s else { return "—" }
        if s < 3600 { return "\(max(1, Int((s / 60).rounded()))) min" }
        if s < 86400 { return String(format: "%.1f h", s / 3600).replacingOccurrences(of: ".", with: ",") }
        return String(format: "%.1f j", s / 86400).replacingOccurrences(of: ".", with: ",")
    }

    private static func day(_ iso: String) -> String {
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"; p.timeZone = TimeZone(identifier: "UTC")
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM"; f.timeZone = p.timeZone
        return p.date(from: iso).map { f.string(from: $0) } ?? iso
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                kpi("\(stats.count)", "tickets depuis le \(Self.day(stats.since))")
                kpi("\(stats.resolved)", "résolus")
                kpi(Self.duration(stats.medianResolution), "temps de résolution (médian)")
                kpi("\(Int((stats.automateShare * 100).rounded())) %", "réglés par un automate")
            }
            ForEach(stats.panelSuggestions) { s in
                HStack(spacing: 12) {
                    Label(s.text, systemImage: "sparkles").font(rounded(16, .semibold))
                    Spacer(minLength: 0)
                    if SupportAutomates.creationActive {
                        Button("Créer l’automate") { suggest(s) }.buttonStyle(PillStyle(height: 38))
                    }
                }
                .padding(12).background(T.mint, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Par semaine" + (focus.map { " · " + TicketCategory.label($0) } ?? ""))
                .font(rounded(14, .semibold)).foregroundStyle(T.muted)
            weeks
            Text("Catégories qui reviennent le plus").font(rounded(14, .semibold)).foregroundStyle(T.muted)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(stats.categories) { c in category(c) }
            }
        }
        .padding(16).carte()
    }

    private func kpi(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(rounded(22, .bold)).monospacedDigit()
            Text(l).font(rounded(12)).foregroundStyle(T.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
    }

    private var weeks: some View {
        let top = max(1, stats.weeks.map(\.total).max() ?? 1)
        let h: CGFloat = 96
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(stats.weeks) { w in
                let part = focus.map { w.by[$0] ?? 0 } ?? w.total
                VStack(spacing: 4) {
                    Text(w.total == 0 ? " " : focus == nil ? "\(w.total)" : "\(part)/\(w.total)")
                        .font(rounded(11, .semibold)).monospacedDigit()
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6).fill(T.field).frame(height: h)
                        RoundedRectangle(cornerRadius: 6).fill(focus == nil ? T.accent : T.mint)
                            .frame(height: h * CGFloat(w.total) / CGFloat(top))
                        if focus != nil {
                            RoundedRectangle(cornerRadius: 6).fill(T.accent).frame(height: h * CGFloat(part) / CGFloat(top))
                        }
                    }
                    Text(Self.day(w.start)).font(rounded(11)).foregroundStyle(T.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Semaine du \(Self.day(w.start)) : \(focus == nil ? w.total : part) tickets")
            }
        }
    }

    private func category(_ c: TicketStats.Category) -> some View {
        let top = max(1, stats.categories.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation { focus = focus == c.id ? nil : c.id } } label: {
                HStack(spacing: 10) {
                    Text(c.label).font(rounded(15, .medium)).frame(width: 190, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(T.field)
                            Capsule().fill(T.accent).opacity(focus == nil || focus == c.id ? 1 : 0.35)
                                .frame(width: g.size.width * CGFloat(c.count) / CGFloat(top))
                        }
                    }
                    .frame(height: 12)
                    Text("\(c.count)").font(rounded(15, .semibold)).monospacedDigit().frame(minWidth: 24, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(c.count) tickets, \(c.resolved) résolus, \(c.byAutomate) par un automate, médiane \(Self.duration(c.medianResolution))")
            if focus == nil || focus == c.id, !c.examples.isEmpty {
                HStack(spacing: 6) {
                    ForEach(c.examples) { e in
                        Button { openExample(e) } label: {
                            Text("« \(e.task) »").font(rounded(13)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(T.field, in: Capsule())
                        }
                        .buttonStyle(.plain).help(e.label)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
