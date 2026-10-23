import Foundation

/// Cache mémoire des paroles (D2) : 2 entrées au plus (titre courant + précédent), jamais sur disque (`Lyrics` n'est pas
/// `Codable`), vidé à la fermeture de l'app.
public struct LyricsCache: Sendable, Equatable {
    public static let capacity = 2

    private struct Entry: Sendable, Equatable {
        var key: String
        var lyrics: Lyrics
    }
    /// Du plus ancien au plus récent.
    private var entries: [Entry] = []

    public init() {}

    public var count: Int { entries.count }
    public var keys: [String] { entries.map(\.key) }

    /// Lecture sans changer l'ordre.
    public func peek(_ key: String) -> Lyrics? { entries.first { $0.key == key }?.lyrics }

    /// Lecture qui rafraîchit l'entrée (la plus récente est gardée en priorité).
    public mutating func fetch(_ key: String) -> Lyrics? {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let e = entries.remove(at: i)
        entries.append(e)
        return e.lyrics
    }

    public mutating func store(_ lyrics: Lyrics, for key: String) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, lyrics: lyrics))
        while entries.count > Self.capacity { entries.removeFirst() }
    }

    public mutating func clear() { entries.removeAll() }
}
