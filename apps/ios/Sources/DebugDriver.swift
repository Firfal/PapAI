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
                    else if l.hasPrefix("pair:"), case .pair(let link)? = sheet {
                        // pair:Prénom|lien|code (code seulement pour la saisie manuelle)
                        let p = l.dropFirst(5).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        Task { await submitPair(link, code: p.count > 2 ? p[2] : nil, name: p[0], relation: p.count > 1 ? p[1] : "") }
                    }
                    else if l == "settings" { sheet = .settings }
                    else if l == "scanner" { sheet = .scanner }
                    else if l == "manual", let link = manualPairLink() { openPair(link) }
                    else if l == "close" { sheet = nil }
                }
            }
        }
    }
}
#endif
