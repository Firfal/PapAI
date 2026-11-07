import Foundation

/// Décide quand la personne a fini de parler, à partir du niveau du micro (dB).
///
/// Le seuil s'adapte au bruit de la pièce : un salon calme est vers -50 dB, une
/// salle de hackathon vers -30 dB. Un seuil fixe (l'ancien -38 dB) prenait le
/// brouhaha pour de la voix et n'envoyait jamais. Ici on mesure le bruit de
/// fond, et seule une voix nettement au-dessus compte.
///
/// Pur et sans dépendance : testé par `apps/mac/tests/silence_test.swift`.
struct SilenceDetector {
    enum Event: Equatable { case none, endOfSpeech, nothingHeard }

    /// Silence après la voix avant d'envoyer.
    var silenceToSend: TimeInterval = 1.6
    /// Rien qui ressemble à de la voix : on arrête quand même (et on transcrit).
    var nothingHeard: TimeInterval = 8
    /// La voix doit dépasser le bruit de fond d'au moins ça.
    var voiceMargin: Float = 10
    /// En dessous, plus de voix : un peu moins haut que pour l'entrée, pour ne pas
    /// hésiter entre les deux.
    var quietMargin: Float = 6
    /// Durée de voix minimale pour considérer qu'on a parlé (évite un toussotement).
    var minVoice: TimeInterval = 0.35

    private(set) var floor: Float?
    private var start: Date?
    private var voiceSince: Date?
    private var spoke = false
    private var quietSince: Date?
    /// Le plus fort entendu, et combien de temps on a été près de ce niveau : si
    /// la personne parle dès la première seconde, le « bruit de fond » mesuré au
    /// départ était sa voix. Quand le son retombe nettement plus bas, ça compte.
    private var peak: Float = -80
    private var nearPeak: TimeInterval = 0
    private var lastT: Date?

    mutating func feed(_ rawDB: Float, at t: Date) -> Event {
        let db = max(rawDB, -80)
        if start == nil { start = t }
        let elapsed = t.timeIntervalSince(start!)
        let dt = lastT.map { t.timeIntervalSince($0) } ?? 0
        lastT = t
        if db > peak { peak = db }
        if db >= peak - quietMargin { nearPeak += dt }

        // Bruit de fond : on part du plus bas entendu au début, puis on suit
        // lentement les moments calmes (jamais la voix).
        if floor == nil { floor = db }
        if let f = floor {
            if db < f { floor = db }
            else if db < f + quietMargin { floor = f * 0.97 + db * 0.03 }
        }
        let f = floor ?? db
        if !spoke, peak > f + voiceMargin, nearPeak >= minVoice { spoke = true }

        if db > f + voiceMargin {
            if voiceSince == nil { voiceSince = t }
            if t.timeIntervalSince(voiceSince!) >= minVoice { spoke = true }
            quietSince = nil
        } else if db < f + quietMargin {
            voiceSince = nil
            if spoke {
                if quietSince == nil { quietSince = t }
                if t.timeIntervalSince(quietSince!) >= silenceToSend { return .endOfSpeech }
            }
        }
        if !spoke && elapsed >= nothingHeard { return .nothingHeard }
        return .none
    }
}
