import Foundation

/// Choix de la bonne entrée LRCLIB (§3.2, recherche 02 §5) : normalisation des titres et artistes, score des candidats
/// de `search`, règles de durée (≤ 5 s → synchro ; 5 à 15 s → synchro quand le titre ET l'artiste correspondent (1.0.1) ;
/// au-delà → texte non synchronisé ; durée inconnue → synchro acceptée sans contrôle, délégué).
public enum TrackMatcher {
    public static let durationTolerance = 5.0
    /// 1.0.1 : un LRC dont l'écart de durée est de 5 à 15 s reste affiché synchronisé si titre et artiste correspondent (le décalage
    /// manuel du volet corrige un petit décalage) ; au-delà de 15 s, texte seul.
    public static let syncedGapLimit = 15.0

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
        return Set(parts.map { artistToken(String($0)) }.filter { !$0.isEmpty })
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
        let wanted = titleKey(track.title)
        let got = titleKey(c.title)
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
        case .far(let d): score -= abs(d) <= syncedGapLimit ? 1 : 3
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

    /// Un LRC d'écart `d` (secondes) reste-t-il affichable synchronisé ? Oui si l'écart est de 15 s au plus ET que l'artiste correspond.
    public static func syncToleratesGap(_ d: Double, artistMatches: Bool) -> Bool { artistMatches && abs(d) <= syncedGapLimit }

    /// Mode d'affichage pour un candidat retenu : instrumental ; synchro si LRC et durée proche ou inconnue (ou écart ≤ 15 s avec
    /// artiste concordant) ; sinon texte.
    public static func mode(for c: Candidate, track: TrackInfo) -> Mode {
        if c.instrumental { return .instrumental }
        if c.hasSynced, case .far(let d) = durationVerdict(track: track.duration, candidate: c.duration) {
            if syncToleratesGap(d, artistMatches: artistMatches(c.artist, track)) { return .synced }
            return .plain
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
        case .far(let d): reason += String(format: ", durée %+.0f s (> 5 s%@)", d, m == .synced ? ", toléré ≤ 15 s" : "")
        }
        return Decision(candidate: m == .none ? nil : c, mode: m, score: s, reason: reason)
    }

    // MARK: Clés de comparaison et requêtes (1.0.1)

    /// Clé de comparaison de deux titres : titre normalisé, sans accents ni ponctuation (« Where Is The Love? » = « where is the love »).
    /// Si rien ne reste (titre de ponctuation seule, ex. « ? »), le titre normalisé lui-même.
    public static func titleKey(_ raw: String) -> String {
        let n = normalizeTitle(raw)
        let folded = n.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let letters = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let key = collapse(String(letters))
        return key.isEmpty ? n : key
    }

    /// Jeton d'artiste comparable : sans accents, sans « the » initial (« The Black Eyed Peas » = « Black Eyed Peas »).
    static func artistToken(_ raw: String) -> String {
        var t = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        t = t.replacing(/^the\s+/, with: "")
        return collapse(t)
    }

    /// L'artiste du candidat recoupe-t-il celui du titre joué ? (jetons communs, ou l'un contient l'autre)
    public static func artistMatches(_ candidateArtist: String, _ track: TrackInfo) -> Bool {
        if looksLikeVideoTitle(candidateArtist) { return false }
        let wanted = artistTokens(track.artist), got = artistTokens(candidateArtist)
        if !wanted.isDisjoint(with: got) { return true }
        // « Black Eyed Peas, Justin Timberlake » contre « Black Eyed Peas » : un jeton contenu dans l'autre côté.
        return wanted.contains { w in w.count >= 3 && got.contains { g in g.count >= 3 && (g.contains(w) || w.contains(g)) } }
    }

    /// Premier artiste d'une chaîne multi-artistes (« A, B & C », « A feat. B », « A ; B », « A / B » avec espaces). « AC/DC » reste entier.
    public static func primaryArtist(_ raw: String) -> String {
        let s = raw.replacing(/\s+(feat\.?|featuring|ft\.?|with|vs\.?|x)\s+.*$/.ignoresCase(), with: "")
        let parts = s.split(separator: /\s*(,|;|\s\/\s|\s&\s|\sand\s)\s*/)
        let first = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : first
    }

    /// « The Beatles » → « Beatles » (la casse et les accents sont gardés pour la requête).
    public static func withoutThe(_ raw: String) -> String {
        let t = raw.replacing(/^the\s+/.ignoresCase(), with: "")
        return t.isEmpty ? raw : t
    }

    /// Titre pour une requête : « (feat. …) », « - Remastered 2011 », « - Radio Edit »… retirés, casse, accents et apostrophes GARDÉS
    /// (« Don't Stop Believin' » reste tel quel : `normalizeTitle` retire les apostrophes, ce qui dégrade la recherche).
    public static func queryTitle(_ raw: String) -> String {
        var s = raw.precomposedStringWithCompatibilityMapping
        s = s.replacing(/\s*[\(\[]\s*(feat\.?|featuring|ft\.?|with)\s+[^\)\]]*[\)\]]/.ignoresCase(), with: "")
        s = s.replacing(/\s+-?\s*(feat\.?|featuring|ft\.?)\s+.*$/.ignoresCase(), with: "")
        let versions = "((\\d{4}\\s+)?(re-?master(ed)?|remastered\\s+version)(\\s+\\d{4})?(\\s+version)?|single\\s+version|album\\s+version|mono\\s+version|stereo\\s+version|radio\\s+edit|bonus\\s+track)"
        if let dash = try? Regex("\\s*[-–—]\\s*\(versions)\\s*$").ignoresCase() { s = s.replacing(dash, with: "") }
        if let paren = try? Regex("\\s*[\\(\\[]\\s*\(versions)\\s*[\\)\\]]").ignoresCase() { s = s.replacing(paren, with: "") }
        let t = collapse(s)
        return t.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : t
    }

    /// Titre le plus court : en plus, tout suffixe « - … » et toute parenthèse finale retirés (« Last Friday Night (T.G.I.F.) » → « Last Friday Night »).
    public static func shortQueryTitle(_ raw: String) -> String {
        var s = queryTitle(raw)
        s = s.replacing(/\s+[-–—]\s+.*$/, with: "")
        s = s.replacing(/\s*[\(\[][^\)\]]*[\)\]]\s*$/, with: "")
        let t = collapse(s)
        return t.isEmpty ? queryTitle(raw) : t
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
