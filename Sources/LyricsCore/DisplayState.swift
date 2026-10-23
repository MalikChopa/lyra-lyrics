import Foundation

/// États affichés (§3.6), réducteur pur `reduce(état, événement) → état`. L'« En pause » du tableau est un drapeau
/// (`paused`) posé sur l'écran courant : lignes figées, barre « En pause », sortie à la reprise.
public struct DisplayState: Sendable, Equatable {
    public enum Screen: Sendable, Equatable {
        /// « Rien en lecture » (aucun lecteur, ou arrêt).
        case nothing
        /// Requête en cours ; `hint` vrai après 1,5 s (« Recherche des paroles… »).
        case searching(hint: Bool)
        /// LRC trouvé, écart de durée ≤ 5 s.
        case synced
        /// Texte seul, ou écart > 5 s : bloc défilant, mention « non synchronisées ».
        case unsynced
        /// `instrumental: true`.
        case instrumental
        /// 404, aucun candidat, budget dépassé par lenteur sans erreur.
        case unavailable
        /// Tout 429/503/délai dépassé : « Service de paroles occupé » / « Nouvel essai dans N s. » (`retryIn` ≤ 0 : les reprises
        /// automatiques sont épuisées, « Le service ne répond pas pour l'instant » ; dans les deux cas, bouton « Réessayer »).
        case busy(retryIn: Double)
        /// `NWPathMonitor` : « Hors connexion ».
        case offline
        /// −1743/−1744 côté Music ; `refused` vrai après un refus explicite (→ « Ouvrir les Réglages »).
        case permissionNeeded(refused: Bool)
        /// −1728 répétés côté Music : « Titre non lisible depuis Apple Music ».
        case unreadable

        public var name: String {
            switch self {
            case .nothing: return "nothing"
            case .searching: return "searching"
            case .synced: return "synced"
            case .unsynced: return "unsynced"
            case .instrumental: return "instrumental"
            case .unavailable: return "unavailable"
            case .busy: return "busy"
            case .offline: return "offline"
            case .permissionNeeded: return "permission"
            case .unreadable: return "unreadable"
            }
        }
    }

    public enum Event: Sendable, Equatable {
        /// Lecture détectée / changement de titre : la recherche démarre (annule l'ancienne).
        case trackChanged
        /// 1,5 s de recherche écoulées.
        case searchHintDue
        case lyricsSynced
        case lyricsUnsynced
        case instrumental
        /// 404, aucun candidat.
        case notFound
        /// Budget de 15 s dépassé par lenteur sans erreur.
        case budgetExhausted
        /// 429/503 : attente de `retryIn` secondes.
        case serviceBusy(retryIn: Double)
        /// Compte à rebours de « Service occupé » (N s restantes).
        case busyCountdown(retryIn: Double)
        /// Erreurs passagères qui durent après toutes les reprises automatiques : reste « Service occupé » (jamais « indisponible »).
        case serviceStalled
        /// Fin de l'attente ou du disjoncteur : nouvel essai pour le titre courant.
        case waitEnded
        case wentOffline
        case backOnline
        case paused
        case resumed
        /// Arrêt ou lecteur quitté.
        case stopped
        case permissionNeeded
        case permissionRefused
        case permissionGranted
        case trackUnreadable
    }

    public var screen: Screen = .nothing
    public var paused = false
    /// Un titre est en cours (sert à savoir où revenir après « Hors connexion » ou une autorisation).
    public var hasTrack = false

    public init(screen: Screen = .nothing, paused: Bool = false, hasTrack: Bool = false) {
        self.screen = screen; self.paused = paused; self.hasTrack = hasTrack
    }

    public static let initial = DisplayState()

    public static func reduce(_ state: DisplayState, _ event: Event) -> DisplayState {
        var s = state
        switch event {
        case .trackChanged:
            s.hasTrack = true
            s.paused = false
            if case .offline = s.screen { return s }                       // on attend le réseau pour ce titre
            if case .permissionNeeded = s.screen { return s }              // toujours bloqué côté Music
            s.screen = .searching(hint: false)
        case .searchHintDue:
            if case .searching(false) = s.screen { s.screen = .searching(hint: true) }
        case .lyricsSynced:
            guard s.hasTrack else { return s }
            s.screen = .synced
        case .lyricsUnsynced:
            guard s.hasTrack else { return s }
            s.screen = .unsynced
        case .instrumental:
            guard s.hasTrack else { return s }
            s.screen = .instrumental
        case .notFound, .budgetExhausted:
            guard s.hasTrack else { return s }
            s.screen = .unavailable
        case .serviceBusy(let retryIn), .busyCountdown(let retryIn):
            guard s.hasTrack else { return s }
            if case .offline = s.screen { return s }                       // hors connexion prime sur un compte à rebours
            s.screen = .busy(retryIn: max(0, retryIn))
        case .serviceStalled:
            guard s.hasTrack else { return s }
            if case .offline = s.screen { return s }
            s.screen = .busy(retryIn: 0)
        case .waitEnded:
            if case .busy = s.screen { s.screen = s.hasTrack ? .searching(hint: false) : .nothing }
        case .wentOffline:
            s.screen = .offline
        case .backOnline:
            if case .offline = s.screen { s.screen = s.hasTrack ? .searching(hint: false) : .nothing }
        case .paused:
            if s.hasTrack { s.paused = true }
        case .resumed:
            s.paused = false
        case .stopped:
            s.hasTrack = false
            s.paused = false
            if case .offline = s.screen { return s }
            s.screen = .nothing
        case .permissionNeeded:
            if case .permissionNeeded(true) = s.screen { return s }
            s.screen = .permissionNeeded(refused: false)
        case .permissionRefused:
            s.screen = .permissionNeeded(refused: true)
        case .permissionGranted:
            if case .permissionNeeded = s.screen { s.screen = s.hasTrack ? .searching(hint: false) : .nothing }
        case .trackUnreadable:
            guard s.hasTrack else { return s }
            s.screen = .unreadable
        }
        return s
    }

    /// Textes du §3.6 (titre gras, corps) ; `nil` pour les écrans à lignes (synchronisées, non synchronisées, recherche).
    public var stateText: (title: String, body: String)? {
        switch screen {
        case .nothing: return ("Rien en lecture", "Lance un titre dans Spotify ou Apple Music : ses paroles apparaîtront ici.")
        case .searching, .synced, .unsynced: return nil
        case .instrumental: return ("Morceau instrumental", "")
        case .unavailable: return ("Paroles indisponibles", "Aucune parole trouvée pour ce titre. (Remix, titre rare ou pas encore référencé.)")
        case .busy(let retryIn):
            if retryIn <= 0 { return ("Service de paroles occupé", "Le service ne répond pas pour l'instant. Réessaie dans un moment.") }
            return ("Service de paroles occupé", "Nouvel essai dans \(Int(retryIn.rounded(.up))) s.")
        case .offline: return ("Hors connexion", "Les paroles reviendront avec le réseau.")
        case .permissionNeeded(let refused):
            return ("Autorisation nécessaire", refused ? AppIdentity.permissionRefusedBody : AppIdentity.permissionBody)
        case .unreadable: return ("Titre non lisible depuis Apple Music", "Ce titre en streaming ne donne pas ses informations.")
        }
    }

    /// Texte de la barre au survol quand aucun titre n'est à afficher.
    public var barTitleWhenIdle: String? {
        if case .nothing = screen { return "Aucune lecture" }
        return nil
    }
}
