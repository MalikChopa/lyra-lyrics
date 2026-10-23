import Foundation

/// Entrée de l'index disque (D4) : clé hachée, identifiant LRCLIB ou « non trouvé » (`lrclibID == nil`), date.
/// AUCUN champ texte : ce type ne peut pas contenir de paroles, de titre ni d'artiste.
public struct LookupEntry: Codable, Sendable, Equatable {
    public var key: String
    public var lrclibID: Int?
    public var storedAt: Date
    public init(key: String, lrclibID: Int?, storedAt: Date) {
        self.key = key; self.lrclibID = lrclibID; self.storedAt = storedAt
    }
}

/// Index disque sans texte (§3.2, D4) : clé = hachage (SHA-256 salé, INJECTÉ par l'app : CryptoKit reste hors du cœur
/// portable) de (titre, artiste, durée arrondie) normalisés ; valeur = identifiant LRCLIB ou « non trouvé » ; 24 h ;
/// 500 entrées au plus. Obscurcissement léger, pas une protection (D4).
public struct LookupIndex: Sendable, Equatable {
    public static let maxAge: TimeInterval = 24 * 3600
    public static let maxEntries = 500
    public static let fileName = "lookup-index.json"

    public enum Outcome: Sendable, Equatable {
        case found(id: Int)
        case notFound
    }

    public private(set) var entries: [LookupEntry]

    public init(entries: [LookupEntry] = []) { self.entries = entries }

    public var count: Int { entries.count }

    /// Matière hachée : titre et artiste normalisés, durée arrondie à la seconde (« ? » si inconnue).
    public static func material(for track: TrackInfo) -> String {
        let duration = track.duration.map { String(Int($0.rounded())) } ?? "?"
        return [TrackMatcher.normalizeTitle(track.title), TrackMatcher.normalizeArtist(track.artist), duration].joined(separator: "\u{1F}")
    }

    public static func key(for track: TrackInfo, hasher: (String) -> String) -> String {
        hasher(material(for: track))
    }

    /// Résultat mémorisé, s'il a moins de 24 h (les entrées périmées sont retirées).
    public mutating func lookup(key: String, now: Date) -> Outcome? {
        purge(now: now)
        guard let e = entries.first(where: { $0.key == key }) else { return nil }
        return e.lrclibID.map { .found(id: $0) } ?? .notFound
    }

    public mutating func record(key: String, outcome: Outcome, now: Date) {
        entries.removeAll { $0.key == key }
        let id: Int? = { if case .found(let i) = outcome { return i } else { return nil } }()
        entries.append(LookupEntry(key: key, lrclibID: id, storedAt: now))
        purge(now: now)
        while entries.count > Self.maxEntries { entries.removeFirst() }
    }

    public mutating func purge(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.storedAt) > Self.maxAge || $0.storedAt > now.addingTimeInterval(60) }
    }

    /// « Vider le cache ».
    public mutating func clear() { entries.removeAll() }

    // MARK: Disque (seules les entrées sans texte sont encodées)

    public static func load(from url: URL) -> LookupIndex {
        guard let data = try? Data(contentsOf: url) else { return LookupIndex() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return LookupIndex(entries: (try? decoder.decode([LookupEntry].self, from: data)) ?? [])
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}
