// Test du détecteur de fin de phrase, sans micro.
//   swiftc -o /tmp/silence_test apps/mac/Sources/SilenceDetector.swift apps/mac/tests/silence_test.swift && /tmp/silence_test
import Foundation

var fails = 0
func check(_ ok: Bool, _ label: String) { print((ok ? "  OK      " : "  ÉCHEC   ") + label); if !ok { fails += 1 } }

/// Rejoue une suite (durée en s, niveau dB) par pas de 50 ms ; renvoie l'événement et l'instant.
func run(_ segments: [(Double, Float)], jitter: Float = 2) -> (SilenceDetector.Event, Double) {
    var d = SilenceDetector()
    let t0 = Date(timeIntervalSince1970: 0)
    var t = 0.0, i = 0
    for (dur, db) in segments {
        var k = 0.0
        while k < dur {
            let noise = Float((i * 7919) % 11) / 10 * jitter - jitter / 2  // bruit déterministe
            let e = d.feed(db + noise, at: t0.addingTimeInterval(t))
            if e != .none { return (e, t) }
            k += 0.05; t += 0.05; i += 1
        }
    }
    return (.none, t)
}

@main
struct SilenceTest {
    static func main() {
        // Salon calme : bruit -52 dB, voix -22 dB pendant 3 s, puis silence.
        var (e, t) = run([(0.6, -52), (3, -22), (4, -52)])
        check(e == .endOfSpeech && t > 3.6 && t < 6, "salon calme : envoi ~1,6 s après la fin de la phrase (\(t) s)")

        // Salle bruyante (hackathon) : bruit -30 dB, voix -12 dB. L'ancien seuil fixe ne s'arrêtait jamais.
        (e, t) = run([(0.6, -30), (3, -12), (4, -30)], jitter: 4)
        check(e == .endOfSpeech && t < 6.5, "salle bruyante : envoi quand même (\(t) s)")

        // La personne parle dès le premier instant (pas de silence au début).
        (e, t) = run([(3, -18), (5, -45)])
        check(e == .endOfSpeech && t < 6, "parle tout de suite : envoi après la phrase (\(t) s)")

        // Pauses courtes en parlant (0,8 s) : on n'envoie pas au milieu.
        (e, t) = run([(0.5, -50), (1.5, -20), (0.8, -50), (1.5, -20), (4, -50)])
        check(e == .endOfSpeech && t > 4.2, "pause courte au milieu : on attend la vraie fin (\(t) s)")

        // Personne ne parle : arrêt à 8 s.
        (e, t) = run([(12, -50)])
        check(e == .nothingHeard && t >= 7.9 && t < 8.5, "rien dit : arrêt vers 8 s (\(t) s)")

        print("\n\(5 - fails) contrôles passés, \(fails) échec(s)")
        exit(fails == 0 ? 0 : 1)
    }
}
