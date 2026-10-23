import Testing
import Foundation
@testable import LyricsCore
import FakeLRCLIB

/// Une ligne du §3.6 par test (déclencheur, texte, sortie).
@Suite("DisplayState (§3.6)")
struct DisplayStateTests {
    typealias S = DisplayState
    func run(_ events: [S.Event], from start: S = .initial) -> S { events.reduce(start, S.reduce) }

    @Test("Rien en lecture : état initial, arrêt ; sortie : lecture détectée → recherche")
    func nothing() {
        #expect(S.initial.screen == .nothing)
        #expect(S.initial.stateText?.title == "Rien en lecture")
        #expect(S.initial.barTitleWhenIdle == "Aucune lecture")
        let stopped = run([.trackChanged, .lyricsSynced, .stopped])
        #expect(stopped.screen == .nothing && !stopped.hasTrack && !stopped.paused)
        #expect(run([.trackChanged]).screen == .searching(hint: false))
    }

    @Test("Recherche : requête en cours, indication après 1,5 s ; sortie : résultat")
    func searching() {
        let s = run([.trackChanged, .searchHintDue])
        #expect(s.screen == .searching(hint: true))
        #expect(s.stateText == nil)
        #expect(run([.trackChanged, .searchHintDue, .lyricsSynced]).screen == .synced)
        #expect(run([.trackChanged, .lyricsSynced, .searchHintDue]).screen == .synced)      // l'indication n'écrase pas un résultat
    }

    @Test("Paroles synchronisées ; sortie : changement de titre")
    func synced() {
        #expect(run([.trackChanged, .lyricsSynced]).screen == .synced)
        #expect(run([.trackChanged, .lyricsSynced, .trackChanged]).screen == .searching(hint: false))
        #expect(run([.lyricsSynced]).screen == .nothing)                                   // résultat sans titre : ignoré
    }

    @Test("Paroles non synchronisées (texte seul ou écart > 5 s) ; sortie : changement de titre")
    func unsynced() {
        #expect(run([.trackChanged, .lyricsUnsynced]).screen == .unsynced)
        #expect(run([.trackChanged, .lyricsUnsynced, .trackChanged]).screen == .searching(hint: false))
    }

    @Test("En pause : lignes figées (écran inchangé), drapeau ; sortie : reprise")
    func paused() {
        let p = run([.trackChanged, .lyricsSynced, .paused])
        #expect(p.paused && p.screen == .synced)
        #expect(!run([.trackChanged, .lyricsSynced, .paused, .resumed]).paused)
        #expect(!run([.paused]).paused)                                                     // sans titre : rien à figer
        #expect(!run([.trackChanged, .lyricsSynced, .paused, .trackChanged]).paused)
    }

    @Test("Instrumental ; sortie : changement de titre")
    func instrumental() {
        #expect(run([.trackChanged, .instrumental]).screen == .instrumental)
        #expect(run([.trackChanged, .instrumental]).stateText?.title == "Morceau instrumental")
        #expect(run([.trackChanged, .instrumental, .trackChanged]).screen == .searching(hint: false))
    }

    @Test("Paroles indisponibles : 404 / aucun candidat / budget dépassé par lenteur ; sortie : changement de titre")
    func unavailable() {
        #expect(run([.trackChanged, .notFound]).screen == .unavailable)
        #expect(run([.trackChanged, .budgetExhausted]).screen == .unavailable)
        #expect(run([.trackChanged, .notFound]).stateText?.title == "Paroles indisponibles")
        #expect(run([.trackChanged, .notFound, .trackChanged]).screen == .searching(hint: false))
    }

    @Test("Service occupé : tout 429/503 dès le premier, compte à rebours ; sortie : fin de l'attente → nouvel essai")
    func busy() {
        let b = run([.trackChanged, .serviceBusy(retryIn: 3.2)])
        #expect(b.screen == .busy(retryIn: 3.2))
        #expect(b.stateText?.title == "Service de paroles occupé")
        #expect(b.stateText?.body == "Nouvel essai dans 4 s.")
        #expect(run([.trackChanged, .serviceBusy(retryIn: 3), .busyCountdown(retryIn: 1)]).screen == .busy(retryIn: 1))
        #expect(run([.trackChanged, .serviceBusy(retryIn: 3), .waitEnded]).screen == .searching(hint: false))
        #expect(run([.trackChanged, .serviceBusy(retryIn: 3), .stopped, .waitEnded]).screen == .nothing)
    }

    @Test("Hors connexion ; sortie : réseau revenu → recherche du titre courant")
    func offline() {
        let o = run([.trackChanged, .lyricsSynced, .wentOffline])
        #expect(o.screen == .offline && o.stateText?.title == "Hors connexion")
        #expect(run([.wentOffline, .trackChanged]).screen == .offline)                        // un nouveau titre attend le réseau
        #expect(run([.wentOffline, .trackChanged, .backOnline]).screen == .searching(hint: false))
        #expect(run([.wentOffline, .backOnline]).screen == .nothing)
        #expect(run([.wentOffline, .trackChanged, .stopped]).screen == .offline)
        #expect(run([.trackChanged, .wentOffline, .serviceBusy(retryIn: 3)]).screen == .offline)   // un compte à rebours n'écrase pas « Hors connexion »
    }

    @Test("Autorisation nécessaire (Music) : bouton Autoriser, puis Ouvrir les Réglages si refusé ; sortie : autorisation")
    func permission() {
        let p = run([.trackChanged, .permissionNeeded])
        #expect(p.screen == .permissionNeeded(refused: false))
        #expect(p.stateText?.title == "Autorisation nécessaire")
        let r = run([.trackChanged, .permissionNeeded, .permissionRefused])
        #expect(r.screen == .permissionNeeded(refused: true))
        #expect(r.stateText?.body.contains("Réglages") == true)
        #expect(run([.trackChanged, .permissionNeeded, .permissionRefused, .permissionNeeded]).screen == .permissionNeeded(refused: true))
        #expect(run([.trackChanged, .permissionNeeded, .trackChanged]).screen == .permissionNeeded(refused: false))
        #expect(run([.trackChanged, .permissionNeeded, .permissionGranted]).screen == .searching(hint: false))
        #expect(run([.permissionNeeded, .permissionGranted]).screen == .nothing)
    }

    @Test("Titre illisible (−1728 répétés) ; sortie : titre suivant")
    func unreadable() {
        let u = run([.trackChanged, .trackUnreadable])
        #expect(u.screen == .unreadable && u.stateText?.title == "Titre non lisible depuis Apple Music")
        #expect(run([.trackChanged, .trackUnreadable, .trackChanged]).screen == .searching(hint: false))
    }
}

@Suite("LyricsCache (2 entrées, mémoire)")
struct LyricsCacheTests {
    func lyrics(_ s: String) -> Lyrics { Lyrics(kind: .plain(s), provenance: "test") }

    @Test("au plus 2 entrées, la plus ancienne sort ; fetch rafraîchit ; clear")
    func capacity() {
        var c = LyricsCache()
        c.store(lyrics("a"), for: "a"); c.store(lyrics("b"), for: "b"); c.store(lyrics("c"), for: "c")
        #expect(c.count == 2 && c.keys == ["b", "c"])
        #expect(c.peek("a") == nil)
        #expect(c.fetch("b")?.plainText == "b")
        #expect(c.keys == ["c", "b"])
        c.store(lyrics("d"), for: "d")
        #expect(c.keys == ["b", "d"])
        c.store(lyrics("b2"), for: "b")
        #expect(c.keys == ["d", "b"] && c.peek("b")?.plainText == "b2")
        c.clear()
        #expect(c.count == 0)
    }
}

@Suite("LookupIndex (disque, sans texte)")
struct LookupIndexTests {
    /// Hachage de test injecté (le vrai est un SHA-256 salé fourni par l'app).
    static let hasher: @Sendable (String) -> String = { "h" + String($0.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }, radix: 16) }
    let track = TrackInfo(title: "Phares sur la mer", artist: "Artiste fictif", duration: 120.4)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("clé = hachage de (titre, artiste, durée arrondie) normalisés ; identifiant ou non trouvé ; 24 h ; 500 entrées")
    func rules() {
        #expect(LookupIndex.material(for: track) == "phares sur la mer\u{1F}artiste fictif\u{1F}120")
        #expect(LookupIndex.material(for: TrackInfo(title: "X", artist: "Y")) == "x\u{1F}y\u{1F}?")
        let key = LookupIndex.key(for: track, hasher: Self.hasher)
        #expect(key == LookupIndex.key(for: TrackInfo(title: "PHARES SUR LA MER - Remastered 2031", artist: "Artiste  fictif", duration: 119.6), hasher: Self.hasher))
        var i = LookupIndex()
        #expect(i.lookup(key: key, now: now) == nil)
        i.record(key: key, outcome: .found(id: 101), now: now)
        #expect(i.lookup(key: key, now: now.addingTimeInterval(23 * 3600)) == .found(id: 101))
        #expect(i.lookup(key: key, now: now.addingTimeInterval(24 * 3600 + 1)) == nil)
        #expect(i.count == 0)
        i.record(key: "nf", outcome: .notFound, now: now)
        #expect(i.lookup(key: "nf", now: now) == .notFound)
        for n in 0..<501 { i.record(key: "k\(n)", outcome: .found(id: n), now: now.addingTimeInterval(Double(n))) }
        #expect(i.count == 500)
        #expect(i.lookup(key: "nf", now: now.addingTimeInterval(600)) == nil)             // la plus ancienne est partie
        #expect(i.lookup(key: "k500", now: now.addingTimeInterval(600)) == .found(id: 500))
        i.clear()
        #expect(i.count == 0)
    }

    @Test("aller-retour disque ; le fichier ne contient ni titre ni artiste")
    func disk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pf-lookup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(LookupIndex.fileName)
        var i = LookupIndex()
        i.record(key: LookupIndex.key(for: track, hasher: Self.hasher), outcome: .found(id: 101), now: now)
        i.record(key: "autre", outcome: .notFound, now: now)
        try i.save(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.lowercased().contains("phares") && !text.lowercased().contains("fictif"))
        #expect(text.contains("\"lrclibID\":101"))
        var back = LookupIndex.load(from: url)
        #expect(back.count == 2)
        #expect(back.lookup(key: LookupIndex.key(for: track, hasher: Self.hasher), now: now) == .found(id: 101))
        #expect(LookupIndex.load(from: dir.appendingPathComponent("absent.json")).count == 0)
    }
}

@Suite("FakeLRCLIBEngine (Fixtures/lrclib/catalog.json)")
struct FakeEngineTests {
    func engine() throws -> FakeLRCLIBEngine {
        FakeLRCLIBEngine(catalog: try FakeLRCLIBEngine.loadCatalog(at: Fixtures.url("lrclib/catalog.json").path))
    }
    func json(_ r: FakeLRCLIBEngine.Response) -> Any? { try? JSONSerialization.jsonObject(with: r.body) }

    @Test("200 exact (durée ± 2 s), 404, get/{id}, search, instrumental, texte seul")
    func routes() throws {
        let e = try engine()
        let ok = e.handle(method: "GET", rawTarget: "/api/get?track_name=Phares%20sur%20la%20mer&artist_name=Artiste%20fictif&duration=121")
        #expect(ok.status == 200)
        #expect((json(ok) as? [String: Any])?["id"] as? Int == 101)
        #expect(((json(ok) as? [String: Any])?["syncedLyrics"] as? String)?.hasPrefix("[00:00.00]") == true)
        #expect(e.handle(method: "GET", rawTarget: "/api/get?track_name=Phares%20sur%20la%20mer&artist_name=Artiste%20fictif&duration=130").status == 404)
        let nf = e.handle(method: "GET", rawTarget: "/api/get?track_name=Silence%20en%20do%20majeur&artist_name=Trio%20imaginaire")
        #expect(nf.status == 404 && (json(nf) as? [String: Any])?["name"] as? String == "TrackNotFound")
        #expect(e.handle(method: "GET", rawTarget: "/api/get/106").status == 200)
        #expect(e.handle(method: "GET", rawTarget: "/api/get/999").status == 404)
        let search = e.handle(method: "GET", rawTarget: "/api/search?track_name=horloge&artist_name=Artiste")
        #expect(search.status == 200)
        #expect((json(search) as? [[String: Any]])?.count == 1)
        #expect((json(e.handle(method: "GET", rawTarget: "/api/search?track_name=inconnu")) as? [[String: Any]])?.isEmpty == true)
        let inst = json(e.handle(method: "GET", rawTarget: "/api/get?track_name=Vent%20instrumental&artist_name=Trio%20imaginaire")) as? [String: Any]
        #expect(inst?["instrumental"] as? Bool == true && inst?["syncedLyrics"] is NSNull)
        let plain = json(e.handle(method: "GET", rawTarget: "/api/get?track_name=Brume%20sans%20horloge&artist_name=Duo%20fictif")) as? [String: Any]
        #expect(plain?["syncedLyrics"] is NSNull && (plain?["plainLyrics"] as? String)?.isEmpty == false)
        #expect(e.handle(method: "POST", rawTarget: "/api/get").status == 405)
    }

    @Test("comportements : 429 + Retry-After une fois puis 200, 503 toujours, lenteur ; journal et remise à zéro")
    func behaviours() throws {
        let e = try engine()
        let first = e.handle(method: "GET", rawTarget: "/api/get?track_name=Occup%C3%A9%20trois%20secondes&artist_name=Artiste%20fictif&duration=100")
        #expect(first.status == 429)
        #expect(first.headers.contains { $0.0 == "Retry-After" && $0.1 == "3" })
        let second = e.handle(method: "GET", rawTarget: "/api/get?track_name=Occup%C3%A9%20trois%20secondes&artist_name=Artiste%20fictif&duration=100")
        #expect(second.status == 200)
        for _ in 0..<3 { #expect(e.handle(method: "GET", rawTarget: "/api/get?track_name=Panne%20en%20s%C3%A9rie&artist_name=A").status == 503) }
        let slow = e.handle(method: "GET", rawTarget: "/api/search?track_name=lenteur%20de%20plomb&artist_name=A")
        #expect(slow.status == 200 && slow.delay == 7.8)
        let log = e.requestLog
        #expect(log.count == 6 && log[0].status == 429 && log[1].status == 200 && log[5].delay == 7.8)
        #expect(log[0].query["track_name"] == "Occupé trois secondes")
        let logData = e.handle(method: "GET", rawTarget: "/_fake/log")
        #expect((json(logData) as? [[String: Any]])?.count == 6)
        #expect(e.handle(method: "GET", rawTarget: "/_fake/reset").status == 200)
        #expect(e.requestLog.isEmpty)
        #expect(e.handle(method: "GET", rawTarget: "/api/get?track_name=Occup%C3%A9%20trois%20secondes&artist_name=Artiste%20fictif&duration=100").status == 429)
        #expect(e.handle(method: "GET", rawTarget: "/_fake/quit").shouldQuit)
    }
}
