import Testing
import Foundation
@testable import LyricsCore

@Suite("LRCParser")
struct LRCParserTests {
    @Test("formats d'horodatage, offset, métadonnées, multi-horodatages, ligne vide, mot à mot, désordre (Fixtures/lrc/formats.lrc)")
    func formats() throws {
        let r = LRCParser.parseDetailed(try Fixtures.text("lrc/formats.lrc"))
        #expect(r.offsetMillis == 500)
        #expect(r.metadata["ar"] == "Artiste fictif")
        #expect(r.metadata["ti"] == "Formats mêlés")
        #expect(r.metadata["length"] == "01:00")
        #expect(r.metadata["offset"] == nil)
        let expected: [(Double, String)] = [
            (4.623, "Ligne au millième, placée en désordre"),      // [00:05.123] − 0,5 s, trié
            (12.0, "Ligne au centième"),
            (19.5, "Ligne sans fraction"),
            (29.6, "Ligne au dixième"),
            (39.5, "Refrain répété deux fois"),
            (44.5, "♪"),                                           // ligne vide
            (49.5, "Refrain répété deux fois"),                    // 2e horodatage de la même ligne
            (54.5, "Mot à mot"),                                   // balises <mm:ss.xx> retirées
            (62.0, "Deux-points comme séparateur"),                // [01:02:50]
            (4199.5, "Soixante-dix minutes"),                      // minutes > 59
        ]
        #expect(r.lines.count == expected.count)
        for (line, e) in zip(r.lines, expected) {
            #expect(abs(line.time - e.0) < 0.0005, "\(line)")
            #expect(line.text == e.1)
        }
        #expect(!r.lines.contains { $0.text.contains("sans horodatage") || $0.text.contains("Refrain]") })
    }

    @Test("BOM et CRLF (Fixtures/lrc/bom-crlf.lrc)")
    func bomCRLF() throws {
        let lines = LRCParser.parse(try Fixtures.text("lrc/bom-crlf.lrc"))
        #expect(lines.map(\.text) == ["Avec BOM et CRLF", "Deuxième ligne", "Espaces autour"])
        #expect(lines.map(\.time) == [1, 3, 5])
    }

    @Test("fichier vide ou corrompu → aucune ligne")
    func emptyCorrupt() throws {
        #expect(LRCParser.parse(try Fixtures.text("lrc/empty.lrc")).isEmpty)
        #expect(LRCParser.parse(try Fixtures.text("lrc/corrupt.lrc")).isEmpty)
        #expect(LRCParser.parse("[12:xx.00] mauvais").isEmpty)
    }

    @Test("offset négatif, millièmes, pas d'horodatage négatif")
    func negativeOffset() {
        let r = LRCParser.parseDetailed("[offset:-250]\n[00:00.100]Début\n[00:01.000]Suite")
        #expect(r.offsetMillis == -250)
        #expect(r.lines.map(\.time) == [0.35, 1.25])
        let clamped = LRCParser.parse("[offset:+900]\n[00:00.10]Début")
        #expect(clamped.first?.time == 0)
    }

    @Test("texte seul d'un LRC (bloc non synchronisé) sans « ♪ »")
    func plainText() {
        let lines = LRCParser.parse("[00:01.00]Un\n[00:02.00]\n[00:03.00]Deux")
        #expect(LRCParser.plainText(from: lines) == "Un\nDeux")
    }
}

@Suite("PositionEstimator + SyncEngine (horloge simulée)")
struct SyncTests {
    let lines = [LyricLine(time: 0, text: "zéro"), LyricLine(time: 5, text: "cinq"), LyricLine(time: 10, text: "dix"), LyricLine(time: 20, text: "vingt")]

    @Test("lecture : la position avance avec l'horloge ; pause : figée ; reset")
    func playPause() {
        var e = PositionEstimator()
        #expect(e.estimate(at: 100) == 0)
        #expect(e.apply(PlaybackReading(position: 10, at: 100, state: .playing)) == .initial)
        #expect(e.estimate(at: 105) == 15)
        #expect(e.isPlaying)
        e.apply(PlaybackReading(position: 15.1, at: 105.1, state: .paused))
        #expect(e.estimate(at: 120) == 15.1)
        #expect(!e.isPlaying)
        e.apply(PlaybackReading(position: 15.1, at: 130, state: .playing))
        #expect(e.estimate(at: 131) == 16.1)
        e.reset()
        #expect(!e.primed && e.estimate(at: 200) == 0)
    }

    @Test("seek (> 0,75 s) contre recalage silencieux (≤ 0,75 s)")
    func seekVsSilent() {
        var e = PositionEstimator()
        e.apply(PlaybackReading(position: 10, at: 100, state: .playing))
        #expect(e.apply(PlaybackReading(position: 15.6, at: 105, state: .playing)) == .silent)   // prédit 15, écart 0,6
        #expect(e.estimate(at: 105) == 15.6)
        #expect(e.apply(PlaybackReading(position: 40, at: 106, state: .playing)) == .seek)       // prédit 16,6
        #expect(e.apply(PlaybackReading(position: 40.2, at: 107, state: .playing)) == .seek)     // prédit 41, écart 0,8 > 0,75
        #expect(e.lastRecalibration == .seek)
    }

    @Test("avance de 0,15 s, dichotomie, avant la 1re ligne, après la dernière")
    func leadAndBounds() {
        let s = SyncEngine(lines: lines)
        #expect(s.index(at: 4.85) == 1)        // 4,85 + 0,15 = 5
        #expect(s.index(at: 4.84) == 0)
        #expect(s.index(at: -1) == -1)
        let before = s.window(index: -1)
        #expect(before.current == "♪" && before.previous == nil && before.next == "zéro")
        #expect(s.index(at: 999) == 3)
        let after = s.window(position: 999)
        #expect(after.current == "vingt" && after.next == nil && after.previous == "dix")
        let mid = s.window(position: 10)
        #expect(mid == LineWindow(index: 2, previous: "cinq", current: "dix", next: "vingt"))
        #expect(SyncEngine(lines: []).window(index: 3).current == "♪")
    }

    @Test("hystérésis : pas de retour en arrière après un recalage silencieux ; retour permis après un seek")
    func hysteresis() {
        let s = SyncEngine(lines: lines)
        #expect(s.index(at: 4.7, previous: 1, allowBackward: false) == 1)
        #expect(s.index(at: 4.7, previous: 1, allowBackward: true) == 0)
        #expect(s.index(at: 12, previous: 1, allowBackward: false) == 2)
    }

    @Test("décalage manuel : ± 5 s par pas de 0,1 s, appliqué à la position")
    func manualOffset() {
        var s = SyncEngine(lines: lines, manualOffset: 0.26)
        #expect(s.manualOffset == 0.3)
        s.manualOffset = 7; #expect(s.manualOffset == 5)
        s.manualOffset = -9; #expect(s.manualOffset == -5)
        s.manualOffset = 1.0
        #expect(s.index(at: 3.85) == 1)        // 3,85 + 0,15 + 1 = 5
        s.manualOffset = -1.0
        #expect(s.index(at: 5.84) == 0)        // 5,84 + 0,15 − 1 = 4,99
        #expect(SyncEngine.snappedOffset(-0.04) == 0)
    }

    @Test("chaîne estimateur → moteur : les instants de changement de ligne = horodatage − 0,15 s − décalage")
    func expectedInstants() {
        var e = PositionEstimator()
        e.apply(PlaybackReading(position: 0, at: 1000, state: .playing))
        let s = SyncEngine(lines: lines, manualOffset: 0)
        // ligne « dix » (10 s) attendue à t = 1000 + 10 − 0,15 = 1009,85
        #expect(s.index(at: e.estimate(at: 1009.849)) == 1)
        #expect(s.index(at: e.estimate(at: 1009.851)) == 2)
    }
}
