import Foundation

/// Rangement guidé d'un dossier (Documents, Téléchargements ou Bureau).
///
/// Seuls les noms des fichiers partent au serveur, jamais leur contenu. Le plan
/// (un déplacement par ligne) est validé par le support comme tout plan, puis
/// exécuté ici : déplacements seulement, jamais de suppression ni d'écrasement.
/// Un journal local permet « Annuler le rangement ». Les garde-fous sont en code :
/// dossier système, bibliothèque, app, lien symbolique et plus de 200 fichiers
/// sont refusés, même si le serveur demandait autre chose.
enum TidyFolder: String, CaseIterable, Codable {
    case documents, downloads, desktop

    var label: String {
        switch self {
        case .documents: "Documents"
        case .downloads: "Téléchargements"
        case .desktop: "Bureau"
        }
    }

    /// Nom réel du dossier dans le dossier de départ.
    var directoryName: String {
        switch self {
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .desktop: "Desktop"
        }
    }
}

struct TidyMove: Codable, Equatable {
    /// Nom du fichier à la racine du dossier choisi.
    var from: String
    /// Chemin relatif au dossier choisi, après déplacement (« Factures/a (2).pdf »).
    var to: String
}

struct TidyRecord: Codable, Equatable {
    var id: String
    var folder: TidyFolder
    var date: Date
    var moves: [TidyMove]
    /// Sous-dossiers créés par ce rangement : retirés à l'annulation s'ils sont vides.
    var created: [String]
}

struct TidyScan: Equatable {
    var folder: TidyFolder
    var root: URL
    var files: [String]
    var folders: [String]
    /// Fichiers laissés de côté : liens, apps, noms cachés, au-delà de 200.
    var skipped: Int

    var payload: [String: Any] { ["folder": folder.rawValue, "files": files, "folders": folders] }
}

struct TidyResult: Equatable {
    var moved = 0
    var renamed = 0
    var skipped = 0
    var stopped = false

    var text: String {
        if moved == 0 { return "Aucun fichier déplacé." }
        var t = "\(moved) fichier\(moved > 1 ? "s" : "") rangé\(moved > 1 ? "s" : "")"
        if renamed > 0 { t += ", \(renamed) renommé\(renamed > 1 ? "s" : "") avec « (2) »" }
        if skipped > 0 { t += ", \(skipped) laissé\(skipped > 1 ? "s" : "") en place" }
        return t + (stopped ? ". Rangement arrêté." : ". Rien n'a été supprimé.")
    }
}

struct TidyUndoResult: Equatable {
    var restored = 0
    var renamed = 0
    var missing = 0
}

enum TidyError: Error, LocalizedError, Equatable {
    case folderRefused(String)
    case tooManyMoves
    case nothingToUndo

    var errorDescription: String? {
        switch self {
        case .folderRefused(let why): "Rangement refusé : \(why)."
        case .tooManyMoves: "Rangement refusé : \(Tidy.maxFiles) fichiers au plus."
        case .nothingToUndo: "Aucun rangement à annuler."
        }
    }
}

enum Tidy {
    static let maxFiles = 200
    static let maxCategories = 12

    /// Jamais rangés, même par erreur : système, apps, bibliothèques.
    static let systemPrefixes = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
                                 "/private", "/etc", "/var", "/opt", "/cores", "/Volumes", "/Network"]

    // MARK: Demande

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// « range mes documents », « trier mes téléchargements », « mettre de l'ordre sur mon bureau ».
    static func isRequest(_ text: String) -> Bool {
        let t = fold(text)
        let verb = t.range(of: #"\b(range|ranger|rangez|rangement|trie|trier|triez|classe|classer|organise|organiser|mettre de l.ordre|mets de l.ordre)\b"#,
                           options: .regularExpression) != nil
        let object = t.range(of: #"\b(documents?|telechargements?|bureau|fichiers?|dossiers?|downloads|desktop)\b"#,
                             options: .regularExpression) != nil
        return verb && object
    }

    /// Le dossier nommé dans la demande, sinon nil (l'app demande lequel).
    static func folder(in text: String) -> TidyFolder? {
        let t = fold(text)
        if t.range(of: #"\b(telechargements?|downloads)\b"#, options: .regularExpression) != nil { return .downloads }
        if t.range(of: #"\b(bureau|desktop)\b"#, options: .regularExpression) != nil { return .desktop }
        if t.range(of: #"\bdocuments?\b"#, options: .regularExpression) != nil { return .documents }
        return nil
    }

    // MARK: Garde-fous

    static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && !name.contains("/") && !name.contains("\\")
            && !name.contains("\0") && !name.hasPrefix(".") && name.trimmingCharacters(in: .whitespaces) == name
            && name.lowercased().hasSuffix(".app") == false
    }

    static func safeCategory(_ name: String) -> Bool {
        name.range(of: #"^[0-9\p{L}][0-9\p{L} '’&_-]{0,39}$"#, options: .regularExpression) != nil
            && name.trimmingCharacters(in: .whitespaces) == name
    }

    private static func real(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Raison du refus d'un emplacement, ou nil s'il peut être rangé.
    static func refusal(_ url: URL, home: URL) -> String? {
        let path = real(url)
        let homePath = real(home)
        if path.split(separator: "/").contains(where: { $0.lowercased().hasSuffix(".app") }) {
            return "une app ne se range pas"
        }
        if path == homePath + "/Library" || path.hasPrefix(homePath + "/Library/") {
            return "la bibliothèque du Mac ne se range pas"
        }
        if !(path.hasPrefix(homePath + "/")) {
            if systemPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) || path == "/" {
                return "dossier système"
            }
            return "dossier hors de votre dossier personnel"
        }
        return nil
    }

    /// Le dossier choisi, vérifié : un vrai dossier (pas un lien) parmi les trois.
    static func root(_ folder: TidyFolder, home: URL) throws -> URL {
        let url = home.appendingPathComponent(folder.directoryName, isDirectory: true)
        if let why = refusal(url, home: home) { throw TidyError.folderRefused(why) }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs?[.type] as? FileAttributeType == .typeDirectory else {
            throw TidyError.folderRefused("\(folder.label) n'est pas un dossier ordinaire")
        }
        guard real(url) == real(home) + "/" + folder.directoryName else {
            throw TidyError.folderRefused("\(folder.label) mène ailleurs")
        }
        return url
    }

    private static func type(_ url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    /// Existe, même si c'est un lien cassé (lstat, sans suivre le lien).
    private static func exists(_ url: URL) -> Bool { type(url) != nil }

    // MARK: Lecture des noms

    /// Les noms des fichiers à la racine du dossier, jamais leur contenu. Les
    /// sous-dossiers restent en place ; liens symboliques, apps et paquets sont
    /// écartés ; 200 fichiers au plus (les suivants restent où ils sont).
    static func scan(_ folder: TidyFolder, home: URL) throws -> TidyScan {
        let root = try root(folder, home: home)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var files: [String] = [], folders: [String] = [], skipped = 0
        for name in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            if name.hasPrefix(".") { continue }
            let url = root.appendingPathComponent(name)
            switch type(url) {
            case .typeRegular? where safeName(name):
                files.append(name)
            case .typeDirectory? where !name.lowercased().hasSuffix(".app"):
                if safeCategory(name) { folders.append(name) }
            default:
                skipped += 1  // lien symbolique, app, nom étrange…
            }
        }
        if files.count > maxFiles {
            skipped += files.count - maxFiles
            files = Array(files.prefix(maxFiles))
        }
        return TidyScan(folder: folder, root: root, files: files, folders: folders, skipped: skipped)
    }

    // MARK: Exécution

    /// « facture.pdf » → « facture (2).pdf », « (3) »… jusqu'à un nom libre.
    static func freeName(_ name: String, in dir: URL) -> String {
        if !exists(dir.appendingPathComponent(name)) { return name }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        for n in 2...9999 {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if !exists(dir.appendingPathComponent(candidate)) { return candidate }
        }
        return "\(base) (\(UUID().uuidString.prefix(6)))" + (ext.isEmpty ? "" : ".\(ext)")
    }

    /// Exécute les déplacements du plan validé. `allowed` : les noms lus par `scan`,
    /// seuls fichiers qu'un ordre du serveur peut déplacer.
    static func execute(_ folder: TidyFolder, moves: [TidyMove], allowed: Set<String>, home: URL,
                        journal: TidyJournal, shouldStop: () -> Bool = { false }) throws -> TidyResult {
        guard moves.count <= maxFiles else { throw TidyError.tooManyMoves }
        let root = try root(folder, home: home)
        let fm = FileManager.default
        var result = TidyResult()
        var record = TidyRecord(id: UUID().uuidString, folder: folder, date: Date(), moves: [], created: [])
        var categories: Set<String> = []
        var seen: Set<String> = []
        for move in moves {
            if shouldStop() { result.stopped = true; break }
            let target = move.to
            guard safeName(move.from), safeCategory(target), allowed.contains(move.from), !seen.contains(move.from),
                  categories.contains(target) || categories.count < maxCategories else {
                result.skipped += 1; continue
            }
            seen.insert(move.from)
            let src = root.appendingPathComponent(move.from)
            guard type(src) == .typeRegular else { result.skipped += 1; continue }
            let dir = root.appendingPathComponent(target, isDirectory: true)
            switch type(dir) {
            case .typeDirectory?:
                break
            case nil:
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: false)
                    record.created.append(target)
                } catch { result.skipped += 1; continue }
            default:
                result.skipped += 1; continue  // fichier ou lien du même nom : on n'y touche pas
            }
            guard real(dir) == real(root) + "/" + target, refusal(dir, home: home) == nil else {
                result.skipped += 1; continue
            }
            categories.insert(target)
            let name = freeName(move.from, in: dir)
            do {
                // moveItem n'écrase jamais : il échoue si la destination existe.
                try fm.moveItem(at: src, to: dir.appendingPathComponent(name))
            } catch { result.skipped += 1; continue }
            result.moved += 1
            if name != move.from { result.renamed += 1 }
            record.moves.append(TidyMove(from: move.from, to: target + "/" + name))
            journal.save(record)
        }
        if record.moves.isEmpty, !record.created.isEmpty {
            for d in record.created { rmdir(root.appendingPathComponent(d).path) }
        }
        return result
    }

    // MARK: Annulation

    /// Remet chaque fichier du dernier rangement à sa place d'origine (renommé
    /// avec « (2) » si la place a été reprise), puis retire les dossiers créés
    /// s'ils sont vides. Rien n'est supprimé.
    static func undo(home: URL, journal: TidyJournal) throws -> TidyUndoResult {
        guard var record = journal.last else { throw TidyError.nothingToUndo }
        let root = try root(record.folder, home: home)
        let fm = FileManager.default
        var result = TidyUndoResult()
        var remainingMoves: [TidyMove] = []
        for move in record.moves.reversed() {
            let parts = move.to.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, safeCategory(parts[0]), safeName(parts[1]), safeName(move.from) else {
                result.missing += 1
                remainingMoves.append(move)
                continue
            }
            let src = root.appendingPathComponent(parts[0]).appendingPathComponent(parts[1])
            guard type(root.appendingPathComponent(parts[0])) == .typeDirectory, type(src) == .typeRegular else {
                result.missing += 1
                remainingMoves.append(move)
                continue
            }
            let name = freeName(move.from, in: root)
            do {
                try fm.moveItem(at: src, to: root.appendingPathComponent(name))
                result.restored += 1
                if name != move.from { result.renamed += 1 }
            } catch {
                result.missing += 1
                remainingMoves.append(move)
            }
        }
        var remainingCreated: [String] = []
        // rmdir échoue sur un dossier non vide : rien d'autre ne peut disparaître.
        for d in record.created {
            guard safeCategory(d) else {
                remainingCreated.append(d)
                continue
            }
            let dir = root.appendingPathComponent(d)
            if type(dir) == .typeDirectory {
                rmdir(dir.path)
                if type(dir) == .typeDirectory { remainingCreated.append(d) }
            }
        }
        if remainingMoves.isEmpty && remainingCreated.isEmpty {
            journal.remove(record.id)
        } else {
            record.moves = Array(remainingMoves.reversed())
            record.created = remainingCreated
            journal.save(record)
        }
        return result
    }
}

/// Journal local des rangements, dans ~/Library/Application Support/PapAI.
final class TidyJournal {
    let url: URL

    init(url: URL) { self.url = url }

    static let standard: TidyJournal = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PapAI", isDirectory: true)
        return TidyJournal(url: dir.appendingPathComponent("rangements.json"))
    }()

    var records: [TidyRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TidyRecord].self, from: data)) ?? []
    }

    var last: TidyRecord? { records.last }

    func save(_ record: TidyRecord) {
        var all = records.filter { $0.id != record.id }
        all.append(record)
        write(Array(all.suffix(20)))
    }

    func remove(_ id: String) { write(records.filter { $0.id != id }) }

    private func write(_ all: [TidyRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(all) { try? data.write(to: url, options: .atomic) }
    }
}
