import Foundation

/// Rôle de ce Mac, déposé par le service informatique (préférence gérée `role`) :
/// - par défaut, le poste d'un employé : l'app PapAI habituelle ;
/// - `support` : le poste d'un agent du support IT (comme l'app iPhone).
/// Rien ne se choisit dans l'app. `-role support` au lancement le force (démo, rendus).
enum AppRole: String {
    case aide, support

    static let key = "role"
    static var current: AppRole { Poste.managed(key) == AppRole.support.rawValue ? .support : .aide }
}
