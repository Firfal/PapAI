import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Onglet « Mes automates » du mode support.
struct SupportAutomates: View {
    /// Création d'automate (à la main, document, enregistrement) masquée pour l'instant.
    /// Le code reste en place : repasser à `true` pour la réactiver.
    static let creationActive = false
    let model: HelperModel
    @State private var lib = AutomateLibrary.shared
    @State private var creating = false
    @State private var importing = false
    @State private var applying: AutomateLibrary.Entry?
    @State private var toDelete: AutomateLibrary.Entry?
    @State private var error: String?

    var body: some View {
        Panneau {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mes automates").font(rounded(30, .bold))
                    Text("Votre bibliothèque. Choisissez ensuite à qui appliquer chaque automate.")
                        .font(rounded(17, .medium)).opacity(0.92)
                }
                Spacer(minLength: 0)
                if Self.creationActive {
                    Button { creating = true } label: { Label("Créer un automate", systemImage: "plus.circle.fill") }
                        .buttonStyle(PillStyle(filled: false, height: 50))
                }
            }
        } corps: {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(lib.entries.count) automate\(lib.entries.count > 1 ? "s" : "")")
                            .font(rounded(16, .semibold)).foregroundStyle(T.muted)
                        Spacer()
                        Button("Importer un fichier .papai") { importing = true }
                            .buttonStyle(.plain).font(rounded(14, .semibold)).foregroundStyle(T.leaf)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(rounded(15, .semibold))
                            .foregroundStyle(T.danger)
                    }
                    if lib.entries.isEmpty {
                        Text(Self.creationActive ? "Aucun automate. Créez-en un à partir d’un document, d’un enregistrement de votre écran, ou à la main."
                                                 : "Aucun automate. Importez un fichier .papai.")
                            .font(rounded(16)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(lib.entries) { e in row(e) }
                }
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $creating) {
            SupportCreateAutomate(model: model) { pack in
                creating = false
                if let pack, let d = try? JSONSerialization.data(withJSONObject: pack), let e = lib.add(pack: d) {
                    model.showToast("« \(e.title) » ajouté à vos automates")
                    applying = e
                }
            }
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
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Supprimer « \(toDelete?.title ?? "") »", role: .destructive) { if let e = toDelete { lib.remove(e) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les personnes chez qui il est déjà appliqué le gardent.")
        }
    }

    private func row(_ e: AutomateLibrary.Entry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol(e.firstAction)).font(.system(size: 18, weight: .semibold)).foregroundStyle(T.accent)
                .frame(width: 44, height: 44).background(Circle().fill(T.mint))
            VStack(alignment: .leading, spacing: 5) {
                Text(e.title).font(rounded(19, .semibold))
                if !e.detail.isEmpty {
                    Text(e.detail).font(rounded(15)).foregroundStyle(T.muted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if e.stepCount > 0 { tag("\(e.stepCount) étape\(e.stepCount > 1 ? "s" : "")") }
                    if !e.platforms.isEmpty { tag(e.platforms.map { $0 == "mac" ? "Mac" : "Windows" }.joined(separator: " · ")) }
                    if !e.publisher.isEmpty { tag(e.publisher) }
                }
                let names = AutomateLibrary.appliedTo(e, people: model.people, orgName: model.orgName)
                Text(names.isEmpty ? "Appliqué à personne" : "Appliqué à : " + names.joined(separator: ", "))
                    .font(rounded(14, .semibold)).foregroundStyle(names.isEmpty ? T.muted : T.leaf)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button("Appliquer…") { applying = e }.buttonStyle(PillStyle(height: 40))
                Button { toDelete = e } label: {
                    Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.muted)
                        .frame(width: 36, height: 36).background(Circle().fill(T.field))
                }
                .buttonStyle(.plain).accessibilityLabel("Supprimer \(e.title)")
            }
        }
        .padding(14).carte()
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(rounded(13, .semibold)).foregroundStyle(T.muted)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(T.field))
    }

    private func symbol(_ action: String) -> String {
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

/// Choisir les utilisateurs chez qui appliquer un automate.
struct ApplyAutomateSheet: View {
    let model: HelperModel
    let entry: AutomateLibrary.Entry
    var close: () -> Void
    @State private var chosen: Set<String> = []
    @State private var orgs: [OrgMembers] = []
    @State private var chosenOrgs: Set<String> = []
    @State private var sending = false
    @State private var results: [String: String] = [:]   // clé ou jeton -> erreur ("" = réussi)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appliquer « \(entry.title) »").font(rounded(24, .bold))
            Text("Les personnes cochées pourront le relancer d’un clic. Vous pouvez aussi ne l’appliquer à personne pour l’instant.")
                .font(rounded(15)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if model.people.isEmpty {
                Text("Aucun utilisateur relié à ce poste.").font(rounded(16)).foregroundStyle(T.muted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(orgs) { o in
                        let already = entry.orgKeys?[o.token] != nil
                        let done = results[o.token] == ""
                        HStack {
                            Toggle(isOn: Binding(get: { chosenOrgs.contains(o.token) || already || done },
                                                 set: { on in if on { chosenOrgs.insert(o.token) } else { chosenOrgs.remove(o.token) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.name.isEmpty ? "Toute l’organisation" : "Toute l’organisation \(o.name)").font(rounded(17, .semibold))
                                    Text(o.detail).font(rounded(13)).foregroundStyle(T.muted)
                                }
                            }
                            .toggleStyle(.checkbox).disabled(already || done || sending)
                            Spacer()
                            if already { Text("déjà appliqué").font(rounded(13)).foregroundStyle(T.leaf) }
                            if let r = results[o.token] {
                                Text(r.isEmpty ? "Appliqué" : r).font(rounded(13, .semibold))
                                    .foregroundStyle(r.isEmpty ? T.leaf : T.danger)
                            }
                        }
                        .padding(12).champ()
                    }
                    ForEach(model.people) { p in
                        let already = entry.applied.contains(p.key)
                        let covered = orgs.contains { chosenOrgs.contains($0.token) && $0.keys.contains(p.key) }
                        let done = results[p.key] == ""
                        HStack {
                            Toggle(isOn: Binding(get: { chosen.contains(p.key) || already || covered || done },
                                                 set: { on in if on { chosen.insert(p.key) } else { chosen.remove(p.key) } })) {
                                Text(p.name.isEmpty ? "Utilisateur" : p.name).font(rounded(17, .semibold))
                            }
                            .toggleStyle(.checkbox).disabled(already || covered || done || sending)
                            Spacer()
                            if already { Text("déjà appliqué").font(rounded(13)).foregroundStyle(T.leaf) }
                            if let r = results[p.key] {
                                Text(r.isEmpty ? "Appliqué" : r).font(rounded(13, .semibold))
                                    .foregroundStyle(r.isEmpty ? T.leaf : T.danger)
                            }
                        }
                        .padding(12).champ()
                    }
                }
            }
            HStack {
                Spacer()
                Button(results.isEmpty ? "Plus tard" : "Fermer") { close() }.buttonStyle(PillStyle(filled: false, height: 46))
                Button(sending ? "Envoi…" : "Appliquer") { Task { await apply() } }
                    .buttonStyle(PillStyle(height: 46, icone: "checkmark.circle"))
                    .disabled((chosen.isEmpty && chosenOrgs.isEmpty) || sending)
            }
        }
        .padding(24).frame(width: 480, height: 460).background(T.bg).foregroundStyle(T.ink)
        .task { orgs = await OrgMembers.load(model.org, name: model.orgName) }
    }

    private func apply() async {
        sending = true; defer { sending = false }
        let r = await AutomateLibrary.shared.apply(entry, people: model.people.filter { chosen.contains($0.key) },
                                                   orgs: orgs.filter { chosenOrgs.contains($0.token) })
        results.merge(r) { _, n in n }
        let ok = r.filter { $0.value.isEmpty }.map(\.key)
        chosen.subtract(ok); chosenOrgs.subtract(ok)
        if !ok.isEmpty { await model.loadLessons() }
    }
}

/// Création d'un automate : un titre, ce qu'il fait (une action de premier
/// niveau, jamais de commande) et le pas à pas « Montrez-moi ».
struct SupportCreateAutomate: View {
    let model: HelperModel
    /// Brouillon venu d'une suggestion de l'onglet Tickets (title, description, goal).
    var prefill: [String: String]? = nil
    var done: ([String: Any]?) -> Void

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
    @State private var importing = false
    @State private var drafting = false
    @State private var draftNote: String?
    @State private var warning: String?
    @State private var recorder = SupportRecorder()
    @State private var reviewing = false

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
                    sources
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
                Text("Il rejoint vos automates ; vous choisirez ensuite à qui l’appliquer.").font(rounded(14)).foregroundStyle(T.muted)
                Spacer()
                Button("Annuler") { done(nil) }.buttonStyle(PillStyle(filled: false, height: 48))
                    .keyboardShortcut(.cancelAction)
                Button("Ajouter à mes automates") { Task { await create() } }
                    .buttonStyle(PillStyle(height: 48, icone: "checkmark.circle"))
                    .disabled(sending)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .foregroundStyle(T.ink)
        .frame(width: 640, height: 700).background(T.bg)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText]) { r in
            if case .success(let url) = r { Task { await importDocument(url) } }
        }
        .onAppear {
            recorder.onStop = { reviewing = true }
            if let p = prefill, title.isEmpty {
                title = p["title"] ?? ""; detail = p["description"] ?? ""; goal = p["goal"] ?? ""; kind = .holo
            }
        }
    }

    // MARK: Sources (document, enregistrement)

    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Partir d’une source (Holo prépare un brouillon, vous le relisez)")
            HStack(spacing: 10) {
                Button { importing = true } label: { Label("Importer un document", systemImage: "doc.text") }
                    .buttonStyle(PillStyle(filled: false, height: 46))
                Button { recorder.start() } label: { Label("Enregistrer mon écran", systemImage: "record.circle") }
                    .buttonStyle(PillStyle(filled: false, height: 46))
                Toggle("avec ma voix", isOn: $recorder.withVoice).toggleStyle(.checkbox).font(rounded(15))
            }
            Text("Document : .txt, .md ou .pdf. Enregistrement : faites la manipulation sur votre poste en la commentant ; seules quelques captures clés sont gardées.")
                .font(rounded(13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if drafting {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Holo prépare le brouillon…").font(rounded(15)) }
            }
            if let draftNote {
                Label(draftNote, systemImage: "sparkles").font(rounded(14, .semibold)).foregroundStyle(T.leaf)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(rounded(14, .semibold))
                    .foregroundStyle(T.danger).fixedSize(horizontal: false, vertical: true)
            }
            if let e = recorder.error {
                Text(e).font(rounded(13)).foregroundStyle(T.danger).fixedSize(horizontal: false, vertical: true)
            }
            if reviewing && !recorder.shots.isEmpty {
                RecorderReview(rec: recorder, analyze: { reviewing = false; Task { await analyzeRecording() } },
                               cancel: { reviewing = false; recorder.shots = [] })
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.mint))
    }

    private func importDocument(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var text = ""
        if url.pathExtension.lowercased() == "pdf" {
            text = PDFDocument(url: url)?.string ?? ""   // le PDF est lu ici, seul le texte part
        } else {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else {
            error = "Ce document ne contient pas de texte lisible (un PDF scanné, par exemple)."
            return
        }
        await requestDraft(["kind": "document", "name": url.lastPathComponent, "text": String(text.prefix(20_000))],
                           note: "Brouillon tiré de « \(url.lastPathComponent) »")
    }

    private func analyzeRecording() async {
        let frames = recorder.selected().compactMap { SupportRecorder.jpegB64($0) }.map { ["b64": $0, "mime": "image/jpeg"] }
        guard !frames.isEmpty else { return }
        await requestDraft(["kind": "recording", "frames": frames,
                            "narration": recorder.narration.trimmingCharacters(in: .whitespacesAndNewlines)],
                           note: "Brouillon tiré de votre enregistrement (\(frames.count) captures)")
        recorder.shots = []
    }

    private func requestDraft(_ body: [String: Any], note: String) async {
        guard let url = URL(string: model.baseHTTP + "/automations/draft"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        drafting = true; error = nil; draftNote = nil; warning = nil
        defer { drafting = false }
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
            guard (r as? HTTPURLResponse)?.statusCode == 200 else {
                error = obj["error"] as? String ?? "Holo n’a pas pu préparer de brouillon."
                return
            }
            title = obj["title"] as? String ?? title
            detail = obj["description"] as? String ?? detail
            kind = .holo
            goal = obj["goal"] as? String ?? goal
            stepsText = (obj["steps"] as? [String] ?? []).joined(separator: "\n")
            let p = obj["platforms"] as? [String] ?? ["mac", "windows"]
            mac = p.contains("mac"); windows = p.contains("windows")
            let w = (obj["warning"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            warning = w.isEmpty ? nil : w
            draftNote = note + ". Relisez et corrigez avant de créer."
        } catch {
            self.error = "Impossible de joindre le serveur."
        }
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
        done(pack)
    }
}
