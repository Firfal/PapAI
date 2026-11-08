import SwiftUI

/// La barre de l'accueil cherche d'abord dans les automates de l'utilisateur.
/// Rien ne correspond : Holo propose le plan d'un automate, que l'utilisateur
/// envoie au support IT dans un ticket ; le support le valide pour le créer.
enum RechercheAutomates {
    /// Mots qui ne disent rien de la tâche (« je n'arrive plus à… »).
    private static let vides: Set<String> = [
        "les", "des", "une", "est", "pas", "plus", "pour", "dans", "sur", "avec", "mon", "mes", "ma", "ton", "son",
        "ses", "que", "qui", "quoi", "comment", "faire", "veux", "voudrais", "aimerais", "peux", "pouvez", "arrive",
        "marche", "fonctionne", "aide", "aider", "besoin", "moi", "mettre", "svp", "merci", "bonjour", "cette", "ces",
    ]

    static func mots(_ s: String) -> [String] {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split { !$0.isLetter && !$0.isNumber }
            .map { w in
                var w = String(w)
                if w.count > 4, w.hasSuffix("s") || w.hasSuffix("x") { w.removeLast() }
                return w
            }
            .filter { $0.count >= 3 && !vides.contains($0) }
    }

    /// Deux mots se valent s'ils partagent leur racine (« bloquer » / « bloqueur », « pub » / « publicités »).
    private static func proche(_ a: String, _ b: String) -> Bool {
        let n = min(5, a.count, b.count)
        return n >= 3 && a.prefix(n) == b.prefix(n)
    }

    /// Les automates qui répondent à la demande, les meilleurs d'abord (3 au plus) :
    /// plus de la moitié de ses mots doivent se retrouver dans le titre ou la description.
    static func chercher(_ demande: String, dans lessons: [Lesson]) -> [Lesson] {
        let q = mots(demande)
        guard !q.isEmpty else { return [] }
        let notes: [(Lesson, Int)] = lessons.compactMap { l in
            let m = mots(l.title + " " + (l.description ?? ""))
            let n = q.filter { w in m.contains { proche(w, $0) } }.count
            return n * 2 > q.count ? (l, n) : nil
        }
        return notes.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
    }
}

/// Demande floue : Holo pose une question avant de proposer le plan (PROTOCOL.md, pré-traitement).
struct QuestionHolo: Equatable {
    var demande: String
    var question: String
    var options: [String]
    var precisions: [[String: String]]
}

enum ReponseHolo {
    case question(QuestionHolo)
    case plan(PropositionAutomate)
}

/// Le plan proposé par Holo (`POST …/automations/draft`, `kind: request`).
struct PropositionAutomate: Equatable {
    var demande: String
    var brouillon: [String: Any]
    var titre: String { brouillon["title"] as? String ?? "Nouvel automate" }
    var etapes: [String] { brouillon["steps"] as? [String] ?? [] }

    static func == (a: Self, b: Self) -> Bool { a.demande == b.demande && a.titre == b.titre && a.etapes == b.etapes }

    /// Demande le plan à Holo, ou une question si la demande est floue. Rien n'est enregistré à ce stade.
    static func preparer(_ demande: String, precisions: [[String: String]] = [], envoyerQuandMeme: Bool = false,
                         base: String) async -> Result<ReponseHolo, Erreur> {
        guard let url = URL(string: base + "/automations/draft") else { return .failure(Erreur(texte: "Serveur introuvable.")) }
        var body: [String: Any] = ["kind": "request", "text": demande, "os": "mac", "precisions": precisions]
        if envoyerQuandMeme { body["skip"] = true }
        switch await post(url, body, attente: 60) {
        case .success(let d):
            if let c = d["clarify"] as? [String: Any], let q = c["question"] as? String, !q.isEmpty {
                return .success(.question(QuestionHolo(demande: demande, question: q,
                                                       options: c["options"] as? [String] ?? [], precisions: precisions)))
            }
            return .success(.plan(Self(demande: demande, brouillon: d)))
        case .failure(let e): return .failure(e)
        }
    }

    /// Envoie le ticket au support IT, avec le plan.
    func envoyer(base: String) async -> Result<Int, Erreur> {
        guard let url = URL(string: base + "/tickets") else { return .failure(Erreur(texte: "Serveur introuvable.")) }
        // L'objet formel rédigé par Holo devient le titre du ticket ; les mots d'origine restent.
        let body: [String: Any] = ["task": brouillon["objet"] as? String ?? demande, "demande": demande,
                                   "precisions": brouillon["precisions"] ?? [], "automate": brouillon]
        switch await Self.post(url, body, attente: 20) {
        case .success(let d): return .success(((d["ticket"] as? [String: Any])?["number"] as? NSNumber)?.intValue ?? 0)
        case .failure(let e): return .failure(e)
        }
    }

    struct Erreur: Error { var texte: String }

    private static func post(_ url: URL, _ body: [String: Any], attente: TimeInterval) async -> Result<[String: Any], Erreur> {
        var req = URLRequest(url: url, timeoutInterval: attente)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, r) = try? await URLSession.shared.data(for: req) else {
            return .failure(Erreur(texte: "Je ne joins pas le serveur pour le moment. Réessayez dans un instant."))
        }
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        guard (r as? HTTPURLResponse)?.statusCode == 200 else {
            return .failure(Erreur(texte: obj["error"] as? String ?? "Ça n'a pas marché. Réessayez dans un instant."))
        }
        return .success(obj)
    }
}

/// Sous la barre : les automates trouvés, ou la proposition de ticket.
struct ResultatsRecherche: View {
    @Environment(AppModel.self) private var model
    var trouves: [Lesson]
    var prepare: Bool
    var proposition: PropositionAutomate?
    var fermer: () -> Void
    var question: QuestionHolo? = nil
    /// Réponse à la question de Holo ; nil : « Envoyer quand même ».
    var repondre: (String?) -> Void = { _ in }
    @State private var reponse = ""
    @State private var envoi = false
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !trouves.isEmpty {
                entete(trouves.count > 1 ? "Ces automates correspondent à votre demande" : "Cet automate correspond à votre demande")
                ForEach(trouves) { l in
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars").font(rounded(17)).foregroundStyle(T.accent)
                            .frame(width: 36, height: 36).background(Circle().fill(T.mint))
                        Text(l.title).font(rounded(18, .semibold)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { fermer(); model.runShortcut(l) } label: {
                            Text("Exécuter").font(rounded(15, .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(Capsule().fill(T.primary)).contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Exécuter \(l.title)")
                    }
                }
            } else if let q = question {
                entete("Holo a besoin d’une précision")
                Text(q.question).font(rounded(19, .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Votre demande : « \(q.demande) »").font(rounded(15)).foregroundStyle(T.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(q.options, id: \.self) { o in
                        Button { repondre(o) } label: {
                            Text(o).font(rounded(16, .semibold)).foregroundStyle(T.ink)
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(Capsule().fill(T.field)).contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                HStack(spacing: 10) {
                    TextField("Ou dites-le avec vos mots", text: $reponse)
                        .textFieldStyle(.plain).font(rounded(16)).padding(.horizontal, 14).frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.field))
                        .onSubmit(envoyerReponse)
                    Button(action: envoyerReponse) {
                        Text("Répondre").font(rounded(16, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(Capsule().fill(T.primary)).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(reponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Ne donnez jamais de mot de passe ni de code : on ne vous les demandera pas.")
                    .font(rounded(13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Envoyer quand même") { repondre(nil) }
                        .buttonStyle(.plain).font(rounded(16, .semibold)).foregroundStyle(T.accent).frame(minHeight: 44)
                    Button("Annuler", action: fermer)
                        .buttonStyle(.plain).font(rounded(16, .semibold)).foregroundStyle(T.muted).frame(minHeight: 44)
                }
            } else if prepare {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Aucun automate ne correspond. Holo prépare une proposition pour votre support IT…")
                        .font(rounded(17, .medium)).fixedSize(horizontal: false, vertical: true)
                }
            } else if let p = proposition {
                entete("Aucun automate ne correspond")
                Text("Je peux demander à votre support IT de créer cet automate. Une fois validé, il apparaîtra dans vos automates.")
                    .font(rounded(16)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.titre).font(rounded(18, .bold))
                    ForEach(Array(p.etapes.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(rounded(14, .bold)).foregroundStyle(T.accent)
                                .frame(width: 24, height: 24).background(Circle().fill(T.mint))
                            Text(s).font(rounded(16)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.field))
                if let erreur {
                    Label(erreur, systemImage: "exclamationmark.circle").font(rounded(15, .semibold))
                        .foregroundStyle(T.danger).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button { Task { await envoyer(p) } } label: {
                        HStack(spacing: 8) {
                            if envoi { ProgressView().controlSize(.small).tint(.white) }
                            Text("Envoyer au support IT")
                        }
                        .font(rounded(16, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(Capsule().fill(T.primary)).contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle()).disabled(envoi)
                    Button("Annuler", action: fermer)
                        .buttonStyle(.plain).font(rounded(16, .semibold)).foregroundStyle(T.muted)
                        .frame(minHeight: 44).disabled(envoi)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.card))
        .foregroundStyle(T.ink)
    }

    private func envoyerReponse() {
        let t = reponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        reponse = ""
        repondre(String(t.prefix(300)))
    }

    private func entete(_ s: String) -> some View {
        HStack {
            Text(s).font(rounded(17, .bold))
            Spacer(minLength: 0)
            Button(action: fermer) { Image(systemName: "xmark").font(rounded(14, .semibold)).foregroundStyle(T.muted).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Fermer")
        }
    }

    private func envoyer(_ p: PropositionAutomate) async {
        envoi = true; erreur = nil
        defer { envoi = false }
        switch await p.envoyer(base: model.httpBase) {
        case .success(let n):
            fermer()
            model.showNotice("Demande\(n > 0 ? " n° \(n)" : "") envoyée à votre support IT. Vous la suivez dans l’onglet Tickets.")
        case .failure(let e):
            erreur = e.texte
        }
    }
}
