import SwiftUI

/// Le support propose une assistance : l’utilisateur accepte ou refuse.
struct RemoteRequestView: View {
    @Environment(AppModel.self) private var model
    let request: RemoteRequest

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                HStack(alignment: .center, spacing: 22) {
                    Text(String(request.from.prefix(1)).uppercased())
                        .font(rounded(40, .bold)).foregroundStyle(T.leaf)
                        .frame(width: 88 * CGFloat(model.textScale), height: 88 * CGFloat(model.textScale))
                        .background(Circle().fill(.white))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Pastille(texte: request.rdv ? String(localized: "C'est l'heure de votre rendez-vous") : request.ticket != nil ? String(localized: "Votre demande en attente") : String(localized: "Proposition d'aide"), ton: .violet, taille: 17)
                        Text(request.ticket != nil ? "\(request.from) est disponible pour vous aider" : "\(request.from) propose de vous aider").font(rounded(44, .bold)).tracking(-0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    if !request.task.isEmpty {
                        Text("« \(request.task) »").font(rounded(26, .medium))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .champ(T.r)
                    }
                    Text("Si vous acceptez, PapAI va regarder votre écran. Rien ne bouge avant l'accord de \(request.from), et vous pouvez arrêter à tout moment.")
                        .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 14) {
                Button { model.refuseRemote() } label: { Text("Non merci").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(filled: false, height: 78))
                    .keyboardShortcut(.cancelAction)
                Button { model.acceptRemote() } label: { Text("Oui, j'accepte").frame(maxWidth: .infinity) }
                    .buttonStyle(PillStyle(height: 78, icone: "checkmark.circle", plein: true))
                    .disabled(!model.connected)
            }
        }
    }
}

func rdvText(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: AppLangue.anglais ? "en_US" : "fr_FR")
    f.dateFormat = String(localized: "EEEE d MMMM 'à' HH:mm")
    return f.string(from: d)
}

/// La demande est partie mais aucun support n'est disponible : elle attend.
struct QueuedView: View {
    @Environment(AppModel.self) private var model
    let ticket: QueuedTicket

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                VStack(alignment: .leading, spacing: 12) {
                    Pastille(texte: "Demande n° \(ticket.number)", icone: "person.wave.2.fill", ton: .orange, taille: 17)
                    Text("Votre demande est partie").font(rounded(44, .bold)).tracking(-0.7)
                }
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    if !ticket.task.isEmpty {
                        Text("« \(ticket.task) »").font(rounded(24, .medium))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .champ(T.r)
                    }
                    if let rdv = ticket.rdv {
                        Text("Rendez-vous \(rdvText(rdv)). PapAI vous préviendra à l'heure dite.")
                            .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Personne n'est disponible pour l'instant. PapAI vous préviendra dès que \(model.helperName) sera là. Vous pouvez aussi fixer un rendez-vous.")
                            .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            ForEach([("Dans 1 heure", "1h"), (String(localized: "Demain à 9 h"), "demain9"), (String(localized: "Demain à 14 h"), "demain14")], id: \.1) { slot in
                                Button { model.scheduleTicket(slot.1) } label: { Text(slot.0) }
                                    .buttonStyle(PillStyle(filled: false, height: 56, icone: "calendar"))
                            }
                        }
                    }
                    if !ticket.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("En attendant, vous pouvez essayer :")
                                .font(rounded(19, .semibold))
                            ForEach(ticket.suggestions) { suggestion in
                                HStack(spacing: 12) {
                                    Text(suggestion.title).font(rounded(18, .medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Button(ticket.suggestionLancee == suggestion.id ? "Lancé" : "Lancer") {
                                        model.runSuggestedAutomation(suggestion, ticket: ticket.ticket)
                                    }
                                    .buttonStyle(PillStyle(filled: ticket.suggestionLancee != suggestion.id,
                                                           height: 48))
                                    .disabled(ticket.suggestionLancee != nil)
                                }
                                .padding(14).carte()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Button { model.queuedShown = false } label: { Text("D'accord").frame(maxWidth: .infinity) }
                .buttonStyle(PillStyle(height: 78, icone: "checkmark.circle", plein: true))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// La demande a déjà son ticket : encore ouvert, on le dit ; réglé, on montre la solution.
struct ExistingTicketView: View {
    @Environment(AppModel.self) private var model
    let ticket: ExistingTicket

    private var statut: String {
        switch ticket.status {
        case "en_cours": return String(localized: "Une assistance est déjà en cours sur cette demande.")
        case "rdv": return ticket.rdv.map { String(localized: "Rendez-vous \(rdvText($0)). PapAI vous préviendra à l’heure dite.") }
            ?? String(localized: "Un rendez-vous est prévu. PapAI vous préviendra à l’heure dite.")
        case "a_reprendre": return String(localized: "L’assistance s’est arrêtée avant la fin. \(model.helperName) a votre demande et va la reprendre.")
        default: return String(localized: "Elle attend un support. PapAI vous préviendra dès que \(model.helperName) sera là.")
        }
    }

    private var pastille: String {
        guard ticket.solved else { return String(localized: "Demande n° \(ticket.number)") }
        guard let at = ticket.at else { return String(localized: "Demande n° \(ticket.number) · réglée") }
        let f = DateFormatter()
        f.locale = Locale(identifier: AppLangue.anglais ? "en_US" : "fr_FR")
        f.dateFormat = "d MMMM"
        return String(localized: "Demande n° \(ticket.number) · réglée le \(f.string(from: at))")
    }

    var body: some View {
        VStack(spacing: 18) {
            Panneau {
                VStack(alignment: .leading, spacing: 12) {
                    Pastille(texte: pastille, icone: ticket.solved ? "checkmark.seal.fill" : "person.wave.2.fill",
                             ton: ticket.solved ? .vert : .orange, taille: 17)
                    Text(ticket.solved ? String(localized: "Cette demande a déjà été réglée")
                         : ticket.status == "en_cours" ? String(localized: "Cette demande est déjà en cours") : String(localized: "Vous avez déjà fait cette demande"))
                        .font(rounded(44, .bold)).tracking(-0.7)
                }
            } corps: {
                VStack(alignment: .leading, spacing: 22) {
                    if !ticket.task.isEmpty {
                        Text("« \(ticket.task) »").font(rounded(24, .medium))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .champ(T.r)
                    }
                    if ticket.solved {
                        if !ticket.note.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(ticket.by.isEmpty ? "Votre support" : ticket.by) a noté")
                                    .font(rounded(16, .semibold)).foregroundStyle(T.muted)
                                Text("« \(ticket.note) »").font(rounded(22))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !ticket.steps.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ce qui l’avait réglée").font(rounded(16, .semibold)).foregroundStyle(T.muted)
                                ForEach(Array(ticket.steps.enumerated()), id: \.offset) { i, step in
                                    Text("\(i + 1). \(step)").font(rounded(21))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Text("Si le problème est revenu, Holo peut refaire la même chose avec vous.")
                            .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(statut + String(localized: " Inutile de la refaire."))
                            .font(rounded(21)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 14) {
                Button { model.newRequest() } label: {
                    Text(ticket.solved ? String(localized: "Ce n’est pas la même demande") : String(localized: "C’est une autre demande")).frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(filled: false, height: 78))
                .disabled(!model.connected)
                if ticket.solved {
                    Button { model.retryExisting() } label: { Text("Refaire avec Holo").frame(maxWidth: .infinity) }
                        .buttonStyle(PillStyle(filled: false, height: 78, icone: "arrow.clockwise"))
                        .disabled(!model.connected)
                }
                Button { model.existing = nil } label: {
                    Text(ticket.solved ? String(localized: "C’est réglé, merci") : "D’accord").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillStyle(height: 78, icone: "checkmark.circle", plein: true))
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
