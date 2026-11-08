import Foundation

@main
struct GladiaLiveTest {
    @MainActor
    static func main() async throws {
        var phrases = LiveTranscript()
        assert(phrases.update(id: "1", text: "Bon", final: false) == "Bon")
        assert(phrases.update(id: "1", text: "Bonjour.", final: true) == "Bonjour.")
        assert(phrases.update(id: "1", text: "Bon", final: false) == "Bonjour.")
        assert(phrases.update(id: "2", text: " Merci. ", final: true) == "Bonjour. Merci.")
        var selection = DictationText()
        selection.updateApple("Texte Apple incorrect")
        assert(selection.displayed.isEmpty)
        selection.updateGladia("Texte Gladia")
        assert(selection.displayed == "Texte Gladia")
        selection.updateApple("Texte Apple corrigé")
        assert(selection.displayed == "Texte Gladia")
        selection.fallback()
        assert(selection.displayed == "Texte Apple corrigé")
        selection.updateGladia("Résultat tardif")
        assert(selection.displayed == "Texte Apple corrigé")
        var withoutApple = DictationText()
        withoutApple.updateGladia("Mots disponibles")
        withoutApple.fallback()
        assert(withoutApple.displayed == "Mots disponibles")
        assert(GladiaLive.endpoint(transcribe: URL(string: "https://exemple.fr/k/secret/transcribe"))?.absoluteString
               == "wss://exemple.fr/k/secret/transcribe/live")
        assert(GladiaLive.endpoint(transcribe: nil) == nil)
        assert(GladiaLive.endpoint(transcribe: URL(string: "file:///tmp/audio")) == nil)

        if CommandLine.arguments.count > 2 {
            let mode = CommandLine.arguments[2]
            let (audio, continuation) = GladiaLive.Audio.makeStream(bufferingPolicy: .bufferingOldest(128))
            let client = GladiaLive()
            var texts: [String] = []
            var fallback = false
            client.start(transcribe: URL(string: CommandLine.arguments[1]), audio: audio,
                         onText: { texts.append($0) }, onFallback: { fallback = true })
            continuation.yield(Data(repeating: 0, count: 3200))
            for _ in 0..<100 where texts.isEmpty && !fallback {
                try await Task.sleep(for: .milliseconds(20))
            }
            if mode == "live" {
                assert(!fallback && texts.first == "Bonjour", "Le partiel doit arriver AVANT l'arrêt")
                continuation.yield(Data(repeating: 0, count: 3200))
                for _ in 0..<100 where texts.last != "Bonjour les photos" {
                    try await Task.sleep(for: .milliseconds(20))
                }
                assert(texts.last == "Bonjour les photos", "Le partiel remplace ses mots, sans doublon")
                continuation.finish()
                await client.waitForCompletion()
                assert(!fallback && texts.last == "Bonjour les photos. Merci.", "Les derniers mots doivent être conservés")
            } else if mode == "cancel" {
                client.cancel()
                let count = texts.count
                continuation.finish()
                try await Task.sleep(for: .milliseconds(100))
                assert(!fallback && texts.count == count, "Annuler ne doit plus publier de texte ni de repli")
            } else {
                continuation.finish()
                await client.waitForCompletion()
                assert(fallback, "Indisponibilité : repli obligatoire")
            }
        }
        print("OK : assemblage, choix Gladia/Apple, URL et cycle WebSocket")
    }
}
