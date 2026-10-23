import Testing
import Foundation
@testable import LyricsCore

/// Horloge simulée : seule l'attente (`sleep`) la fait avancer ; les requêtes du faux transport sont instantanées.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 0.0
    var now: Double { lock.withLock { t } }
    func advance(_ s: Double) { lock.withLock { t += max(0, s) } }
}

/// Faux LRCLIB piloté par une fermeture : reçoit la requête (chemin, paramètres, instant simulé) et rend une réponse ou une erreur.
final class ScriptedTransport: LRCLIBTransport, @unchecked Sendable {
    struct Call: Equatable { var path: String; var query: [String: String]; var at: Double }
    enum Reply { case http(Int, headers: [String: String], body: Data), error(LRCLIBError) }

    private let lock = NSLock()
    private(set) var calls: [Call] = []
    private let clock: VirtualClock
    private let handler: @Sendable (Call, Int) -> Reply

    /// `handler(appel, numéro de l'appel pour ce chemin, à partir de 1)`.
    init(clock: VirtualClock, handler: @escaping @Sendable (Call, Int) -> Reply) { self.clock = clock; self.handler = handler }

    func send(_ request: URLRequest, timeout: Double) async throws -> HTTPResponse {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let call = Call(path: url.path, query: Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a }), at: clock.now)
        let nth: Int = lock.withLock { calls.append(call); return calls.filter { $0.path == call.path }.count }
        switch handler(call, nth) {
        case .http(let status, let headers, let body): return HTTPResponse(status: status, headers: headers, body: body)
        case .error(let e): throw e
        }
    }

    var paths: [String] { lock.withLock { calls.map(\.path) } }
    func calls(to path: String) -> [Call] { lock.withLock { calls.filter { $0.path == path } } }
}

enum Wire {
    static func record(id: Int, title: String, artist: String, album: String = "Album fictif", duration: Double = 200,
                       synced: Bool = true, plain: Bool = true, instrumental: Bool = false) -> [String: Any] {
        var d: [String: Any] = ["id": id, "trackName": title, "artistName": artist, "albumName": album, "duration": duration, "instrumental": instrumental]
        if synced { d["syncedLyrics"] = "[00:01.00]Un\n[00:03.00]Deux\n[00:05.00]Trois" }
        if plain { d["plainLyrics"] = "Un\nDeux\nTrois" }
        return d
    }
    static func json(_ any: Any) -> Data { (try? JSONSerialization.data(withJSONObject: any)) ?? Data() }
    static func ok(_ record: [String: Any]) -> ScriptedTransport.Reply { .http(200, headers: [:], body: json(record)) }
    static func list(_ records: [[String: Any]]) -> ScriptedTransport.Reply { .http(200, headers: [:], body: json(records)) }
    static let notFound = ScriptedTransport.Reply.http(404, headers: [:], body: Data(#"{"code":404}"#.utf8))
    static func busy(_ retryAfter: String? = "1") -> ScriptedTransport.Reply {
        .http(503, headers: retryAfter.map { ["Retry-After": $0] } ?? [:], body: Data("The server is busy".utf8))
    }
}

/// Événements rapportés pendant le déroulé (ordre conservé).
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [LookupEvent] = []
    func add(_ e: LookupEvent) { lock.withLock { items.append(e) } }
    var events: [LookupEvent] { lock.withLock { items } }
    var busyCount: Int { events.filter { if case .busy = $0 { return true } else { return false } }.count }
    var retrying: Int { events.filter { $0 == .retrying }.count }
    var firstBusy: Double? { events.compactMap { if case .busy(let s, _) = $0 { return s } else { return nil } }.first }
}

@Suite("LookupRunner : déroulé d'un titre (1.0.1)")
struct LookupRunnerTests {
    let track = TrackInfo(title: "Phares sur la mer", artist: "Artiste fictif", album: "Album fictif", duration: 200, player: "fake")

    func make(_ handler: @escaping @Sendable (ScriptedTransport.Call, Int) -> ScriptedTransport.Reply, titlesBeforeBreaker: Int = 3)
        -> (LookupRunner, ScriptedTransport, VirtualClock) {
        let clock = VirtualClock()
        let transport = ScriptedTransport(clock: clock, handler: handler)
        let client = LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: transport, userAgent: "Test/0 (test)")
        let runner = LookupRunner(client: client, gate: RequestGate(titlesBeforeBreaker: titlesBeforeBreaker, random: { 0.5 }),
                                  clock: { clock.now }, sleep: { s in clock.advance(s); await Task.yield() })
        return (runner, transport, clock)
    }

    func run(_ runner: LookupRunner, _ track: TrackInfo, knownID: Int? = nil, log: EventLog = EventLog()) async -> LookupOutcome {
        await runner.run(track: track, knownID: knownID) { log.add($0) }
    }

    func isSynced(_ o: LookupOutcome) -> Bool { if case .found(let l) = o { return l.isSynced } else { return false } }

    @Test("get 200 synchronisé : une seule requête, rien d'autre")
    func getHit() async {
        let (r, t, _) = make { c, _ in Wire.ok(Wire.record(id: 1, title: "Phares sur la mer", artist: "Artiste fictif")) }
        let o = await run(r, track)
        #expect(isSynced(o))
        #expect(t.paths == ["/api/get"])
    }

    @Test("get en 503 : passage IMMÉDIAT à search (espacement de 300 ms, pas d'attente de Retry-After) puis paroles trouvées")
    func get503ThenSearch() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.busy("1") }
            return Wire.list([Wire.record(id: 2, title: "Phares sur la mer", artist: "Artiste fictif")])
        }
        let o = await run(r, track)
        #expect(isSynced(o))
        #expect(t.paths == ["/api/get", "/api/search"])
        let gap = t.calls[1].at - t.calls[0].at
        #expect(gap >= 0.3 && gap < 1.0, "écart \(gap) s")
    }

    @Test("get en délai dépassé puis en panne de transport : search prend le relais")
    func getTimeoutThenSearch() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return .error(.timeout) }
            return Wire.list([Wire.record(id: 3, title: "Phares sur la mer", artist: "Artiste fictif")])
        }
        #expect(isSynced(await run(r, track)))
        #expect(t.paths == ["/api/get", "/api/search"])
        let (r2, t2, _) = make { c, _ in
            if c.path == "/api/get" { return .error(.transport("URLError -1005")) }
            return Wire.list([Wire.record(id: 3, title: "Phares sur la mer", artist: "Artiste fictif")])
        }
        #expect(isSynced(await run(r2, track)))
        #expect(t2.paths == ["/api/get", "/api/search"])
    }

    @Test("get 503 puis 200 (la scène mesurée en vrai) : si search ne donne rien, get est retenté après Retry-After")
    func get503RetriedAfterRetryAfter() async {
        let (r, t, _) = make { c, nth in
            if c.path == "/api/get" { return nth == 1 ? Wire.busy("2") : Wire.ok(Wire.record(id: 4, title: "Phares sur la mer", artist: "Artiste fictif")) }
            return Wire.list([])                                  // search : aucune entrée
        }
        let o = await run(r, track)
        #expect(isSynced(o))
        let gets = t.calls(to: "/api/get")
        #expect(gets.count == 2)
        #expect(gets[1].at - gets[0].at >= 2.0)                   // Retry-After: 2 respecté pour la reprise
        #expect(t.calls.count <= RequestGate.maxRequestsPerAttempt)
    }

    @Test("tout en 503 au début, bon ensuite : « Service occupé » puis reprise automatique, jamais « indisponible »")
    func busyThenAutomaticRetry() async {
        let failing = Counter()
        let (r, t, clock) = make { c, _ in
            if failing.value < 9 { failing.bump(); return Wire.busy("1") }          // 9 premières requêtes en 503
            return Wire.ok(Wire.record(id: 5, title: "Phares sur la mer", artist: "Artiste fictif"))
        }
        let log = EventLog()
        let o = await run(r, track, log: log)
        #expect(isSynced(o))
        #expect(log.busyCount >= 1 && log.retrying >= 1)
        #expect(log.firstBusy.map { $0 <= 5.0 } == true)           // compte à rebours de la première reprise (5 s)
        #expect(clock.now >= 5)
        #expect(t.calls.count == 10)
        // jamais plus de 6 requêtes avant la première attente espacée de 5 s
        #expect(t.calls.filter { $0.at < 5 }.count <= RequestGate.maxRequestsPerAttempt)
    }

    @Test("panne totale : reprises espacées 5, 10, 20, 40, 60, 60 s, puis « stalled » (pas « notFound ») ; requêtes bornées")
    func permanentOutage() async {
        let (r, t, clock) = make { _, _ in Wire.busy("1") }
        let log = EventLog()
        let o = await run(r, track, log: log)
        guard case .stalled = o else { Issue.record("attendu stalled, obtenu \(o)"); return }
        #expect(t.calls.count <= RequestGate.maxRequestsPerAttempt + 6 * 3)
        #expect(clock.now >= 5 + 10 + 20 + 40 + 60 + 60)
        #expect(log.retrying == 6)
    }

    @Test("404 partout : notFound DÉFINITIF après les 5 requêtes prévues au plus")
    func definitiveNotFound() async {
        let (r, t, _) = make { c, _ in c.path == "/api/get" ? Wire.notFound : Wire.list([]) }
        let o = await run(r, TrackInfo(title: "Phares sur la mer (T.G.I.F.)", artist: "Artiste fictif, Autre voix", duration: 200))
        guard case .notFound(_, let definitive) = o else { Issue.record("attendu notFound, obtenu \(o)"); return }
        #expect(definitive)
        #expect(t.calls.count == 5)                                // get + 4 recherches distinctes
        #expect(t.calls.count <= 6)
    }

    @Test("notFound NON définitif si une requête est restée en erreur : search vide mais get en 503 jusqu'au bout")
    func notDefinitiveWhenAStepFailed() async {
        let (r, _, _) = make { c, _ in c.path == "/api/get" ? Wire.busy("1") : Wire.list([]) }
        let o = await run(r, track)
        if case .notFound = o { Issue.record("une erreur passagère ne doit pas finir en notFound") }
    }

    @Test("titre « (feat. …) » / « - Remastered 2011 » : requêtes sans suffixe, casse et apostrophes gardées, recherche combinée q")
    func queryNormalisation() async {
        let (r, t, _) = make { c, _ in c.path == "/api/get" ? Wire.notFound : Wire.list([]) }
        _ = await run(r, TrackInfo(title: "Don't Stop Believin' (feat. Invité) - Remastered 2011", artist: "Journey", duration: 250))
        let searches = t.calls(to: "/api/search")
        #expect(searches.first?.query["track_name"] == "Don't Stop Believin'")
        #expect(searches.first?.query["artist_name"] == "Journey")
        #expect(searches.contains { $0.query["q"] == "Don't Stop Believin' Journey" })
        // get : le titre joué tel quel (LRCLIB compare à son propre titre)
        #expect(t.calls(to: "/api/get").first?.query["track_name"] == "Don't Stop Believin' (feat. Invité) - Remastered 2011")
    }

    @Test("« The » en tête : la recherche combinée utilise l'artiste sans « The » et le candidat sans « The » est retenu")
    func thePrefix() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.notFound }
            if c.query["q"] != nil { return Wire.list([Wire.record(id: 7, title: "I Gotta Feeling", artist: "Black Eyed Peas", duration: 289)]) }
            return Wire.list([])
        }
        let o = await run(r, TrackInfo(title: "I Gotta Feeling", artist: "The Black Eyed Peas", duration: 289))
        #expect(isSynced(o))
        #expect(t.calls(to: "/api/search").last?.query["q"] == "I Gotta Feeling Black Eyed Peas")
    }

    @Test("plusieurs artistes : le premier artiste est essayé ; l'entrée « Justin Bieber » est retenue pour « Justin Bieber, Daniel Caesar, Giveon »")
    func multiArtist() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.notFound }
            if c.query["artist_name"] == "Justin Bieber" { return Wire.list([Wire.record(id: 8, title: "Peaches (feat. Daniel Caesar & Giveon)", artist: "Justin Bieber", duration: 198)]) }
            return Wire.list([])
        }
        let o = await run(r, TrackInfo(title: "Peaches (feat. Daniel Caesar & Giveon)", artist: "Justin Bieber, Daniel Caesar, Giveon", duration: 198))
        #expect(isSynced(o))
        let searches = t.calls(to: "/api/search")
        #expect(searches.count == 2)
        #expect(searches[0].query["artist_name"] == "Justin Bieber, Daniel Caesar, Giveon")
        #expect(searches[1].query["artist_name"] == "Justin Bieber")
        #expect(searches[1].query["track_name"] == "Peaches")
    }

    @Test("titre court : « Last Friday Night (T.G.I.F.) » est aussi cherché sans la parenthèse finale")
    func shortTitleStep() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.notFound }
            if c.query["track_name"] == "Last Friday Night" { return Wire.list([Wire.record(id: 9, title: "Last Friday Night", artist: "Katy Perry", duration: 230)]) }
            return Wire.list([])
        }
        let o = await run(r, TrackInfo(title: "Last Friday Night (T.G.I.F.)", artist: "Katy Perry", duration: 230))
        #expect(isSynced(o))
        #expect(t.calls(to: "/api/search").last?.query["track_name"] == "Last Friday Night")
    }

    @Test("écart de durée 6 à 15 s : synchronisé (consigné) ; au-delà de 15 s : texte seul")
    func durationGap() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.notFound }
            return Wire.list([Wire.record(id: 10, title: "Phares sur la mer", artist: "Artiste fictif", duration: 211)])   // +11 s
        }
        let o = await run(r, track)
        guard case .found(let l) = o else { Issue.record("attendu found"); return }
        #expect(l.isSynced)
        #expect(l.provenance.contains("toléré ≤ 15 s"))
        #expect(t.calls.count == 2)                                // get + un seul search : le résultat toléré est accepté après une recherche
        let (r2, _, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.notFound }
            return Wire.list([Wire.record(id: 11, title: "Phares sur la mer", artist: "Artiste fictif", duration: 230)])   // +30 s
        }
        guard case .found(let l2) = await run(r2, track) else { Issue.record("attendu found"); return }
        #expect(l2.plainText != nil && !l2.isSynced)
    }

    @Test("get 200 mais texte seul : le déroulé cherche encore un LRC (search) et le préfère")
    func plainThenSynced() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.ok(Wire.record(id: 12, title: "Phares sur la mer", artist: "Artiste fictif", synced: false)) }
            return Wire.list([Wire.record(id: 13, title: "Phares sur la mer", artist: "Artiste fictif")])
        }
        guard case .found(let l) = await run(r, track) else { Issue.record("attendu found"); return }
        #expect(l.isSynced && l.lrclibID == 13)
        #expect(t.paths == ["/api/get", "/api/search"])
    }

    @Test("get 200 texte seul et rien de mieux : le texte seul est rendu après les recherches")
    func plainOnly() async {
        let (r, _, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.ok(Wire.record(id: 14, title: "Phares sur la mer", artist: "Artiste fictif", synced: false)) }
            return Wire.list([])
        }
        guard case .found(let l) = await run(r, track) else { Issue.record("attendu found"); return }
        #expect(l.plainText != nil)
    }

    @Test("texte seul : une seule recherche après le get si elle confirme (bon titre, bon artiste) ; sinon les autres requêtes sont essayées")
    func plainOnlyStopsEarly() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.ok(Wire.record(id: 14, title: "Phares sur la mer", artist: "Artiste fictif", synced: false)) }
            return Wire.list([Wire.record(id: 14, title: "Phares sur la mer", artist: "Artiste fictif", synced: false)])
        }
        guard case .found(let l) = await run(r, track) else { Issue.record("attendu found"); return }
        #expect(l.plainText != nil)
        #expect(t.paths == ["/api/get", "/api/search"])               // pas de 3e, 4e, 5e requête pour un texte seul confirmé
        // le meilleur candidat de la recherche est d'un autre artiste : on continue
        let (r2, t2, _) = make { c, _ in
            if c.path == "/api/get" { return Wire.notFound }
            return Wire.list([Wire.record(id: 15, title: "Phares sur la mer", artist: "Quelqu'un d'autre", synced: false)])
        }
        _ = await run(r2, track)
        #expect(t2.calls.count == 3)                                  // get + search + search (q), puis fin du plan
    }

    @Test("instrumental : arrêt immédiat")
    func instrumental() async {
        let (r, t, _) = make { _, _ in Wire.ok(Wire.record(id: 15, title: "Phares sur la mer", artist: "Artiste fictif", synced: false, plain: false, instrumental: true)) }
        guard case .found(let l) = await run(r, track) else { Issue.record("attendu found"); return }
        #expect(l.kind == .instrumental)
        #expect(t.calls.count == 1)
    }

    @Test("identifiant connu (index) : get/{id} d'abord ; 404 → déroulé normal")
    func knownID() async {
        let (r, t, _) = make { c, _ in
            if c.path == "/api/get/77" { return Wire.notFound }
            return Wire.ok(Wire.record(id: 16, title: "Phares sur la mer", artist: "Artiste fictif"))
        }
        #expect(isSynced(await run(r, track, knownID: 77)))
        #expect(t.paths == ["/api/get/77", "/api/get"])
        let (r2, t2, _) = make { c, _ in Wire.ok(Wire.record(id: 77, title: "Phares sur la mer", artist: "Artiste fictif")) }
        #expect(isSynced(await run(r2, track, knownID: 77)))
        #expect(t2.paths == ["/api/get/77"])
    }

    @Test("429 : porte fermée jusqu'à Retry-After (+ aléa), « Service occupé » compté à rebours, puis reprise et paroles")
    func rateLimited() async {
        let (r, t, clock) = make { c, nth in
            if nth == 1 && c.path == "/api/get" { return .http(429, headers: ["Retry-After": "3"], body: Data()) }
            if c.path == "/api/search" { return Wire.list([]) }
            return Wire.ok(Wire.record(id: 17, title: "Phares sur la mer", artist: "Artiste fictif"))
        }
        let log = EventLog()
        #expect(isSynced(await run(r, track, log: log)))
        #expect(log.busyCount >= 3 && log.retrying == 1)
        #expect(clock.now >= 3.5 - 0.001)
        let calls = t.calls
        #expect(calls[1].at >= 3.5 - 0.001)                         // aucune requête pendant la fermeture de la porte (D8)
    }

    @Test("429 répété : le déroulé s'arrête en « stalled » (reprises espacées), pas en « indisponible »")
    func rateLimitedAgain() async {
        let (r, _, _) = make { _, _ in .http(429, headers: ["Retry-After": "1"], body: Data()) }
        let o = await run(r, track)
        guard case .stalled = o else { Issue.record("attendu stalled, obtenu \(o)"); return }
    }

    @Test("hors connexion : aucune requête ; au retour du réseau, la recherche reprend")
    func offline() async {
        let (r, t, _) = make { _, _ in Wire.ok(Wire.record(id: 18, title: "Phares sur la mer", artist: "Artiste fictif")) }
        await r.setOnline(false)
        let log = EventLog()
        let task = Task { await run(r, track, log: log) }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(t.calls.isEmpty)
        #expect(log.events.contains(.offline))
        await r.setOnline(true)
        #expect(isSynced(await task.value))
        #expect(t.calls.count == 1)
    }

    @Test("annulation pendant une attente : « cancelled », aucune requête de plus")
    func cancellation() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport(clock: clock) { _, _ in Wire.busy("1") }
        let client = LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: transport, userAgent: "Test/0 (test)")
        // attente réelle courte pour pouvoir annuler en cours de route
        let runner = LookupRunner(client: client, gate: RequestGate(titlesBeforeBreaker: 3, random: { 0.5 }), clock: { clock.now },
                                  sleep: { s in try? await Task.sleep(for: .milliseconds(20)); clock.advance(s) })
        let task = Task { await runner.run(track: track, knownID: nil) { _ in } }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        #expect(await task.value == .cancelled)
    }

    @Test("plan : ordre et absence de doublons (artiste seul, sans artiste, titre déjà court)")
    func plan() {
        let simple = LookupRunner.plan(for: TrackInfo(title: "Roar", artist: "Katy Perry"))
        #expect(simple.map(\.name) == ["get", "search", "search (q)"])
        let full = LookupRunner.plan(for: TrackInfo(title: "Dark Horse (feat. Juicy J)", artist: "Katy Perry, Juicy J"))
        #expect(full.map(\.name) == ["get", "search", "search (1er artiste)", "search (q)"])
        let withParen = LookupRunner.plan(for: TrackInfo(title: "Last Friday Night (T.G.I.F.)", artist: "Katy Perry"))
        #expect(withParen.map(\.name) == ["get", "search", "search (q)", "search (titre court)"])
        let noArtist = LookupRunner.plan(for: TrackInfo(title: "Titre seul", artist: ""))
        #expect(noArtist.map(\.name) == ["get", "search (q)"])
        #expect(full.count <= 5)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    var value: Int { lock.withLock { v } }
    func bump() { lock.withLock { v += 1 } }
}

@Suite("Aides de requête et de correspondance (1.0.1)")
struct QueryHelpersTests {
    @Test("queryTitle : suffixes retirés, casse / accents / apostrophes gardés")
    func queryTitle() {
        #expect(TrackMatcher.queryTitle("Peaches (feat. Daniel Caesar & Giveon)") == "Peaches")
        #expect(TrackMatcher.queryTitle("Bohemian Rhapsody - Remastered 2011") == "Bohemian Rhapsody")
        #expect(TrackMatcher.queryTitle("Alors on danse - Radio Edit") == "Alors on danse")
        #expect(TrackMatcher.queryTitle("Billie Jean - Single Version") == "Billie Jean")
        #expect(TrackMatcher.queryTitle("Hey Jude - 2015 Remaster") == "Hey Jude")
        #expect(TrackMatcher.queryTitle("Don't Stop Believin'") == "Don't Stop Believin'")
        #expect(TrackMatcher.queryTitle("La Vie en rose (Remastered)") == "La Vie en rose")
        #expect(TrackMatcher.queryTitle("Où est l’amour ? feat. Quelqu'un") == "Où est l’amour ?")
        #expect(TrackMatcher.queryTitle("Horloge (Live)") == "Horloge (Live)")
    }

    @Test("shortQueryTitle : en plus, suffixe « - … » et parenthèse finale retirés")
    func shortTitle() {
        #expect(TrackMatcher.shortQueryTitle("Last Friday Night (T.G.I.F.)") == "Last Friday Night")
        #expect(TrackMatcher.shortQueryTitle("Titre - From \"Un film\"") == "Titre")
        #expect(TrackMatcher.shortQueryTitle("Roar") == "Roar")
    }

    @Test("primaryArtist et withoutThe")
    func artists() {
        #expect(TrackMatcher.primaryArtist("Justin Bieber, Daniel Caesar, Giveon") == "Justin Bieber")
        #expect(TrackMatcher.primaryArtist("Mark Ronson feat. Bruno Mars") == "Mark Ronson")
        #expect(TrackMatcher.primaryArtist("Duo fictif & Chanteuse fictive") == "Duo fictif")
        #expect(TrackMatcher.primaryArtist("AC/DC") == "AC/DC")
        #expect(TrackMatcher.primaryArtist("Katy Perry") == "Katy Perry")
        #expect(TrackMatcher.withoutThe("The Black Eyed Peas") == "Black Eyed Peas")
        #expect(TrackMatcher.withoutThe("Theory of a Deadman") == "Theory of a Deadman")
    }

    @Test("titleKey : accents, ponctuation, casse ignorés ; titre de ponctuation seule conservé")
    func titleKey() {
        #expect(TrackMatcher.titleKey("Where Is The Love?") == TrackMatcher.titleKey("where is the love"))
        #expect(TrackMatcher.titleKey("Éléphant d'été") == TrackMatcher.titleKey("Elephant d'ete"))
        #expect(TrackMatcher.titleKey("?") == "?")
    }

    @Test("artistMatches : « The » et accents ignorés, artiste multiple, entrée type vidéo refusée")
    func artistMatches() {
        let t = TrackInfo(title: "X", artist: "The Black Eyed Peas")
        #expect(TrackMatcher.artistMatches("Black Eyed Peas", t))
        #expect(TrackMatcher.artistMatches("Édith Piaf", TrackInfo(title: "X", artist: "Edith Piaf")))
        #expect(TrackMatcher.artistMatches("Justin Bieber", TrackInfo(title: "X", artist: "Justin Bieber, Daniel Caesar, Giveon")))
        #expect(!TrackMatcher.artistMatches("Quelqu'un d'autre", t))
        #expect(!TrackMatcher.artistMatches("Black Eyed Peas | Official Video", t))
    }

    @Test("porte : un nouveau titre ramène une pause de disjoncteur à 5 s au plus ; un 429 n'est jamais raccourci")
    func halfOpen() {
        var g = RequestGate(titlesBeforeBreaker: 1, random: { 0.5 })
        g.beginTitle()
        g.requestStarted(now: 0); _ = g.requestFinished(now: 1, outcome: .serverError(status: 503, retryAfter: nil))
        g.requestStarted(now: 4); _ = g.requestFinished(now: 5, outcome: .serverError(status: 503, retryAfter: nil))
        #expect(g.closedUntil == 15)                              // première pause : 10 s
        g.beginTitle(now: 6)
        #expect(g.closedUntil == 11)                              // ramenée à 5 s après l'arrivée du nouveau titre
        var h = RequestGate(titlesBeforeBreaker: 1, random: { 0.5 })
        h.beginTitle()
        h.requestStarted(now: 0); _ = h.requestFinished(now: 1, outcome: .rateLimited(retryAfter: 60))
        let until = h.closedUntil
        h.beginTitle(now: 2)
        #expect(h.closedUntil == until)
    }

    @Test("porte : une erreur serveur avec une autre voie possible n'attend pas Retry-After et ne compte pas comme essai")
    func fallbackSkipsWait() {
        var g = RequestGate(titlesBeforeBreaker: 3, random: { 0.5 })
        g.beginTitle()
        g.requestStarted(now: 0)
        #expect(g.requestFinished(now: 1, outcome: .serverError(status: 503, retryAfter: 30), fallbackAvailable: true) == .proceed)
        #expect(g.admit(now: 1.1) == .wait(0.2))                  // espacement seul
        #expect(g.serverRetries == 0)
    }

    @Test("porte : un titre ne compte qu'une fois pour le disjoncteur, même sur plusieurs tentatives")
    func titleCountedOnce() {
        var g = RequestGate(titlesBeforeBreaker: 3, random: { 0.5 })
        g.beginTitle()
        var now = 0.0
        for _ in 0..<3 {                                           // trois tentatives du MÊME titre
            g.beginAttempt()
            for _ in 0..<3 { g.requestStarted(now: now); now += 1; _ = g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: 1)); now += 1 }
        }
        #expect(g.failedTitlesInARow == 1 && g.closedUntil == nil)
    }

    @Test("cache et index : « Réessayer » oublie l'entrée")
    func removeEntries() {
        var c = LyricsCache()
        c.store(Lyrics(kind: .plain("x")), for: "k")
        c.remove("k")
        #expect(c.count == 0)
        var i = LookupIndex()
        i.record(key: "k", outcome: .notFound, now: Date())
        i.remove(key: "k")
        #expect(i.count == 0)
    }

    @Test("états : service qui ne répond plus = « Service occupé » (jamais « indisponible »), texte sans compte à rebours")
    func stalledState() {
        var s = DisplayState.initial
        s = DisplayState.reduce(s, .trackChanged)
        s = DisplayState.reduce(s, .serviceBusy(retryIn: 5))
        #expect(s.stateText?.body == "Nouvel essai dans 5 s.")
        s = DisplayState.reduce(s, .serviceStalled)
        #expect(s.screen == .busy(retryIn: 0))
        #expect(s.stateText?.title == "Service de paroles occupé")
        #expect(s.stateText?.body.contains("ne répond pas") == true)
        s = DisplayState.reduce(s, .trackChanged)
        #expect(s.screen == .searching(hint: false))
        // hors connexion prime ; sans titre, rien
        var o = DisplayState.reduce(DisplayState.initial, .trackChanged)
        o = DisplayState.reduce(o, .wentOffline)
        #expect(DisplayState.reduce(o, .serviceStalled).screen == .offline)
        #expect(DisplayState.reduce(DisplayState.initial, .serviceStalled).screen == .nothing)
    }
}
