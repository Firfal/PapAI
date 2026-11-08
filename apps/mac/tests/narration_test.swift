import Foundation

@main
struct NarrationTest {
    @MainActor static func main() {
        var total = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            total += 1
            print("  OK      \(name)")
        }
        var q = NarrationQueue()
        check(q.enabled, "activée par défaut")
        q.enqueue("Hors assistance")
        check(q.next() == nil, "aucune lecture hors assistance")
        q.context(assistance: true, speakingAllowed: true)
        q.enqueue("  Je clique\n ici  ")
        q.enqueue("Je clique ici")
        q.enqueue("J'ouvre le dossier")
        check(q.pending.count == 2, "normalisation et doublons avant lecture")
        check(q.next() == "Je clique ici", "première phrase")
        q.enqueue("Je clique ici")
        check(q.next() == "J'ouvre le dossier", "file dans l'ordre")
        check(q.next() == nil, "pas de doublon après lecture")
        q.enqueue("Avant la dictée")
        q.dictating = true
        check(!q.canRead && q.pending.isEmpty, "dictée : lecture interdite et file vidée")
        q.enqueue("Pendant la dictée")
        q.dictating = false
        q.enqueue("Avant la dictée")
        q.enqueue("Pendant la dictée")
        check(q.next() == nil, "pas de rattrapage des phrases interrompues ou dictées")
        q.enqueue("Après la dictée")
        check(q.next() == "Après la dictée", "nouvelle phrase après dictée")
        q.enqueue("Avant coupure")
        q.enabled = false
        q.enqueue("Lecture coupée")
        check(q.pending.isEmpty && !q.canRead, "interrupteur coupe et vide la file")
        q.enabled = true
        q.enqueue("Lecture coupée")
        check(q.next() == nil, "réactivation sans rattrapage")
        q.enqueue("Avant pause")
        q.context(assistance: true, speakingAllowed: false)
        check(q.pending.isEmpty && !q.canRead, "pause, alerte ou déconnexion : file vidée")
        q.context(assistance: true, speakingAllowed: true)
        q.enqueue("Avant pause")
        check(q.next() == nil, "reprise sans répétition")
        q.enqueue("Avant fin")
        q.context(assistance: false, speakingAllowed: false)
        check(q.pending.isEmpty && q.next() == nil, "fin ou arrêt : file vidée")
        q.context(assistance: true, speakingAllowed: true)
        q.enqueue("Je clique ici")
        check(q.next() == "Je clique ici", "nouvelle assistance : même phrase autorisée")
        q.enqueue(" \n ")
        check(q.next() == nil, "phrase vide ignorée")

        let suite = "PapAI.NarrationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let narration = LocalNarration(defaults: defaults)
        check(narration.enabled, "préférence absente : lecture activée")
        narration.enabled = false
        check(!LocalNarration(defaults: defaults).enabled, "préférence coupée conservée localement")
        narration.enabled = true
        check(LocalNarration(defaults: defaults).enabled, "préférence réactivée conservée localement")
        print("Narration : \(total) contrôles réussis")
    }
}
