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

/// Le plan proposé par Holo (`POST …/automations/draft`, `kind: request`).
struct PropositionAutomate: Equatable {
    var demande: String
    var brouillon: [String: Any]
    var titre: String { brouillon["title"] as? String ?? String(localized: "Nouvel automate") }
    var etapes: [String] { brouillon["steps"] as? [String] ?? [] }

    static func == (a: Self, b: Self) -> Bool { a.demande == b.demande && a.titre == b.titre && a.etapes == b.etapes }

    /// Demande le plan à Holo. Rien n'est enregistré à ce stade.
    static func preparer(_ demande: String, base: String) async -> Result<Self, Erreur> {
        guard let url = URL(string: base + "/automations/draft") else { return .failure(Erreur(texte: String(localized: "Serveur introuvable."))) }
        switch await post(url, ["kind": "request", "text": demande, "os": "mac", "lang": AppLangue.anglais ? "en" : "fr"], attente: 60) {
        case .success(let d): return .success(Self(demande: demande, brouillon: d))
        case .failure(let e): return .failure(e)
        }
    }

    /// Envoie le ticket au support IT, avec le plan.
    func envoyer(base: String) async -> Result<Int, Erreur> {
        guard let url = URL(string: base + "/tickets") else { return .failure(Erreur(texte: String(localized: "Serveur introuvable."))) }
        switch await Self.post(url, ["task": demande, "automate": brouillon], attente: 20) {
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
            return .failure(Erreur(texte: String(localized: "Je ne joins pas le serveur pour le moment. Réessayez dans un instant.")))
        }
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        guard (r as? HTTPURLResponse)?.statusCode == 200 else {
            return .failure(Erreur(texte: obj["error"] as? String ?? String(localized: "Ça n'a pas marché. Réessayez dans un instant.")))
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
    @State private var envoi = false
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !trouves.isEmpty {
                entete(trouves.count > 1 ? String(localized: "Ces automates correspondent à votre demande") : String(localized: "Cet automate correspond à votre demande"))
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
            } else if prepare {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Aucun automate ne correspond. Préparation de votre demande…")
                        .font(rounded(17, .medium)).fixedSize(horizontal: false, vertical: true)
                }
            } else if let p = proposition {
                entete(String(localized: "Aucun automate ne correspond"))
                Text("Votre question sera envoyée à votre support IT, qui s’en occupe.")
                    .font(rounded(16)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                // Seule la question de l'utilisateur est montrée : le plan préparé par Holo part
                // au support avec le ticket, sans s'afficher ici.
                Text("« \(p.demande) »").font(rounded(18, .semibold)).fixedSize(horizontal: false, vertical: true)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: T.r, style: .continuous).fill(T.field))
                if let erreur {
                    Label(LocalizedStringKey(erreur), systemImage: "exclamationmark.circle").font(rounded(15, .semibold))
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
            model.showNotice(n > 0 ? String(localized: "Demande n° \(n) envoyée à votre support IT. Vous la suivez dans l’onglet Mes demandes.")
                                   : String(localized: "Demande envoyée à votre support IT. Vous la suivez dans l’onglet Mes demandes."))
        case .failure(let e):
            erreur = e.texte
        }
    }
}
