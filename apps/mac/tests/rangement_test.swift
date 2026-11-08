import Foundation

// swiftc -parse-as-library apps/mac/tests/rangement_test.swift apps/mac/Sources/Rangement.swift -o /tmp/rangement_test
@main
struct RangementTest {
    static func main() throws {
        var total = 0
        func verifier(_ value: Bool, _ name: String) {
            precondition(value, name)
            total += 1
            print("  OK      \(name)")
        }
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("papai-rangement-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: home) }
        let docs = home.appendingPathComponent("Documents", isDirectory: true)
        let outside = home.appendingPathComponent("Ailleurs", isDirectory: true)
        for d in [docs, outside, home.appendingPathComponent("Library/Mail"), home.appendingPathComponent("Downloads")] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        func write(_ url: URL, _ text: String) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
        func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        let names = ["facture_edf.pdf", "Contrat bail.pdf", "IMG_2041.HEIC", "Chrome.dmg", "notes"]
        for n in names { try write(docs.appendingPathComponent(n), "contenu de \(n)") }
        try write(docs.appendingPathComponent(".DS_Store"), "caché")
        try write(outside.appendingPathComponent("secret.txt"), "hors du dossier")
        try fm.createSymbolicLink(at: docs.appendingPathComponent("lien.txt"), withDestinationURL: outside.appendingPathComponent("secret.txt"))
        try fm.createSymbolicLink(at: docs.appendingPathComponent("Raccourci"), withDestinationURL: outside)
        try fm.createDirectory(at: docs.appendingPathComponent("Calculette.app/Contents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: docs.appendingPathComponent("Factures"), withIntermediateDirectories: true)
        try write(docs.appendingPathComponent("Factures/facture_edf.pdf"), "ancienne facture")

        // Demande
        verifier(Tidy.isRequest("Range mes documents"), "« Range mes documents » reconnu")
        verifier(Tidy.isRequest("peux-tu trier mes téléchargements ?"), "« trier mes téléchargements » reconnu")
        verifier(!Tidy.isRequest("ouvre mes photos de Noël"), "demande ordinaire non interceptée")
        verifier(Tidy.folder(in: "range mes documents") == .documents, "dossier Documents")
        verifier(Tidy.folder(in: "range mes Téléchargements") == .downloads, "dossier Téléchargements")
        verifier(Tidy.folder(in: "mettre de l'ordre sur mon bureau") == .desktop, "dossier Bureau")
        verifier(Tidy.folder(in: "range mes fichiers") == nil, "dossier non précisé : l'app demande")

        // Garde-fous sur l'emplacement
        verifier(Tidy.refusal(URL(fileURLWithPath: "/System/Library"), home: home) != nil, "/System refusé")
        verifier(Tidy.refusal(URL(fileURLWithPath: "/Applications/Safari.app"), home: home) != nil, "app refusée")
        verifier(Tidy.refusal(URL(fileURLWithPath: "/usr/local"), home: home) != nil, "/usr refusé")
        verifier(Tidy.refusal(home.appendingPathComponent("Library/Mail"), home: home) != nil, "~/Library refusée")
        verifier(Tidy.refusal(docs.appendingPathComponent("Calculette.app"), home: home) != nil, "app dans Documents refusée")
        verifier(Tidy.refusal(docs, home: home) == nil, "Documents accepté")
        do { _ = try Tidy.root(.desktop, home: home); verifier(false, "Bureau absent refusé") }
        catch { verifier(true, "Bureau absent refusé") }
        let fakeHome = home.appendingPathComponent("Faux", isDirectory: true)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: fakeHome.appendingPathComponent("Documents"), withDestinationURL: home.appendingPathComponent("Library"))
        do { _ = try Tidy.scan(.documents, home: fakeHome); verifier(false, "Documents qui mène à la bibliothèque refusé") }
        catch { verifier(true, "Documents qui mène à la bibliothèque refusé") }
        try fm.createSymbolicLink(at: fakeHome.appendingPathComponent("Downloads"), withDestinationURL: URL(fileURLWithPath: "/System"))
        do { _ = try Tidy.scan(.downloads, home: fakeHome); verifier(false, "Téléchargements qui mène à /System refusé") }
        catch { verifier(true, "Téléchargements qui mène à /System refusé") }

        // Lecture des noms
        let scan = try Tidy.scan(.documents, home: home)
        verifier(scan.files == ["Chrome.dmg", "Contrat bail.pdf", "facture_edf.pdf", "IMG_2041.HEIC", "notes"], "noms des fichiers lus : \(scan.files)")
        verifier(!scan.files.contains("lien.txt") && !scan.files.contains("Raccourci"), "liens symboliques écartés")
        verifier(!scan.files.contains(".DS_Store"), "fichiers cachés écartés")
        verifier(!scan.files.contains("Calculette.app") && !scan.folders.contains("Calculette.app"), "app écartée")
        verifier(scan.folders == ["Factures"], "sous-dossier existant signalé, non déplacé")
        verifier(Set(scan.payload.keys) == ["folder", "files", "folders"], "seuls des noms partent au serveur")

        // Exécution
        let journal = TidyJournal(url: home.appendingPathComponent("journal.json"))
        let moves = [
            TidyMove(from: "facture_edf.pdf", to: "Factures"),
            TidyMove(from: "Contrat bail.pdf", to: "Contrats"),
            TidyMove(from: "IMG_2041.HEIC", to: "Images"),
            TidyMove(from: "Chrome.dmg", to: "Installateurs"),
            TidyMove(from: "lien.txt", to: "Textes"),
            TidyMove(from: "../Ailleurs/secret.txt", to: "Textes"),
            TidyMove(from: "notes", to: "../Ailleurs"),
            TidyMove(from: "notes", to: "Raccourci"),
            TidyMove(from: "absent.pdf", to: "Factures"),
        ]
        let tooMany = (0...Tidy.maxFiles).map { TidyMove(from: "f\($0).txt", to: "Textes") }
        do { _ = try Tidy.execute(.documents, moves: tooMany, allowed: [], home: home, journal: journal); verifier(false, "plus de 200 déplacements refusés") }
        catch { verifier(error as? TidyError == .tooManyMoves, "plus de 200 déplacements refusés") }
        let r = try Tidy.execute(.documents, moves: moves, allowed: Set(scan.files), home: home, journal: journal)
        verifier(r.moved == 4 && r.renamed == 1 && r.skipped == 5, "4 déplacés, 1 renommé, 5 refusés : \(r)")
        verifier(read(docs.appendingPathComponent("Factures/facture_edf.pdf")) == "ancienne facture", "fichier existant jamais écrasé")
        verifier(read(docs.appendingPathComponent("Factures/facture_edf (2).pdf")) == "contenu de facture_edf.pdf", "conflit renommé « (2) »")
        verifier(read(docs.appendingPathComponent("Contrats/Contrat bail.pdf")) == "contenu de Contrat bail.pdf", "contrat rangé")
        verifier(read(outside.appendingPathComponent("secret.txt")) == "hors du dossier", "hors du dossier choisi : intact")
        verifier(!fm.fileExists(atPath: outside.appendingPathComponent("notes").path), "rien n'est sorti du dossier choisi")
        verifier(read(docs.appendingPathComponent("notes")) == "contenu de notes", "fichier refusé laissé en place")
        verifier(fm.fileExists(atPath: docs.appendingPathComponent("lien.txt").path), "lien laissé en place")
        verifier(journal.last?.moves.count == 4 && journal.last?.created.sorted() == ["Contrats", "Images", "Installateurs"], "journal local écrit")

        // Annulation
        try write(docs.appendingPathComponent("Contrat bail.pdf"), "nouveau contrat")
        let u = try Tidy.undo(home: home, journal: journal)
        verifier(u.restored == 4 && u.renamed == 1 && u.missing == 0, "4 remis en place, 1 renommé : \(u)")
        verifier(read(docs.appendingPathComponent("facture_edf.pdf")) == "contenu de facture_edf.pdf", "facture revenue")
        verifier(read(docs.appendingPathComponent("Factures/facture_edf.pdf")) == "ancienne facture", "ancienne facture conservée")
        verifier(read(docs.appendingPathComponent("Contrat bail.pdf")) == "nouveau contrat", "fichier arrivé entre-temps conservé")
        verifier(read(docs.appendingPathComponent("Contrat bail (2).pdf")) == "contenu de Contrat bail.pdf", "retour renommé « (2) » si la place est prise")
        verifier(!fm.fileExists(atPath: docs.appendingPathComponent("Contrats").path)
                 && !fm.fileExists(atPath: docs.appendingPathComponent("Images").path), "dossiers créés et vides retirés")
        verifier(fm.fileExists(atPath: docs.appendingPathComponent("Factures").path), "dossier d'origine conservé")
        verifier(journal.last == nil, "journal vidé après annulation")
        do { _ = try Tidy.undo(home: home, journal: journal); verifier(false, "rien à annuler") }
        catch { verifier(error as? TidyError == .nothingToUndo, "rien à annuler") }

        let retryFile = docs.appendingPathComponent("retry.pdf")
        try write(retryFile, "à restaurer")
        let retryScan = try Tidy.scan(.documents, home: home)
        let retryMove = TidyMove(from: "retry.pdf", to: "Images/retry.pdf")
        _ = try Tidy.execute(.documents, moves: [TidyMove(from: "retry.pdf", to: "Images")],
                             allowed: Set(retryScan.files), home: home, journal: journal)
        let movedElsewhere = outside.appendingPathComponent("retry.pdf")
        let sortedFile = docs.appendingPathComponent("Images/retry.pdf")
        try fm.moveItem(at: sortedFile, to: movedElsewhere)
        let partialUndo = try Tidy.undo(home: home, journal: journal)
        verifier(partialUndo.missing == 1 && journal.last?.moves == [retryMove],
                 "journal conservé pour le fichier non restauré")
        verifier(journal.last?.created.isEmpty == true, "dossier vidé retiré du journal")
        try fm.createDirectory(at: sortedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: movedElsewhere, to: sortedFile)
        let retryUndo = try Tidy.undo(home: home, journal: journal)
        verifier(retryUndo.restored == 1 && retryUndo.missing == 0
                 && read(retryFile) == "à restaurer" && journal.last == nil,
                 "second essai restaure le fichier et vide le journal")

        // Dossier non vide à l'annulation : jamais retiré
        let scan2 = try Tidy.scan(.documents, home: home)
        _ = try Tidy.execute(.documents, moves: [TidyMove(from: "IMG_2041.HEIC", to: "Images")], allowed: Set(scan2.files), home: home, journal: journal)
        try write(docs.appendingPathComponent("Images/ajout.jpg"), "ajouté après")
        _ = try Tidy.undo(home: home, journal: journal)
        verifier(read(docs.appendingPathComponent("Images/ajout.jpg")) == "ajouté après", "dossier non vide gardé avec son contenu")

        // Arrêt en cours de route
        let scan3 = try Tidy.scan(.documents, home: home)
        var n = 0
        let s = try Tidy.execute(.documents, moves: [TidyMove(from: "notes", to: "Textes"), TidyMove(from: "Chrome.dmg", to: "Installateurs")],
                                 allowed: Set(scan3.files), home: home, journal: journal, shouldStop: { n += 1; return n > 1 })
        verifier(s.moved == 1 && s.stopped, "Arrêter interrompt le rangement")
        _ = try Tidy.undo(home: home, journal: journal)

        // 200 fichiers au plus
        let dl = home.appendingPathComponent("Downloads")
        for i in 0..<205 { try write(dl.appendingPathComponent(String(format: "f%03d.txt", i)), "x") }
        let big = try Tidy.scan(.downloads, home: home)
        verifier(big.files.count == 200 && big.skipped == 5, "200 fichiers au plus, les autres restent")

        // Rien n'a disparu
        let all = fm.enumerator(atPath: docs.path)?.allObjects.compactMap { $0 as? String } ?? []
        for n in names { verifier(all.contains { ($0 as NSString).lastPathComponent.hasPrefix((n as NSString).deletingPathExtension) }, "toujours présent : \(n)") }
        print("\n\(total) contrôles passés, 0 échec")
    }
}
