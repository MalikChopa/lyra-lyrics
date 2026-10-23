import Foundation

/// Lecteurs pris en charge (PlayerKit).
public enum PlayerID: String, Sendable, CaseIterable {
    case spotify
    case music

    public var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }
}

public enum PlaybackState: String, Sendable, Equatable {
    case playing, paused, stopped

    /// « Playing » / « playing » / « Paused »… (notifications et AppleScript), insensible à la casse.
    public static func parse(_ text: String?) -> PlaybackState? {
        switch text?.lowercased() {
        case "playing": return .playing
        case "paused": return .paused
        case "stopped": return .stopped
        default: return nil
        }
    }
}

public struct PlayerTrack: Sendable, Equatable {
    public var name: String
    public var artist: String
    public var album: String?
    /// Durée en secondes ; facultative (Apple Music en streaming peut ne pas la donner, R01 §1).
    public var durationSeconds: Double?
    public var trackID: String?

    public init(name: String, artist: String, album: String? = nil, durationSeconds: Double? = nil, trackID: String? = nil) {
        self.name = name; self.artist = artist; self.album = album
        self.durationSeconds = durationSeconds; self.trackID = trackID
    }

    /// Clé d'identité d'un titre (changement de titre = clé différente).
    public var identity: String { trackID ?? "\(name)\u{1F}\(artist)\u{1F}\(album ?? "")" }
}

public struct PlayerReading: Sendable, Equatable {
    public var player: PlayerID
    public var state: PlaybackState
    public var positionSeconds: Double?
    public var track: PlayerTrack?
    /// Vrai si une propriété du titre a échoué (−1728 : bug du streaming Apple Music).
    public var trackUnreadable: Bool
    /// Instant monotone auquel la position est valable (milieu de l'appel AppleScript, ou réception de la notification).
    public var at: ContinuousClock.Instant?

    public init(player: PlayerID, state: PlaybackState, positionSeconds: Double?, track: PlayerTrack?,
                trackUnreadable: Bool = false, at: ContinuousClock.Instant? = nil) {
        self.player = player; self.state = state; self.positionSeconds = positionSeconds
        self.track = track; self.trackUnreadable = trackUnreadable; self.at = at
    }
}

public enum PlayerEvent: Sendable, Equatable {
    case trackChanged(PlayerReading)
    case reading(PlayerReading)
    case stopped(PlayerID)
    case permissionNeeded(PlayerID)
    case error(PlayerID, ScriptError)
}

/// Erreurs d'Apple events (codes du §3.2) + deux états internes de l'exécuteur.
public enum ScriptError: Error, Sendable, Equatable {
    case denied              // −1743 refusé
    case consentRequired     // −1744 consentement requis
    case notRunning          // −600 app non lancée (−609 connexion invalide : app quittée pendant l'envoi)
    case objectNotFound      // −1728 objet introuvable (bug streaming)
    case timedOut            // −1712 délai dépassé
    case suspended           // interne : relevés suspendus après 3 délais dépassés de suite
    case busy                // interne : un relevé est déjà en vol
    case invalidResult       // interne : résultat inattendu
    case other(Int)

    public static func from(code: Int) -> ScriptError {
        switch code {
        case -1743: return .denied
        case -1744: return .consentRequired
        case -600, -609: return .notRunning
        case -1728: return .objectNotFound
        case -1712: return .timedOut
        default: return .other(code)
        }
    }

    public var code: Int {
        switch self {
        case .denied: return -1743
        case .consentRequired: return -1744
        case .notRunning: return -600
        case .objectNotFound: return -1728
        case .timedOut: return -1712
        case .suspended, .busy, .invalidResult: return 0
        case .other(let c): return c
        }
    }
}

/// Valeur d'un résultat AppleScript, `Sendable`.
public enum ScriptValue: Sendable, Equatable {
    case string(String)
    case double(Double)
    case int(Int)
    /// Octets bruts (pochette d'Apple Music). Jamais écrits sur le disque.
    case data(Data)
    case null

    public var stringValue: String? {
        if case .string(let s) = self, !s.isEmpty { return s }
        return nil
    }
    public var dataValue: Data? {
        if case .data(let d) = self, !d.isEmpty { return d }
        return nil
    }
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }
}

/// Commandes de lecture de la barre au survol (renverse « contrôle de la lecture : hors périmètre »).
/// Codes relus dans les `.sdef` des deux lecteurs : Music `hook` + Prev/PlPs/Next ; Spotify `spfy` + Prev/PlPs/Next.
public enum PlaybackCommand: String, Sendable, CaseIterable {
    case previous, playPause, next

    /// (classe d'événement, identifiant d'événement) : 4 caractères chacun.
    public func eventCodes(for player: PlayerID) -> (eventClass: String, eventID: String) {
        let id: String
        switch self { case .previous: id = "Prev"; case .playPause: id = "PlPs"; case .next: id = "Next" }
        return (player == .music ? "hook" : "spfy", id)
    }

    /// Nom AppleScript de la commande (diagnostic, libellés).
    public var scriptName: String {
        switch self { case .previous: return "previous track"; case .playPause: return "playpause"; case .next: return "next track" }
    }

    public var accessibilityLabel: String {
        switch self { case .previous: return "Titre précédent"; case .playPause: return "Lecture ou pause"; case .next: return "Titre suivant" }
    }
}
