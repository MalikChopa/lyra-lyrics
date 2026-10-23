import Testing
import Foundation
@testable import LyricsCore

@Suite("TrackMatcher")
struct TrackMatcherTests {
    struct Golden: Decodable {
        struct Case: Decodable {
            struct Track: Decodable { var title: String; var artist: String; var album: String?; var duration: Double? }
            struct Candidate: Decodable {
                var id: Int; var title: String; var artist: String; var album: String?; var duration: Double?
                var instrumental: Bool?; var synced: Bool?; var plain: Bool?
            }
            struct Expect: Decodable { var id: Int?; var mode: String }
            struct Norm: Decodable { var `in`: String; var out: String }
            var name: String
            var track: Track?
            var candidates: [Candidate]?
            var expect: Expect?
            var normalize: [Norm]?
        }
        var cases: [Case]
    }

    @Test("table dorée Fixtures/golden/matching.json : taux de réussite imprimé, 100 % attendu")
    func golden() throws {
        let golden = try JSONDecoder().decode(Golden.self, from: try Fixtures.data("golden/matching.json"))
        var total = 0, passed = 0
        var failures: [String] = []
        for c in golden.cases {
            if let norms = c.normalize {
                for n in norms {
                    total += 1
                    let got = TrackMatcher.normalizeTitle(n.in)
                    if got == n.out { passed += 1 } else { failures.append("\(c.name) : « \(n.in) » → « \(got) » (attendu « \(n.out) »)") }
                }
                continue
            }
            guard let t = c.track, let cands = c.candidates, let expect = c.expect else { continue }
            total += 1
            let track = TrackInfo(title: t.title, artist: t.artist, album: t.album, duration: t.duration)
            let candidates = cands.map {
                TrackMatcher.Candidate(id: $0.id, title: $0.title, artist: $0.artist, album: $0.album, duration: $0.duration,
                                       instrumental: $0.instrumental ?? false, hasSynced: $0.synced ?? false, hasPlain: $0.plain ?? false)
            }
            let d = TrackMatcher.choose(for: track, among: candidates)
            if d.candidate?.id == expect.id && d.mode.rawValue == expect.mode {
                passed += 1
            } else {
                failures.append("\(c.name) : obtenu id \(d.candidate?.id.description ?? "nil") mode \(d.mode.rawValue) (\(d.reason)) ; attendu id \(expect.id?.description ?? "nil") mode \(expect.mode)")
            }
        }
        let rate = total == 0 ? 0 : Double(passed) * 100 / Double(total)
        print(String(format: "GOLDEN_MATCHING passed=%d total=%d rate=%.1f%%", passed, total, rate))
        for f in failures { Issue.record(Comment(rawValue: f)) }
        #expect(total >= 25)
        #expect(passed == total)
    }

    @Test("normalisation d'artiste, jetons, entrées type vidéo, verdict de durée")
    func helpers() {
        #expect(TrackMatcher.artistTokens("Duo fictif / Chanteuse fictive") == ["duo fictif", "chanteuse fictive"])
        #expect(TrackMatcher.artistTokens("Duo fictif feat. Chanteuse fictive").contains("duo fictif"))
        #expect(TrackMatcher.artistTokens("Marin & Phare") == ["marin", "phare"])
        #expect(TrackMatcher.looksLikeVideoTitle("Artiste - Chanson (Official Video)"))
        #expect(TrackMatcher.looksLikeVideoTitle("Chanson | Lyrics"))
        #expect(!TrackMatcher.looksLikeVideoTitle("Artiste fictif"))
        #expect(TrackMatcher.durationVerdict(track: 100, candidate: 104) == .close(4))
        #expect(TrackMatcher.durationVerdict(track: 100, candidate: 105) == .close(5))
        #expect(TrackMatcher.durationVerdict(track: 100, candidate: 94) == .far(-6))
        #expect(TrackMatcher.durationVerdict(track: nil, candidate: 94) == .unknown)
        #expect(TrackMatcher.durationVerdict(track: 100, candidate: nil) == .unknown)
    }
}

/// Transport bouchon : file de réponses (ou d'erreurs) et requêtes reçues.
final class StubTransport: LRCLIBTransport, @unchecked Sendable {
    enum Step { case response(HTTPResponse); case failure(LRCLIBError); case hang }
    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []
    private(set) var timeouts: [Double] = []
    init(_ steps: [Step]) { self.steps = steps }

    func send(_ request: URLRequest, timeout: Double) async throws -> HTTPResponse {
        let step: Step = lock.withLock {
            requests.append(request); timeouts.append(timeout)
            return steps.isEmpty ? .failure(.transport("plus de réponse prévue")) : steps.removeFirst()
        }
        switch step {
        case .response(let r): return r
        case .failure(let e): throw e
        case .hang:
            try await Task.sleep(for: .seconds(30))
            throw LRCLIBError.timeout
        }
    }
}

@Suite("LRCLIBClient (transport factice)")
struct LRCLIBClientTests {
    static let json200 = Data(#"{"id":101,"name":"Phares sur la mer","trackName":"Phares sur la mer","artistName":"Artiste fictif","albumName":"Album fictif","duration":120.0,"instrumental":false,"plainLyrics":"Les phares glissent sur la mer\nEt la ville s'éteint sans bruit","syncedLyrics":"[00:00.00] Les phares glissent sur la mer\n[00:02.80] Et la ville s'éteint sans bruit"}"#.utf8)
    static let json404 = Data(#"{"code":404,"name":"TrackNotFound","message":"Failed to find specified track"}"#.utf8)
    let track = TrackInfo(title: "Phares sur la mer", artist: "Artiste fictif", album: "Album fictif", duration: 120, player: "fake")

    func client(_ steps: [StubTransport.Step]) -> (LRCLIBClient, StubTransport) {
        let t = StubTransport(steps)
        return (LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: t, userAgent: "TestApp/0.0.0 (test)"), t)
    }

    @Test("200 : /api/get avec titre, artiste, album, durée en secondes entières et User-Agent")
    func get200() async throws {
        let (c, t) = client([.response(HTTPResponse(status: 200, body: Self.json200))])
        let result = try await c.lookup(track: track)
        #expect(result.via == "get")
        #expect(result.records.first?.id == 101)
        #expect(result.records.first?.candidate.hasSynced == true)
        let url = t.requests[0].url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(url.path == "/api/get")
        #expect(items.contains(URLQueryItem(name: "track_name", value: "Phares sur la mer")))
        #expect(items.contains(URLQueryItem(name: "artist_name", value: "Artiste fictif")))
        #expect(items.contains(URLQueryItem(name: "album_name", value: "Album fictif")))
        #expect(items.contains(URLQueryItem(name: "duration", value: "120")))
        #expect(t.requests[0].value(forHTTPHeaderField: "User-Agent") == "TestApp/0.0.0 (test)")
        #expect(t.requests[0].cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        let lyrics = LRCLIBClient.lyrics(from: result.records[0], for: track, provenance: "get")
        #expect(lyrics?.syncedLines?.count == 2)
        #expect(lyrics?.lrclibID == 101)
    }

    @Test("404 puis /api/search (titre normalisé) ; pause injectée entre les deux")
    func notFoundThenSearch() async throws {
        let searchBody = Data("[\(String(data: Self.json200, encoding: .utf8)!)]".utf8)
        let (c, t) = client([.response(HTTPResponse(status: 404, body: Self.json404)), .response(HTTPResponse(status: 200, body: searchBody))])
        let paused = Paused()
        let result = try await c.lookup(track: TrackInfo(title: "Phares sur la mer - Remastered 2031", artist: "Artiste fictif", duration: 120),
                                        betweenRequests: { await paused.mark() })
        #expect(result.via == "search")
        #expect(result.records.count == 1)
        #expect(await paused.count == 1)
        #expect(t.requests[1].url!.path == "/api/search")
        let items = URLComponents(url: t.requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.contains(URLQueryItem(name: "track_name", value: "Phares sur la mer")))      // 1.0.1 : casse gardée, suffixe retiré
        // search → tableau vide : aucune entrée (pas une erreur)
        let (c2, _) = client([.response(HTTPResponse(status: 404, body: Self.json404)), .response(HTTPResponse(status: 200, body: Data("[]".utf8)))])
        #expect(try await c2.lookup(track: track).records.isEmpty)
    }

    @Test("instrumental, texte seul, durée > 5 s → texte, aucun texte → nil")
    func lyricsKinds() {
        let instrumental = LRCLIBRecord(id: 1, trackName: "Vent instrumental", artistName: "Trio imaginaire", duration: 180, instrumental: true)
        #expect(LRCLIBClient.lyrics(from: instrumental, for: track, provenance: "get")?.kind == .instrumental)
        let plain = LRCLIBRecord(id: 2, trackName: "Brume", artistName: "Duo fictif", duration: 120, plainLyrics: "Un\nDeux")
        #expect(LRCLIBClient.lyrics(from: plain, for: track, provenance: "get")?.kind == .plain("Un\nDeux"))
        let far = LRCLIBRecord(id: 3, trackName: "Phares sur la mer", artistName: "Artiste fictif", duration: 150, syncedLyrics: "[00:01.00]Un\n[00:02.00]\n[00:03.00]Deux")
        let farLyrics = LRCLIBClient.lyrics(from: far, for: track, provenance: "search")                // +30 s : au-delà de 15 s
        #expect(farLyrics?.kind == .plain("Un\nDeux"))
        #expect(farLyrics?.provenance.contains("> 5 s") == true)
        let tolerated = LRCLIBRecord(id: 6, trackName: "Phares sur la mer", artistName: "Artiste fictif", duration: 128, syncedLyrics: "[00:01.00]Un\n[00:03.00]Deux")
        let toleratedLyrics = LRCLIBClient.lyrics(from: tolerated, for: track, provenance: "search")   // +8 s : synchro tolérée (1.0.1)
        #expect(toleratedLyrics?.isSynced == true)
        #expect(toleratedLyrics?.provenance.contains("toléré ≤ 15 s") == true)
        let strangerGap = LRCLIBRecord(id: 7, trackName: "Phares sur la mer", artistName: "Quelqu'un d'autre", duration: 128, syncedLyrics: "[00:01.00]Un\n[00:03.00]Deux")
        #expect(LRCLIBClient.lyrics(from: strangerGap, for: track, provenance: "search")?.isSynced == false)   // artiste sans rapport : texte
        let unknown = LRCLIBRecord(id: 4, trackName: "Phares sur la mer", artistName: "Artiste fictif", duration: nil, syncedLyrics: "[00:01.00]Un")
        #expect(LRCLIBClient.lyrics(from: unknown, for: track, provenance: "get")?.isSynced == true)
        let empty = LRCLIBRecord(id: 5, trackName: "Rien", artistName: "Personne", duration: 120, plainLyrics: "  ", syncedLyrics: "")
        #expect(LRCLIBClient.lyrics(from: empty, for: track, provenance: "get") == nil)
    }

    @Test("JSON invalide, 429 avec Retry-After, 503, statut inattendu, délai, annulation")
    func errors() async throws {
        let (bad, _) = client([.response(HTTPResponse(status: 200, body: Data("{pas du json".utf8)))])
        await #expect(throws: LRCLIBError.invalidJSON) { try await bad.get(track: track) }
        let (limited, _) = client([.response(HTTPResponse(status: 429, headers: ["retry-after": "3"], body: Data()))])
        await #expect(throws: LRCLIBError.rateLimited(retryAfter: "3")) { try await limited.get(track: track) }
        let (down, _) = client([.response(HTTPResponse(status: 503, headers: ["Retry-After": "1"], body: Data()))])
        await #expect(throws: LRCLIBError.serverError(status: 503, retryAfter: "1")) { try await down.get(track: track) }
        let (odd, _) = client([.response(HTTPResponse(status: 418, body: Data()))])
        await #expect(throws: LRCLIBError.unexpectedStatus(418)) { try await odd.get(track: track) }
        let (slow, t) = client([.failure(.timeout)])
        await #expect(throws: LRCLIBError.timeout) { try await slow.get(track: track, timeout: 2.5) }
        #expect(t.timeouts == [2.5])
        // annulation : le transport reste suspendu, la tâche est annulée
        let (hanging, _) = client([.hang])
        let task = Task { try await hanging.get(track: track) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let outcome = await task.result
        var cancelled = false
        if case .failure(let e) = outcome { cancelled = e is CancellationError || (e as? LRCLIBError) == .cancelled }
        #expect(cancelled)
    }
}

actor Paused {
    private(set) var count = 0
    func mark() { count += 1 }
}
