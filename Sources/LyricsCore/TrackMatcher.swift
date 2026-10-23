import Foundation

/// Choix de la bonne entrée LRCLIB (§3.2, recherche 02 §5) : normalisation des titres et artistes, score des candidats
/// de `search`, règles de durée (≤ 5 s → synchro ; > 5 s → texte non synchronisé ; durée inconnue → synchro acceptée
/// sans contrôle, délégué).
public enum TrackMatcher {
    public static let durationTolerance = 5.0

    public struct Candidate: Sendable, Equatable, Hashable {
        public var id: Int
        public var title: String
        public var artist: String
        public var album: String?
        public var duration: Double?
        public var instrumental: Bool
        public var hasSynced: Bool
        public var hasPlain: Bool
        public init(id: Int, title: String, artist: String, album: String? = nil, duration: Double? = nil,
                    instrumental: Bool = false, hasSynced: Bool = false, hasPlain: Bool = false) {
            self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = duration
            self.instrumental = instrumental; self.hasSynced = hasSynced; self.hasPlain = hasPlain
        }
    }

    public enum Mode: String, Sendable, Equatable { case synced, plain, instrumental, none }

    public struct Decision: Sendable, Equatable {
        public var candidate: Candidate?
        public var mode: Mode
        public var score: Double
        /// Explication courte (diagnostic, sans texte de paroles).
        public var reason: String
    }

    public enum DurationVerdict: Sendable, Equatable {
        case unknown                 // l'une des deux durées manque
        case close(Double)           // |écart| ≤ 5 s
        case far(Double)             // |écart| > 5 s
    }

    // MARK: Normalisation

    /// NFKC, minuscules, « & » → « and », guillemets retirés, « (feat. …) » / « feat. … » retirés, suffixes
    /// « - Remastered 20xx », « - 20xx Remaster », « - Single Version », « - Album Version », « (Remastered) » retirés ;
    /// « Live » et « Remix » conservés ; espaces resserrés.
    public static func normalizeTitle(_ raw: String) -> String {
        var s = basic(raw)
        // (feat. X) / [feat. X] / (featuring X) / (ft. X) / (with X)
        s = s.replacing(/\s*[\(\[]\s*(feat\.?|featuring|ft\.?|with)\s+[^\)\]]*[\)\]]/, with: "")
        // « titre feat. X » sans parenthèses, « titre - feat. X »
        s = s.replacing(/\s+-?\s*(feat\.?|featuring|ft\.?)\s+.*$/, with: "")
        // suffixes de version, après un tiret (fin de titre) ou entre parenthèses/crochets
        s = s.replacing(/\s*[-–—]\s*((\d{4}\s+)?(re-?master(ed)?|remastered\s+version)(\s+\d{4})?(\s+version)?|single\s+version|album\s+version|mono\s+version|stereo\s+version|radio\s+edit|bonus\s+track)\s*$/, with: "")
        s = s.replacing(/\s*[\(\[]\s*((\d{4}\s+)?(re-?master(ed)?|remastered\s+version)(\s+\d{4})?(\s+version)?|single\s+version|album\s+version|mono\s+version|stereo\s+version|radio\s+edit|bonus\s+track)\s*[\)\]]/, with: "")
        return collapse(s)
    }

    /// NFKC, minuscules, « & » → « and », guillemets retirés, espaces resserrés (les séparateurs d'artistes sont gardés).
    public static func normalizeArtist(_ raw: String) -> String { collapse(basic(raw)) }

    /// Artistes séparés (« a / b », « a, b », « a & b », « a x b », « a feat. b ») → jetons normalisés.
    public static func artistTokens(_ raw: String) -> Set<String> {
        let s = normalizeArtist(raw)
        let parts = s.split(separator: /\s*(\/|,|;|\+|\band\b|\bx\b|\bfeat\.?\b|\bfeaturing\b|\bft\.?\b|\bvs\.?\b)\s*/)
        return Set(parts.map { collapse(String($0)) }.filter { !$0.isEmpty })
    }

    /// Entrée bruitée dont « l'artiste » ressemble à un titre de vidéo (« Official Video », « Lyrics », « | », « 4K »…).
    public static func looksLikeVideoTitle(_ artist: String) -> Bool {
        let s = normalizeArtist(artist)
        if s.count > 60 || s.contains("|") { return true }
        return s.contains(/\b(official|video|lyrics?|mv|hd|4k|youtube|vevo|audio|visualizer|clip officiel)\b/)
    }

    public static func durationVerdict(track: Double?, candidate: Double?) -> DurationVerdict {
        guard let t = track, let c = candidate, t > 0, c > 0 else { return .unknown }
        let delta = c - t
        return abs(delta) <= durationTolerance ? .close(delta) : .far(delta)
    }

    // MARK: Score et choix

    /// Score d'un candidat ; `nil` = inéligible (titre sans rapport).
    public static func score(_ c: Candidate, for track: TrackInfo) -> Double? {
        let wanted = normalizeTitle(track.title)
        let got = normalizeTitle(c.title)
        var score = 0.0
        if wanted == got {
            score += 10
        } else if wanted.count >= 3, got.count >= 3, got.contains(wanted) || wanted.contains(got) {
            score += 4
        } else {
            return nil
        }
        let wantedArtists = artistTokens(track.artist)
        let gotArtists = artistTokens(c.artist)
        if looksLikeVideoTitle(c.artist) {
            score -= 6
        } else if !wantedArtists.isDisjoint(with: gotArtists) {
            score += 5
        } else {
            score -= 4
        }
        switch durationVerdict(track: track.duration, candidate: c.duration) {
        case .unknown: break
        case .close(let d): score += abs(d) <= 2 ? 6 : 4
        case .far: score -= 3
        }
        if let a = track.album, let b = c.album, !a.isEmpty, normalizeTitle(a) == normalizeTitle(b) { score += 2 }
        if c.instrumental {
            score += 0
        } else if c.hasSynced {
            score += 3
        } else if c.hasPlain {
            score += 1
        } else {
            score -= 5
        }
        return score
    }

    /// Mode d'affichage pour un candidat retenu : instrumental ; synchro si LRC et durée proche ou inconnue ; sinon texte.
    public static func mode(for c: Candidate, track: TrackInfo) -> Mode {
        if c.instrumental { return .instrumental }
        if c.hasSynced, case .far = durationVerdict(track: track.duration, candidate: c.duration) {
            return c.hasPlain || c.hasSynced ? .plain : .none
        }
        if c.hasSynced { return .synced }
        if c.hasPlain { return .plain }
        return .none
    }

    public static func choose(for track: TrackInfo, among candidates: [Candidate]) -> Decision {
        var best: (Candidate, Double)? = nil
        for c in candidates {
            guard let s = score(c, for: track) else { continue }
            if let (b, bs) = best {
                let closer = abs(delta(c, track)) < abs(delta(b, track))
                if s > bs || (s == bs && (closer || (abs(delta(c, track)) == abs(delta(b, track)) && c.id < b.id))) { best = (c, s) }
            } else {
                best = (c, s)
            }
        }
        guard let (c, s) = best else {
            return Decision(candidate: nil, mode: .none, score: 0, reason: candidates.isEmpty ? "aucun candidat" : "aucun titre compatible")
        }
        let m = mode(for: c, track: track)
        var reason = "id \(c.id), score \(Int(s))"
        switch durationVerdict(track: track.duration, candidate: c.duration) {
        case .unknown: reason += ", durée inconnue"
        case .close(let d): reason += String(format: ", durée %+.0f s", d)
        case .far(let d): reason += String(format: ", durée %+.0f s (> 5 s)", d)
        }
        return Decision(candidate: m == .none ? nil : c, mode: m, score: s, reason: reason)
    }

    // MARK: Détails

    private static func delta(_ c: Candidate, _ t: TrackInfo) -> Double {
        guard let a = c.duration, let b = t.duration else { return 1e9 }
        return a - b
    }

    private static func basic(_ raw: String) -> String {
        var s = raw.precomposedStringWithCompatibilityMapping.lowercased()
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacing(/["'’‘“”`´]/, with: "")
        return s
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
