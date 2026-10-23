import Foundation

// Types échangés par le cœur portable (bloc LyricsCore). Foundation seule, tout est `Sendable`.
// Les instants sont des secondes sur une horloge monotone fournie par l'appelant (testable avec une horloge simulée).

/// Lecteur d'origine d'un titre (chaîne libre pour rester portable : « spotify », « music », « fake »…).
public struct TrackInfo: Sendable, Equatable, Hashable {
    public var title: String
    public var artist: String
    public var album: String?
    /// Durée en secondes ; inconnue côté Apple Music en streaming (R01 §1) : la synchro est alors acceptée sans contrôle (délégué).
    public var duration: Double?
    /// Identifiant côté source (« spotify:track:… », persistent ID Music) ; sert d'identité de titre quand il existe.
    public var sourceID: String?
    public var player: String

    public init(title: String, artist: String, album: String? = nil, duration: Double? = nil, sourceID: String? = nil, player: String = "") {
        self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.sourceID = sourceID; self.player = player
    }

    /// Clé d'identité (changement de titre = clé différente) : identifiant source, sinon titre + artiste + album.
    public var identity: String { sourceID.map { "\(player):\($0)" } ?? "\(title)\u{1F}\(artist)\u{1F}\(album ?? "")" }
}

/// Relevé de lecture : position en secondes, instant monotone auquel elle est valable (milieu de l'aller-retour), état.
public struct PlaybackReading: Sendable, Equatable {
    public enum State: String, Sendable, Equatable { case playing, paused, stopped }
    public var position: Double
    public var at: Double
    public var state: State

    public init(position: Double, at: Double, state: State) {
        self.position = position; self.at = at; self.state = state
    }
}

/// Une ligne horodatée (secondes).
public struct LyricLine: Sendable, Equatable, Hashable {
    public var time: Double
    public var text: String
    public init(time: Double, text: String) { self.time = time; self.text = text }
}

/// Paroles d'un titre, EN MÉMOIRE SEULEMENT (D2) : ce type n'est volontairement pas `Codable`, pour qu'aucun chemin
/// d'écriture sur disque ne puisse l'accepter (un test le vérifie).
public struct Lyrics: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case synced([LyricLine])
        /// Texte seul, ou LRC dont la durée s'écarte de plus de 5 s du titre joué (affiché en bloc défilant, « non synchronisées »).
        case plain(String)
        case instrumental
    }
    public var kind: Kind
    /// Identifiant LRCLIB (pour « Signaler un problème » et `LookupIndex`), s'il existe.
    public var lrclibID: Int?
    /// Pourquoi ce choix (diagnostic, sans texte) : « get », « search », « durée +7 s », « cache »…
    public var provenance: String

    public init(kind: Kind, lrclibID: Int? = nil, provenance: String = "") {
        self.kind = kind; self.lrclibID = lrclibID; self.provenance = provenance
    }

    public var isSynced: Bool { if case .synced = kind { return true } else { return false } }
    public var syncedLines: [LyricLine]? { if case .synced(let l) = kind { return l } else { return nil } }
    public var plainText: String? { if case .plain(let t) = kind { return t } else { return nil } }
}
