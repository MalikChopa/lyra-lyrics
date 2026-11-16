import Testing
import Foundation
@testable import LyricsCore

@Suite("1.1.0 : choix manuel de la version (B1)")
struct ManualChoiceTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("un choix manuel ne périme pas après 24 h, un résultat automatique oui")
    func noExpiry() {
        var index = LookupIndex()
        index.record(key: "auto", outcome: .found(id: 1), now: t0)
        index.recordManual(key: "manuel", id: 42, now: t0)
        let later = t0.addingTimeInterval(LookupIndex.maxAge + 60)
        index.purge(now: later)
        #expect(index.lookup(key: "auto", now: later) == nil)
        #expect(index.manualChoice(key: "manuel") == 42)
    }

    @Test("choix manuel et résultat automatique d'une même clé coexistent ; le retour au choix automatique retire seulement le premier")
    func coexistAndRevert() {
        var index = LookupIndex()
        index.record(key: "k", outcome: .found(id: 7), now: t0)
        index.recordManual(key: "k", id: 99, now: t0)
        #expect(index.manualChoice(key: "k") == 99)
        #expect(index.lookup(key: "k", now: t0) == .found(id: 7))
        index.removeManual(key: "k")
        #expect(index.manualChoice(key: "k") == nil)
        #expect(index.lookup(key: "k", now: t0) == .found(id: 7))
        index.remove(key: "k")                         // « Réessayer » ne touche pas aux choix manuels
        index.recordManual(key: "k", id: 5, now: t0)
        index.remove(key: "k")
        #expect(index.manualChoice(key: "k") == 5)
        index.clear()
        #expect(index.count == 0)
    }

    @Test("l'index ne contient jamais de texte : clé hachée et identifiants seulement, aller-retour disque")
    func diskShape() throws {
        var index = LookupIndex()
        index.recordManual(key: String(repeating: "a", count: 64), id: 12, now: t0)
        let url = URL(fileURLWithPath: "/tmp/lyra-110/index-test-\(UUID().uuidString).json")
        try index.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let raw = try String(contentsOf: url, encoding: .utf8)
        let allowed: Set<String> = ["key", "lrclibID", "storedAt", "manual"]
        let objects = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        for o in objects { #expect(Set(o.keys).isSubset(of: allowed)) }
        #expect(LookupIndex.load(from: url).manualChoice(key: String(repeating: "a", count: 64)) == 12)
    }

    @Test("un ancien index (sans le champ manual) se relit")
    func oldIndex() throws {
        let url = URL(fileURLWithPath: "/tmp/lyra-110/index-old-\(UUID().uuidString).json")
        let json = #"[{"key":"abc","lrclibID":3,"storedAt":"2026-10-27T10:00:00Z"}]"#
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LookupIndex.load(from: url).count == 1)
    }

    @Test("un choix manuel d'une durée différente reste synchronisé ; le choix automatique la contrôle")
    func trustDuration() {
        let rec = LRCLIBRecord(id: 1, trackName: "T", artistName: "A", albumName: nil, duration: 200, instrumental: false, plainLyrics: "x", syncedLyrics: "[00:01.00] x\n[00:03.00] y")
        let track = TrackInfo(title: "T", artist: "A", duration: 140)
        #expect(LRCLIBClient.lyrics(from: rec, for: track, provenance: "p")?.isSynced == false)
        #expect(LRCLIBClient.lyrics(from: rec, for: track, provenance: "p", trustDuration: true)?.isSynced == true)
    }
}
