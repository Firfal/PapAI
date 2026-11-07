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
                }
            }
        }
    }
}
#endif
