import SwiftUI
import UniformTypeIdentifiers

/// Accueil du support sur iPhone, aligné sur le support Mac (`SupportRoot`) :
/// trois onglets « Tickets », « Utilisateurs » et « Mes automates ». Les données
/// (tickets, bibliothèque d'automates) sont partagées avec le Mac (`SupportData.swift`).
struct SupportHome: View {
    @Bindable var model: HelperModel
    /// 0 Tickets, 1 Utilisateurs, 2 Mes automates. Retenu entre deux assistances.
    @AppStorage("supportTab") private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            SoinTabs(options: [("Tickets", 0), ("Utilisateurs", 1), ("Mes automates", 2)], selection: $tab)
                .padding(.horizontal, 20).padding(.bottom, 12)
            switch tab {
            case 0: TicketsTab(model: model) { p in model.switchTo(p); tab = 1 }
            case 2: AutomatesTab(model: model)
            default:
                PeopleRow(model: model)
                IdleView(model: model)
            }
        }
        // Une assistance qui démarre remplace l'accueil ; au retour, on est sur l'utilisateur, comme sur Mac.
        .onDisappear { if model.screen != .idle { tab = 1 } }
    }
}

/// Onglets soulignés, comme `Onglets` sur Mac, avec des zones d'au moins 44 pt.
struct SoinTabs<V: Hashable>: View {
    var options: [(label: String, value: V)]
    @Binding var selection: V

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    VStack(spacing: 0) {
                        Text(o.label).font(.subheadline.weight(on ? .semibold : .medium))
                            .foregroundStyle(on ? T.leaf : T.muted)
                            .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        Rectangle().fill(on ? T.accent : T.line).frame(height: on ? 3 : 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

/// Bouton en pilule compact (≥ 44 pt), pour les actions d'une carte.
private struct SmallPill: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.white : T.leaf)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                if filled { Capsule().fill(T.primary) } else {
                    Capsule().fill(T.card).overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

/// Action secondaire discrète (« Clore », « Rouvrir »), comme sur Mac, en gardant 44 pt.
private struct TextAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold)).foregroundStyle(T.muted)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Tickets

/// Onglet « Tickets » : tous les tickets de tous les utilisateurs reliés.
struct TicketsTab: View {
    let model: HelperModel
    var openUser: (Person) -> Void
    @State private var board = TicketBoard()
    @State private var filter = 0   // 0 ouverts, 1 tous

    private var shown: [SupportTicket] { filter == 0 ? board.tickets.filter(\.isOpen) : board.tickets }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    let open = board.openCount
                    Text(open == 0 ? "Aucune demande en attente." :
                         "\(open) demande\(open > 1 ? "s" : "") ouverte\(open > 1 ? "s" : "") chez vos utilisateurs.")
                        .font(.subheadline.weight(.medium)).foregroundStyle(T.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if board.loading { ProgressView().controlSize(.small) }
                }
                SoinTabs(options: [("Ouverts", 0), ("Tous", 1)], selection: $filter).frame(maxWidth: 260)
                ForEach(board.errors, id: \.self) { e in
                    Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(T.danger)
                }
                if model.people.isEmpty {
                    empty("Aucun utilisateur relié. Reliez un ordinateur depuis l’onglet Utilisateurs.")
                } else if shown.isEmpty && !board.loading {
                    empty(filter == 0 ? "Rien à traiter. Les nouvelles demandes de vos utilisateurs arriveront ici."
                                      : "Aucun ticket pour l’instant.")
                }
                ForEach(shown) { t in row(t) }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .refreshable { await board.load(model.people) }
        .task(id: model.people.map(\.key)) {
            while !Task.isCancelled {
                await board.load(model.people)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.callout).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }

    private func row(_ t: SupportTicket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { header(t) }
                VStack(alignment: .leading, spacing: 6) { header(t) }
            }
            Text(t.task.isEmpty ? "Demande sans texte" : "« \(t.task) »")
                .font(.headline).foregroundStyle(T.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.quand)
                if !t.assignee.isEmpty { Text("Pris par \(t.assignee)") }
            }
            .font(.footnote).foregroundStyle(T.muted)
            FlowLayout(spacing: 8) {
                if t.canTake {
                    Button(board.busy == t.id ? "Envoi…" : "Prendre en charge") { Task { await act(t, "take") } }
                        .buttonStyle(SmallPill()).disabled(board.busy != nil)
                }
                Button("Voir l’utilisateur") { openUser(t.person) }.buttonStyle(SmallPill(filled: false))
                if t.canTake {
                    Button("Clore") { Task { await act(t, "close") } }
                        .buttonStyle(TextAction()).disabled(board.busy != nil)
                } else if !t.isOpen {
                    Button("Rouvrir") { Task { await act(t, "reopen") } }
                        .buttonStyle(TextAction()).disabled(board.busy != nil)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard(radius: T.r)
    }

    @ViewBuilder private func header(_ t: SupportTicket) -> some View {
        Text(t.label).font(.footnote.weight(.semibold)).foregroundStyle(T.muted).monospacedDigit()
        StatusPill(text: t.statut.texte, tone: tone(t.statut.ton), icon: "circle.fill")
        Text(t.personName).font(.footnote.weight(.semibold)).foregroundStyle(T.ink)
    }

    private func tone(_ t: TonPastille) -> StatusPill.Tone {
        switch t {
        case .bleu: .blue
        case .violet: .violet
        case .vert: .green
        case .orange: .orange
        case .gris: .gray
        }
    }

    private func act(_ t: SupportTicket, _ action: String) async {
        if let e = await board.act(t, action, by: model.helperName ?? "Support", people: model.people) {
            model.showToast(e)
        } else if action == "take" {
            model.showToast("Demande proposée à \(t.person.name.isEmpty ? "l’utilisateur" : t.person.name)")
            openUser(t.person)
        }
    }
}

// MARK: - Mes automates

/// Onglet « Mes automates » : la bibliothèque du support, partagée avec le Mac
/// (`AutomateLibrary`). Comme sur Mac, la création reste masquée : liste,
/// import d'un `.papai` et « Appliquer… » à un ou plusieurs utilisateurs.
struct AutomatesTab: View {
    let model: HelperModel
    @State private var lib = AutomateLibrary.shared
    @State private var importing = false
    @State private var applying: AutomateLibrary.Entry?
    @State private var toDelete: AutomateLibrary.Entry?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Votre bibliothèque. Choisissez ensuite à qui appliquer chaque automate.")
                    .font(.subheadline.weight(.medium)).foregroundStyle(T.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("\(lib.entries.count) automate\(lib.entries.count > 1 ? "s" : "")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(T.muted)
                    Spacer()
                    Button { importing = true } label: { Label("Importer un .papai", systemImage: "square.and.arrow.down") }
                        .buttonStyle(SmallPill(filled: false))
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold))
                        .foregroundStyle(T.danger)
                }
                if lib.entries.isEmpty {
                    Text("Aucun automate. Importez un fichier .papai.")
                        .font(.callout).foregroundStyle(T.muted)
                }
                ForEach(lib.entries) { e in row(e) }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .sheet(item: $applying) { e in
            ApplyAutomateSheet(model: model, entry: e) { applying = nil }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(filenameExtension: "papai") ?? .json]) { r in
            guard case .success(let url) = r else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), let e = lib.add(pack: d) {
                error = nil; model.showToast("« \(e.title) » ajouté à vos automates")
            } else {
                error = "Ce fichier n’est pas un automate .papai."
            }
        }
        .confirmationDialog("Supprimer cet automate de votre bibliothèque ?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer « \(toDelete?.title ?? "") »", role: .destructive) { if let e = toDelete { lib.remove(e) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les utilisateurs chez qui il est déjà appliqué le gardent.")
        }
    }

    private func row(_ e: AutomateLibrary.Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Self.symbol(e.firstAction)).font(.body.weight(.semibold)).foregroundStyle(T.accent)
                    .frame(width: 44, height: 44).background(Circle().fill(T.mint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title).font(.headline).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
                    if !e.detail.isEmpty {
                        Text(e.detail).font(.subheadline).foregroundStyle(T.muted).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            FlowLayout(spacing: 6) {
                if e.stepCount > 0 { tag("\(e.stepCount) étape\(e.stepCount > 1 ? "s" : "")") }
                if !e.platforms.isEmpty { tag(e.platforms.map { $0 == "mac" ? "Mac" : "Windows" }.joined(separator: " · ")) }
                if !e.publisher.isEmpty { tag(e.publisher) }
            }
            let names = model.people.filter { e.applied.contains($0.key) }.map { $0.name.isEmpty ? "Utilisateur" : $0.name }
            Text(names.isEmpty ? "Appliqué à personne" : "Appliqué à : " + names.joined(separator: ", "))
                .font(.footnote.weight(.semibold)).foregroundStyle(names.isEmpty ? T.muted : T.leaf)
            HStack(spacing: 8) {
                Button("Appliquer…") { applying = e }.buttonStyle(SmallPill())
                Spacer()
                Button { toDelete = e } label: {
                    Image(systemName: "trash").font(.body.weight(.semibold)).foregroundStyle(T.muted)
                        .frame(width: 44, height: 44).background(Circle().fill(T.field))
                }
                .buttonStyle(.plain).accessibilityLabel("Supprimer \(e.title)")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).soinCard(radius: T.r)
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(T.muted)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(T.field))
    }

    static func symbol(_ action: String) -> String {
        switch action {
        case "open_folder": "folder.fill"
        case "open_settings": "gearshape.fill"
        case "open_url": "globe"
        case "install_templates": "doc.richtext.fill"
        case "antivirus_scan": "shield.lefthalf.filled"
        case "holo": "sparkles"
        default: "checkmark.circle.fill"
        }
    }
}

/// Choisir les utilisateurs chez qui appliquer un automate (même logique que sur Mac).
struct ApplyAutomateSheet: View {
    let model: HelperModel
    let entry: AutomateLibrary.Entry
    var close: () -> Void
    @State private var chosen: Set<String> = []
    @State private var sending = false
    @State private var results: [String: String] = [:]   // clé -> erreur ("" = réussi)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Appliquer « \(entry.title) »").font(.title2.bold()).foregroundStyle(T.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Les utilisateurs cochés pourront le relancer d’un clic. Vous pouvez aussi ne l’appliquer à personne pour l’instant.")
                        .font(.subheadline).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    if model.people.isEmpty {
                        Text("Aucun utilisateur relié à ce téléphone.").font(.callout).foregroundStyle(T.muted)
                    }
                    ForEach(model.people) { p in person(p) }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(sending ? "Envoi…" : "Appliquer") { Task { await apply() } }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(chosen.isEmpty || sending)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(T.bg)
            }
            .background(T.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(results.isEmpty ? "Plus tard" : "Fermer") { close() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func person(_ p: Person) -> some View {
        let already = entry.applied.contains(p.key)
        let on = chosen.contains(p.key) || already
        let name = p.name.isEmpty ? "Utilisateur" : p.name
        return Button {
            if chosen.contains(p.key) { chosen.remove(p.key) } else { chosen.insert(p.key) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(on ? T.accent : T.muted)
                    .accessibilityHidden(true)
                Text(name).font(.body.weight(.semibold)).foregroundStyle(T.ink)
                Spacer(minLength: 8)
                if already {
                    Text("déjà appliqué").font(.footnote).foregroundStyle(T.leaf)
                } else if let r = results[p.key] {
                    Text(r.isEmpty ? "Appliqué" : r).font(.footnote.weight(.semibold))
                        .foregroundStyle(r.isEmpty ? T.leaf : T.danger)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .soinField()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(already || sending)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func apply() async {
        sending = true; defer { sending = false }
        let r = await AutomateLibrary.shared.apply(entry, to: model.people.filter { chosen.contains($0.key) })
        results.merge(r) { _, n in n }
        let ok = r.filter { $0.value.isEmpty }.map(\.key)
        chosen.subtract(ok)
        if !ok.isEmpty { await model.loadLessons() }
    }
}
