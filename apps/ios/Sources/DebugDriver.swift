import SwiftUI

#if DEBUG
/// Pilote de vérification (build Debug seulement) : lit des commandes dans un fichier
/// (`-demoFile /chemin`) et appelle les mêmes méthodes que les boutons.
extension HelperModel {
    func startDebugDriver() {
        guard let path = UserDefaults.standard.string(forKey: "demoFile") else { return }
        Task {
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                guard let s = try? String(contentsOfFile: path, encoding: .utf8), !s.isEmpty else { continue }
                try? "".write(toFile: path, atomically: true, encoding: .utf8)
                for line in s.split(separator: "\n") {
                    let l = String(line)
                    if l.hasPrefix("refine:") { refinePlan(String(l.dropFirst(7))) }
                    else if l == "approve" { approvePlan() }
                    else if l == "refuse" { refusePlan() }
                    else if l == "pause" { pause() }
                    else if l == "lesson" { requestLesson() }
                    else if l == "approvelesson" { approveLesson() }
                    else if l == "aim" { setAiming(true) }
                    else if l.hasPrefix("target:") {
                        let p = l.dropFirst(7).split(separator: ","); if p.count == 2 { target = CGPoint(x: Double(p[0]) ?? 0, y: Double(p[1]) ?? 0) }
                    }
                    else if l == "click" { confirmClick() }
                    else if l.hasPrefix("answer:") { answer(String(l.dropFirst(7))) }
                    else if l.hasPrefix("pair:") || l.hasPrefix("pairconfirm:"), case .pair(let link)? = sheet {
                        // pair:Prénom|lien|code (code seulement pour la saisie manuelle)
                        let confirmed = l.hasPrefix("pairconfirm:")
                        let p = l.dropFirst(confirmed ? 12 : 5).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        Task { await submitPair(link, code: p.count > 2 ? p[2] : nil, name: p.first ?? "", relation: p.count > 1 ? p[1] : "") }
                    }
                    else if l == "settings" { sheet = .settings }
                    else if l == "scanner" { sheet = .scanner }
                    else if l == "manual", let link = manualPairLink() { openPair(link) }
                    else if l == "close" { sheet = nil }
                    // Données de démo pour les captures : plan, automates, fin d'aide.
                    else if l.hasPrefix("plan:") { plan = l.dropFirst(5).split(separator: ";").map(String.init) }
                    else if l.hasPrefix("lessons:") {
                        let items = l.dropFirst(8).split(separator: ";").map { ["title": String($0), "steps": [["instruction": ""], ["instruction": ""], ["instruction": ""]]] as [String: Any] }
                        if let d = try? JSONSerialization.data(withJSONObject: items) { lessons = (try? JSONDecoder().decode([Lesson].self, from: d)) ?? [] }
                    }
                    else if l.hasPrefix("guard:") {
                        // guard:titre|détail|demande
                        let p = l.dropFirst(6).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        lastAlert = (p[0], p.count > 1 ? p[1] : ""); guardTask = p.count > 2 ? p[2] : ""; guardAlertId = "demo"
                    }
                    else if l == "unguard" { guardAlertId = nil; lastAlert = nil }
                    else if l.hasPrefix("fresh:") { doneFresh = true; doneAnswer = String(l.dropFirst(6)) }
                    else if l.hasPrefix("snap:") { snapCards(to: String(l.dropFirst(5))) }
                    else if l.hasPrefix("state:") {
                        // state:awaiting_approval|tâche|question|étape|nb d'étapes
                        let p = l.dropFirst(6).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        state = p[0]; task = p.count > 1 ? p[1] : task
                        question = p.count > 2 && !p[2].isEmpty ? (p[2], []) : nil
                        planStep = p.count > 3 ? Int(p[3]) : nil
                        plan = Array(repeating: "", count: p.count > 4 ? Int(p[4]) ?? 0 : 0)
                        syncLive()
                    }
                }
            }
        }
    }
}
extension HelperModel {
    /// Rendu des cartes de l'écran verrouillé, pour les vérifier sans verrouiller.
    func snapCards(to dir: String) {
        typealias S = HelpActivityAttributes.ContentState
        let since = Date().addingTimeInterval(-90)
        let cases: [(String, S)] = [
            ("watching", S(phase: .watching, senior: "Sophie", task: "", detail: "", step: 0, steps: 0, since: since)),
            ("request", S(phase: .request, senior: "Sophie", task: "Envoyer les photos de Noël à Léa", detail: "", step: 0, steps: 3, since: since)),
            ("needsyou", S(phase: .needsYou, senior: "Sophie", task: "Envoyer les photos", detail: "Quel album faut-il ouvrir ?", step: 2, steps: 3, since: since)),
            ("working", S(phase: .working, senior: "Sophie", task: "Envoyer les photos de Noël à Léa", detail: "", step: 2, steps: 3, since: since)),
        ]
        for (name, s) in cases {
            let v = LockScreenCard(s: s)
                .frame(width: 360)
                .background(s.urgent ? PapColors.ink : PapColors.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(20).background(Color(red: 0.35, green: 0.42, blue: 0.5))
            let r = ImageRenderer(content: v); r.scale = 3
            try? r.uiImage?.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/card-\(name).png"))
        }
    }
}
#endif
