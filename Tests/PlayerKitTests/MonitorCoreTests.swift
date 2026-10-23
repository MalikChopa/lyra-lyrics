import Foundation
import Testing
@testable import PlayerKit

// Valeurs INVENTÉES (D10). Horloge simulée : aucun minuteur, aucun lecteur.

@Suite("NowPlayingMonitor : arbitrage et anti-rebond (J4)")
struct MonitorCoreTests {
    static let t0 = ContinuousClock.now

    static func reading(_ p: PlayerID, _ state: PlaybackState = .playing, id: String = "a", position: Double = 3) -> PlayerReading {
        PlayerReading(player: p, state: state, positionSeconds: position,
                      track: PlayerTrack(name: "Titre \(id)", artist: "Artiste", album: nil, durationSeconds: 200, trackID: id))
    }
    static func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }
    static func ids(_ events: [PlayerEvent]) -> [String] {
        events.map {
            switch $0 {
            case .trackChanged(let r): return "T:\(r.player.rawValue):\(r.track?.trackID ?? "-")"
            case .reading(let r): return "R:\(r.player.rawValue):\(r.track?.trackID ?? "-"):\(r.state.rawValue)"
            case .stopped(let p): return "S:\(p.rawValue)"
            case .permissionNeeded(let p): return "P:\(p.rawValue)"
            case .error(let p, _): return "E:\(p.rawValue)"
            }
        }
    }

    @Test("changement de titre : émis après 600 ms de calme, pas avant")
    func debounce() {
        var m = MonitorCore()
        #expect(m.handle(.trackChanged(Self.reading(.spotify)), at: Self.at(0)).isEmpty)
        #expect(m.nextDeadline == Self.at(600))
        #expect(m.flushDue(at: Self.at(599)).isEmpty)
        #expect(Self.ids(m.flushDue(at: Self.at(600))) == ["T:spotify:a"])
        #expect(m.nextDeadline == nil)
    }

    @Test("deux changements rapprochés : seul le dernier sort, l'attente repart")
    func lastWins() {
        var m = MonitorCore()
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "a")), at: Self.at(0))
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "b")), at: Self.at(400))
        #expect(m.flushDue(at: Self.at(700)).isEmpty)
        #expect(Self.ids(m.flushDue(at: Self.at(1000))) == ["T:spotify:b"])
    }

    @Test("relevés : immédiats hors anti-rebond, mis en file dans l'ordre pendant")
    func readingsOrder() {
        var m = MonitorCore()
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "a")), at: Self.at(0))
        _ = m.flushDue(at: Self.at(600))
        #expect(Self.ids(m.handle(.reading(Self.reading(.spotify, id: "a", position: 5)), at: Self.at(700))) == ["R:spotify:a:playing"])
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "b")), at: Self.at(800))
        #expect(m.handle(.reading(Self.reading(.spotify, id: "b", position: 1)), at: Self.at(900)).isEmpty)
        #expect(Self.ids(m.flushDue(at: Self.at(1400))) == ["T:spotify:b", "R:spotify:b:playing"])
    }

    @Test("deux lecteurs : le plus récent à passer en lecture gagne, l'autre est ignoré")
    func mostRecentWins() {
        var m = MonitorCore()
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "s1")), at: Self.at(0))
        _ = m.flushDue(at: Self.at(600))
        #expect(m.active == .spotify)
        _ = m.handle(.trackChanged(Self.reading(.music, id: "m1")), at: Self.at(5000))
        #expect(m.active == .music)
        #expect(Self.ids(m.flushDue(at: Self.at(5600))) == ["T:music:m1"])
        // Spotify continue de lire : ses relevés n'écrasent pas Music.
        #expect(m.handle(.reading(Self.reading(.spotify, id: "s1", position: 40)), at: Self.at(6000)).isEmpty)
        #expect(m.handle(.trackChanged(Self.reading(.spotify, id: "s2")), at: Self.at(6100)).isEmpty)
        #expect(m.nextDeadline == nil)
        #expect(Self.ids(m.handle(.reading(Self.reading(.music, id: "m1", position: 9)), at: Self.at(6200))) == ["R:music:m1:playing"])
    }

    @Test("le lecteur actif se met en pause pendant que l'autre joue : l'autre prend la main")
    func fallBackToOther() {
        var m = MonitorCore()
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "s1")), at: Self.at(0))
        _ = m.flushDue(at: Self.at(600))
        _ = m.handle(.trackChanged(Self.reading(.music, id: "m1")), at: Self.at(1000))
        _ = m.flushDue(at: Self.at(1600))
        #expect(m.handle(.reading(Self.reading(.music, .paused, id: "m1")), at: Self.at(2000)).isEmpty)
        #expect(m.active == .spotify)
        #expect(Self.ids(m.flushDue(at: Self.at(2600))) == ["T:spotify:s1"])
    }

    @Test("pause du seul lecteur : relevé transmis ; arrêt : stopped")
    func pauseAndStop() {
        var m = MonitorCore()
        _ = m.handle(.trackChanged(Self.reading(.music, id: "m1")), at: Self.at(0))
        _ = m.flushDue(at: Self.at(600))
        #expect(Self.ids(m.handle(.reading(Self.reading(.music, .paused, id: "m1")), at: Self.at(1000))) == ["R:music:m1:paused"])
        #expect(Self.ids(m.handle(.stopped(.music), at: Self.at(2000))) == ["S:music"])
    }

    @Test("statut : « Autorisation nécessaire » de Music ne masque pas Spotify en cours")
    func statusRules() {
        var m = MonitorCore()
        #expect(Self.ids(m.handle(.permissionNeeded(.music), at: Self.at(0))) == ["P:music"])   // personne n'est actif
        _ = m.handle(.trackChanged(Self.reading(.spotify, id: "s1")), at: Self.at(100))
        _ = m.flushDue(at: Self.at(700))
        #expect(m.handle(.permissionNeeded(.music), at: Self.at(800)).isEmpty)
        #expect(m.handle(.error(.music, .objectNotFound), at: Self.at(900)).isEmpty)
        #expect(Self.ids(m.handle(.error(.spotify, .timedOut), at: Self.at(1000))) == ["E:spotify"])
    }
}
