import SwiftUI

/// Premier onglet de l'accueil support : tous les tickets formulés par tous
/// les utilisateurs reliés à ce poste, les plus récents d'abord.
struct SupportTickets: View {
    let model: HelperModel
    /// Clé d'un utilisateur : n'afficher que ses tickets (onglet Utilisateurs).
    var only: String? = nil
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
    @State private var editing: SupportTicket?
    @State private var closing: SupportTicket?

    private var shown: [SupportTicket] {
        (filter == 0 ? tickets.filter(\.isOpen) : tickets)
            .filter { (focus == nil || $0.category == focus) && (only == nil || $0.person.key == only) }
    }

    @State private var showStats = false

    var body: some View {
        // Une seule barre (filtre, compteurs, actualiser), puis la liste. Le titre est déjà
        // l'onglet « Tickets » : pas d'en-tête bleu en double. Les statistiques restent repliées.
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                let open = tickets.filter(\.isOpen).count
                Picker("Afficher", selection: $filter) {
                    Text("Ouverts (\(open))").tag(0)
                    Text("Tous (\(tickets.count))").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if focus != nil {
                    Button { focus = nil } label: {
                        Label(TicketCategory.label(focus ?? ""), systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).font(rounded(14, .semibold)).foregroundStyle(T.accent)
                    .help("Retirer le filtre de catégorie")
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                if let stats, stats.count > 0 {
                    Button { withAnimation(.easeOut(duration: 0.2)) { showStats.toggle() } } label: {
                        Label("Statistiques", systemImage: showStats ? "chart.bar.fill" : "chart.bar")
                    }
                    .buttonStyle(.plain).font(rounded(14, .semibold)).foregroundStyle(showStats ? T.accent : T.muted)
                }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.muted)
                    .help("Actualiser")
            }
            ForEach(errors, id: \.self) { e in
                Label(e, systemImage: "exclamationmark.triangle").font(rounded(14)).foregroundStyle(T.danger)
            }
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if showStats, let stats, stats.count > 0 {
                        TicketWeekCard(week: stats.thisWeek, suggest: { suggestion = $0 })
                        TicketStatsPanel(stats: stats, focus: $focus,
                                         openExample: { ex in
                                             filter = 1; focus = nil; highlight = ex.id
                                             Task { @MainActor in
                                                 try? await Task.sleep(nanoseconds: 150_000_000)
                                                 withAnimation { proxy.scrollTo(ex.id, anchor: .center) }
                                             }
                                         },
                                         suggest: { suggestion = $0 })
                    }
                    if model.people.isEmpty {
                        empty("Aucun utilisateur relié pour l’instant.")
                    } else if shown.isEmpty && !loading {
                        empty(filter == 0 ? "Rien à traiter. Les demandes de vos utilisateurs arriveront ici."
                                          : "Aucun ticket pour l’instant.")
                    }
                    ForEach(shown) { t in row(t).id(t.id) }
                }
                .padding(.bottom, 8)
            }
            }
        }
        .padding(.top, 4)
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
        .sheet(item: $editing) { t in
            EditPlanSheet(titre: t.plan?.titre ?? "", etapes: t.plan?.etapes ?? []) { titre, etapes in
                editing = nil
                guard let titre else { return }
                Task { await validateEdited(t, titre: titre, etapes: etapes) }
            }
        }
        .sheet(item: $closing) { t in
            SolutionSheet { texte in
                closing = nil
                guard let texte else { return }
                Task { await act(t, "close", ["text": texte]) }
            }
        }
        .sheet(item: $applying) { e in
            ApplyAutomateSheet(model: model, entry: e) { applying = nil }
        }
        .onAppear { if only != nil { filter = 1 } }   // historique complet, résolus compris
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
                    Text(t.person.name.isEmpty ? "Utilisateur" : t.person.name).font(rounded(15, .semibold))
                    status(t)
                    Text("\(t.label) · \(TicketCategory.label(t.category))\(t.categoryBy == "doute" ? " ?" : "")")
                        .font(rounded(13)).foregroundStyle(T.muted).monospacedDigit()
                        .help(t.categoryBy == "support" ? "Catégorie corrigée par le support"
                              : t.categoryBy == "holo" ? "Catégorie choisie par Holo"
                              : t.categoryBy == "doute" ? "Catégorie à vérifier" : "Catégorie choisie par les règles")
                    if !t.assignee.isEmpty {
                        Text("· pris par \(t.assignee)").font(rounded(13)).foregroundStyle(T.muted)
                    }
                }
                Text(t.task.isEmpty ? "Demande sans texte" : "« \(t.task) »").font(rounded(18, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let p = t.plan {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Automate proposé : \(p.titre)", systemImage: "wand.and.stars")
                            .font(rounded(15, .semibold)).foregroundStyle(T.accent)
                        ForEach(Array(p.etapes.enumerated()), id: \.offset) { i, s in
                            Text("\(i + 1). \(s)").font(rounded(14)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.field))
                }
                if let l = t.linkup {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Recherche Linkup", systemImage: "magnifyingglass")
                            .font(rounded(14, .semibold)).foregroundStyle(T.accent)
                        Text(l.resume).font(rounded(14)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(l.sources.prefix(3).enumerated()), id: \.offset) { _, src in
                            if let u = URL(string: src.url) {
                                Link(src.nom, destination: u).font(rounded(13)).lineLimit(1)
                            }
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.field))
                }
                if !t.isOpen && !t.solution.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Solution", systemImage: "checkmark.seal.fill")
                            .font(rounded(14, .semibold)).foregroundStyle(Pastille.Ton.vert.texte)
                        Text(t.solution).font(rounded(14)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.field))
                }
                if let b = t.blocked {
                    Label(b, systemImage: "exclamationmark.circle").font(rounded(14, .medium))
                        .foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(t.suggestions) { suggestion in
                    Text("Automate proposé : \(suggestion.title) · \(t.suggestionLancee == suggestion.id ? "lancé" : "pas lancé")")
                        .font(rounded(14)).foregroundStyle(T.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(when(t)).font(rounded(13)).foregroundStyle(T.muted)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if t.isOpen && t.plan != nil {
                    Button(busy == t.id ? "…" : "Valider") { Task { await act(t, "validate") } }
                        .buttonStyle(PillStyle(height: 40)).disabled(busy != nil)
                        .help("Crée l’automate chez l’utilisateur")
                    Button("Modifier") { editing = t }
                        .buttonStyle(PillStyle(filled: false, height: 36)).disabled(busy != nil)
                        .help("Corriger le plan proposé par Holo avant de le valider")
                    Button(busy == t.id ? "…" : "Chercher avec Linkup") { Task { await act(t, "linkup") } }
                        .buttonStyle(.plain).font(rounded(13, .semibold)).foregroundStyle(T.accent)
                        .disabled(busy != nil)
                        .help("Recherche documentaire : Holo refait le plan avec les sources trouvées")
                } else if t.isOpen && t.status != "en_cours" {
                    Button(busy == t.id ? "…" : "Prendre en charge") { Task { await act(t, "take") } }
                        .buttonStyle(PillStyle(height: 40)).disabled(busy != nil)
                }
                // Le reste dans un seul menu, pour garder la carte lisible.
                Menu {
                    Button("Voir l’utilisateur") { openUser(t.person) }
                    Menu("Catégorie") {
                        ForEach(TicketCategory.all, id: \.id) { c in
                            Button(c.label + (c.id == t.category ? " ✓" : "")) {
                                Task { await act(t, "category", ["category": c.id]) }
                            }
                        }
                    }
                    Divider()
                    if t.isOpen && t.status != "en_cours" {
                        Button("Clore le ticket…") { closing = t }
                    } else if !t.isOpen {
                        Button("Rouvrir le ticket") { Task { await act(t, "reopen") } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 20, weight: .medium)).foregroundStyle(T.muted)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy != nil)
                .help("Plus d’actions")
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

    /// Valide le plan corrigé par le support : l'automate est créé avec ces étapes.
    private func validateEdited(_ t: SupportTicket, titre: String, etapes: [String]) async {
        guard let url = URL(string: AutomateLibrary.base(t.person) + "/tickets/" + t.tid) else { return }
        busy = t.id; defer { busy = nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "action": "validate", "by": model.helperName ?? "Support",
            "automate": ["title": titre, "steps": etapes],
        ])
        if let (d, r) = try? await URLSession.shared.data(for: req) {
            if (r as? HTTPURLResponse)?.statusCode == 200 {
                model.showToast("Automate créé chez \(t.person.name.isEmpty ? "l’utilisateur" : t.person.name)")
            } else {
                let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                model.showToast(obj?["error"] as? String ?? "Action refusée")
            }
        } else {
            model.showToast("Serveur injoignable")
        }
        await load()
    }

    private func act(_ t: SupportTicket, _ action: String, _ extra: [String: String] = [:]) async {
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
            } else if action == "validate" {
                model.showToast("Automate créé chez \(t.person.name.isEmpty ? "l’utilisateur" : t.person.name)")
            } else if action == "linkup" {
                model.showToast("Plan mis à jour avec Linkup")
            } else if action == "close" {
                model.showToast("Ticket résolu, solution enregistrée")
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
                    if TicketStatsPanel.canCreate {
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

    /// Masqué tant que la suggestion compte toutes les demandes d'une catégorie
    /// au lieu des tickets réglés sur un même sujet (voir TODO.md).
    static let canCreate = false

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
                    if Self.canCreate {
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


/// Le support corrige le plan proposé par Holo : titre et étapes, puis valide.
struct EditPlanSheet: View {
    @State var titre: String
    @State var etapes: [String]
    /// (nil, _) si annulé ; sinon le titre et les étapes non vides.
    var done: (String?, [String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Modifier le plan").font(rounded(26, .bold)).foregroundStyle(.white)
                .padding(24).frame(maxWidth: .infinity, alignment: .leading).background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Titre de l’automate").font(rounded(14, .semibold)).foregroundStyle(T.muted)
                    TextField("Titre", text: $titre).textFieldStyle(.plain).font(rounded(17))
                        .padding(12).champ(T.r)
                    Text("Étapes").font(rounded(14, .semibold)).foregroundStyle(T.muted)
                    ForEach(etapes.indices, id: \.self) { i in
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(rounded(14, .bold)).foregroundStyle(T.accent)
                                .frame(width: 26, height: 26).background(Circle().fill(T.mint))
                            TextField("Étape \(i + 1)", text: $etapes[i], axis: .vertical)
                                .textFieldStyle(.plain).font(rounded(16)).padding(10).champ(T.r)
                            Button { etapes.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(T.muted)
                            }
                            .buttonStyle(.plain).disabled(etapes.count <= 1).help("Retirer cette étape")
                        }
                    }
                    if etapes.count < 6 {
                        Button { etapes.append("") } label: { Label("Ajouter une étape", systemImage: "plus.circle") }
                            .buttonStyle(.plain).font(rounded(15, .semibold)).foregroundStyle(T.accent)
                    }
                }
                .padding(24)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack {
                Spacer()
                Button("Annuler") { done(nil, []) }.buttonStyle(PillStyle(filled: false, height: 44))
                    .keyboardShortcut(.cancelAction)
                Button("Valider le plan") {
                    done(titre.trimmingCharacters(in: .whitespacesAndNewlines),
                         etapes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                }
                .buttonStyle(PillStyle(height: 44, icone: "checkmark.circle"))
                .disabled(titre.trimmingCharacters(in: .whitespaces).isEmpty
                          || etapes.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            }
            .padding(16)
        }
        .foregroundStyle(T.ink).frame(width: 560, height: 560).background(T.bg)
    }
}


/// Clore un ticket : la solution apportée est obligatoire, elle reste dans l'historique.
struct SolutionSheet: View {
    @State private var texte = ""
    var done: (String?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Solution apportée").font(rounded(24, .bold))
            Text("Ce que vous avez fait pour régler la demande. L’utilisateur la retrouve dans « Mes demandes ».")
                .font(rounded(15)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            TextField("Par exemple : imprimante réinstallée, pilote mis à jour.", text: $texte, axis: .vertical)
                .lineLimit(4...8).textFieldStyle(.plain).font(rounded(16)).padding(12).champ(T.r)
            HStack {
                Spacer()
                Button("Annuler") { done(nil) }.buttonStyle(PillStyle(filled: false, height: 44))
                    .keyboardShortcut(.cancelAction)
                Button("Clore le ticket") { done(texte.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(PillStyle(height: 44, icone: "checkmark.circle"))
                    .disabled(texte.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            }
        }
        .padding(24).foregroundStyle(T.ink).frame(width: 520).background(T.bg)
    }
}
