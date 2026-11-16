import Testing
import Foundation
@testable import LyricsCore

/// Fixtures INVENTÉES du dossier `Fixtures/` (chemin résolu depuis ce fichier source).
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    static func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    static func text(_ relative: String) throws -> String { try String(contentsOf: url(relative), encoding: .utf8) }
    static func data(_ relative: String) throws -> Data { try Data(contentsOf: url(relative)) }
}

@Suite("LyricsCore J0")
struct LyricsCoreTests {
    @Test("formatPosition formate mm:ss")
    func formatPosition() {
        #expect(LyricsCore.formatPosition(0) == "00:00")
        #expect(LyricsCore.formatPosition(75.9) == "01:15")
        #expect(LyricsCore.formatPosition(-3) == "00:00")
    }
}

@Suite("Droits : types sans texte sur disque (D2)")
struct PrivacyTypeTests {
    @Test("Lyrics et LRCLIBRecord ne sont ni Encodable ni Decodable")
    func lyricsNotCodable() {
        let lyrics: Any.Type = Lyrics.self
        #expect(!(lyrics is any Encodable.Type))
        #expect(!(lyrics is any Decodable.Type))
        let record: Any.Type = LRCLIBRecord.self
        #expect(!(record is any Encodable.Type))
        #expect(!(record is any Decodable.Type))
    }

    @Test("LookupEntry : clé hachée, identifiant, date et (1.1.0) un indicateur booléen de choix manuel ; aucun champ texte")
    func lookupEntryShape() {
        let entry = LookupEntry(key: "abc", lrclibID: 7, storedAt: Date(timeIntervalSince1970: 0))
        let labels = Mirror(reflecting: entry).children.compactMap(\.label)
        #expect(labels == ["key", "lrclibID", "storedAt", "manual"])
        // le seul champ ajouté en 1.1.0 est un Bool? : aucun type texte ne peut s'y glisser
        #expect(Mirror(reflecting: entry).children.filter { $0.value is String }.map(\.label) == ["key"])
        #expect(LookupEntry.self is any Codable.Type)
    }
}
