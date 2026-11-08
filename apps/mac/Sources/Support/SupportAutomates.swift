import SwiftUI

/// Un automate tel que le serveur le décrit (`GET /lessons`), vu par le support.
struct SupportAutomate: Decodable, Identifiable {
    struct Step: Decodable { var instruction: String? }
    struct Action: Decodable { var `do`: String? }
    var id: String
    var title: String
    var description: String?
    var publisher: String?
    var platforms: [String]?
    var actions: [Action]?
    var steps: [Step]?
    var source: String?
}

/// Onglet « Automates » du mode support : tous les automates de la personne
/// aidée suivie, et la création d'un nouvel automate (validé par le support
/// en le créant, comme un import `.papai`).
struct SupportAutomates: View {
    let model: HelperModel
    @State private var list: [SupportAutomate] = []
    @State private var loading = false
    @State private var error: String?
    @State private var creating = false
    @State private var toDelete: SupportAutomate?

    var body: some View {
        Panneau {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Automates de \(model.senior)").font(rounded(30, .bold))
                    Text("Ce que \(model.senior) peut relancer d’un clic depuis son ordinateur.")
                        .font(rounded(17, .medium)).opacity(0.92)
                }
                Spacer(minLength: 0)
                Button { creating = true } label: {
                    Label("Créer un automate", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PillStyle(filled: false, height: 50))
            }
        } corps: {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(list.isEmpty ? "" : "\(list.count) automate\(list.count > 1 ? "s" : "")")
                            .font(rounded(16, .semibold)).foregroundStyle(T.muted)
                        Spacer()
                        if loading { ProgressView().controlSize(.small) }
                        Button("Actualiser") { Task { await load() } }
                            .buttonStyle(.plain).font(rounded(14, .semibold)).foregroundStyle(T.leaf)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(rounded(15, .semibold))
                            .foregroundStyle(T.danger)
                    }
                    if list.isEmpty && !loading {
                        Text("Aucun automate pour l’instant. Créez-en un, ou gardez une assistance réussie comme automate.")
                            .font(rounded(16)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(list) { a in row(a) }
                }
                .padding(.bottom, 8)
            }
        }
        .task(id: model.helperKey) { await load() }
        .sheet(isPresented: $creating) {
            SupportCreateAutomate(model: model) { created in
                creating = false
                if let created {
                    model.showToast("Automate « \(created) » créé")
                    Task { await load(); await model.loadLessons() }
                }
            }
        }
        .confirmationDialog("Retirer cet automate ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Retirer « \(toDelete?.title ?? "") »", role: .destructive) {
                if let a = toDelete { Task { await remove(a) } }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("\(model.seniorTitle) ne pourra plus le relancer.")
        }
    }

    private func row(_ a: SupportAutomate) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol(a)).font(.system(size: 18, weight: .semibold)).foregroundStyle(T.accent)
                .frame(width: 44, height: 44).background(Circle().fill(T.mint))
            VStack(alignment: .leading, spacing: 4) {
                Text(a.title).font(rounded(19, .semibold))
                if let d = a.description, !d.isEmpty {
                    Text(d).font(rounded(15)).foregroundStyle(T.muted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    let n = a.steps?.count ?? 0
                    if n > 0 { tag("\(n) étape\(n > 1 ? "s" : "")") }
                    if let p = a.platforms, !p.isEmpty {
                        tag(p.map { $0 == "mac" ? "Mac" : "Windows" }.joined(separator: " · "))
                    }
                    if let pub = a.publisher, !pub.isEmpty { tag(pub) }
                    else if a.source != "import" { tag("Gardé après une assistance") }
                }
            }
            Spacer(minLength: 0)
            Button { toDelete = a } label: {
                Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.muted)
                    .frame(width: 36, height: 36).background(Circle().fill(T.field))
            }
            .buttonStyle(.plain).accessibilityLabel("Retirer \(a.title)")
        }
        .padding(14).carte()
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(rounded(13, .semibold)).foregroundStyle(T.muted)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(T.field))
    }

    private func symbol(_ a: SupportAutomate) -> String {
        switch a.actions?.first?.do {
        case "open_folder": "folder.fill"
        case "open_settings": "gearshape.fill"
        case "open_url": "globe"
        case "install_templates": "doc.richtext.fill"
        case "antivirus_scan": "shield.lefthalf.filled"
        case "holo": "sparkles"
        default: "checkmark.circle.fill"
        }
    }

    private func load() async {
        guard let url = URL(string: model.baseHTTP + "/lessons") else { return }
        loading = true; defer { loading = false }
        do {
            let (d, _) = try await URLSession.shared.data(from: url)
            list = try JSONDecoder().decode([SupportAutomate].self, from: d)
            error = nil
        } catch {
            self.error = "Impossible de charger les automates."
        }
    }

    private func remove(_ a: SupportAutomate) async {
        toDelete = nil
        guard let enc = a.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: model.baseHTTP + "/automations/" + enc) else { return }
        var req = URLRequest(url: url); req.httpMethod = "DELETE"
        if let (_, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 {
            model.showToast("Automate retiré")
        } else {
            error = "Cet automate ne peut pas être retiré d’ici."
        }
        await load()
        await model.loadLessons()
    }
}

/// Création d'un automate : un titre, ce qu'il fait (une action de premier
/// niveau, jamais de commande) et le pas à pas « Montrez-moi ».
struct SupportCreateAutomate: View {
    let model: HelperModel
    var done: (String?) -> Void

    enum Kind: String, CaseIterable { case holo, folder, settings, url }
    @State private var title = ""
    @State private var detail = ""
    @State private var kind: Kind = .holo
    @State private var goal = ""
    @State private var folder = "pictures"
    @State private var subfolder = ""
    @State private var page = "wifi"
    @State private var link = "https://"
    @State private var stepsText = ""
    @State private var mac = true
    @State private var windows = true
    @State private var sending = false
    @State private var error: String?

    private static let kinds: [(String, Kind)] = [("Holo s’en charge", .holo), ("Ouvrir un dossier", .folder),
                                                  ("Page des Réglages", .settings), ("Ouvrir un site", .url)]
    private static let folders: [(String, String)] = [("Images", "pictures"), ("Documents", "documents"),
        ("Téléchargements", "downloads"), ("Bureau", "desktop"), ("Vidéos", "videos"), ("Musique", "music")]
    private static let pages: [(String, String)] = [("Wi-Fi", "wifi"), ("Imprimantes", "printers"),
        ("Mises à jour", "updates"), ("Bluetooth", "bluetooth"), ("Son", "sound"), ("Écran", "display"),
        ("Applications par défaut", "default_apps"), ("Antivirus", "antivirus")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Créer un automate").font(rounded(28, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading).background(T.header)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Titre (un verbe, par exemple « Retrouver mes photos »)", $title, "Se connecter au Wi-Fi")
                    field("Description (facultatif)", $detail, "Ce que fait l’automate, en une phrase")
                    VStack(alignment: .leading, spacing: 8) {
                        label("Ce que fait l’automate")
                        Onglets(options: Self.kinds, selection: $kind)
                    }
                    switch kind {
                    case .holo:
                        field("Objectif donné à Holo", $goal, "Ouvrir le dossier des photos de Noël")
                    case .folder:
                        picker("Dossier", Self.folders, $folder)
                        field("Sous-dossier (facultatif)", $subfolder, "Noël 2025")
                    case .settings:
                        picker("Page", Self.pages, $page)
                    case .url:
                        field("Adresse (https seulement)", $link, "https://")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        label("Pas à pas « Montrez-moi » : une étape par ligne (facultatif)")
                        TextEditor(text: $stepsText).font(rounded(16)).frame(minHeight: 96)
                            .scrollContentBackground(.hidden).padding(10).champ()
                    }
                    HStack(spacing: 18) {
                        label("Pour")
                        Toggle("Mac", isOn: $mac)
                        Toggle("Windows", isOn: $windows)
                    }
                    .toggleStyle(.checkbox).font(rounded(16))
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(rounded(15, .semibold))
                            .foregroundStyle(T.danger).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack {
                Text("En le créant, vous le validez pour \(model.senior).").font(rounded(14)).foregroundStyle(T.muted)
                Spacer()
                Button("Annuler") { done(nil) }.buttonStyle(PillStyle(filled: false, height: 48))
                    .keyboardShortcut(.cancelAction)
                Button(sending ? "Création…" : "Créer") { Task { await create() } }
                    .buttonStyle(PillStyle(height: 48, icone: "checkmark.circle"))
                    .disabled(sending)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .foregroundStyle(T.ink)
        .frame(width: 620, height: 640).background(T.bg)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(rounded(15, .semibold)).foregroundStyle(T.muted)
    }

    private func field(_ l: String, _ text: Binding<String>, _ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(l)
            TextField(prompt, text: text).textFieldStyle(.plain).font(rounded(17)).padding(14).champ()
        }
    }

    private func picker(_ l: String, _ options: [(String, String)], _ sel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(l)
            Picker("", selection: sel) { ForEach(options, id: \.1) { Text($0.0).tag($0.1) } }
                .labelsHidden().frame(maxWidth: 280)
        }
    }

    private func create() async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { error = "Donnez un titre à l’automate."; return }
        guard mac || windows else { error = "Choisissez au moins Mac ou Windows."; return }
        let steps = stepsText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var action: [String: Any]
        switch kind {
        case .holo:
            let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !g.isEmpty else { error = "Dites à Holo ce qu’il doit faire."; return }
            action = ["do": "holo", "goal": g, "steps": steps]
        case .folder:
            action = ["do": "open_folder", "folder": folder, "subfolder": subfolder.trimmingCharacters(in: .whitespaces)]
        case .settings:
            action = ["do": "open_settings", "page": page]
        case .url:
            action = ["do": "open_url", "url": link.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        let pack: [String: Any] = [
            "papai": 1, "title": t,
            "description": detail.trimmingCharacters(in: .whitespacesAndNewlines),
            "publisher": model.helperName?.isEmpty == false ? model.helperName! : "Mon support",
            "platforms": (mac ? ["mac"] : []) + (windows ? ["windows"] : []),
            "actions": [action],
            "steps": steps.map { ["instruction": $0] },
        ]
        guard let url = URL(string: model.baseHTTP + "/automations"),
              let body = try? JSONSerialization.data(withJSONObject: pack) else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        sending = true; defer { sending = false }
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            if (r as? HTTPURLResponse)?.statusCode == 200 {
                done(obj?["title"] as? String ?? t)
            } else {
                error = obj?["error"] as? String ?? "Le serveur a refusé cet automate."
            }
        } catch {
            self.error = "Impossible de joindre le serveur."
        }
    }
}
