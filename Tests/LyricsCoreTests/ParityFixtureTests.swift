import Testing
import Foundation
@testable import LyricsCore

/// W2 : fixtures PARTAGÉES avec le cœur C# (`windows/LyraLyrics.Core.Tests/ParityFixtureTests.cs`). Les deux suites lisent les mêmes
/// fichiers de `Fixtures/` et doivent donner les mêmes résultats : toute divergence entre les deux cœurs fait échouer l'une des deux.
enum ParityJSON {
    static func load(_ relative: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try Fixtures.data(relative)) as! [String: Any]
    }
    static func num(_ v: Any?) -> Double? { (v as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue } }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
}

@Suite("Parité : fixtures communes Mac / Windows")
struct ParityFixtureTests {
    @Test("normalize.json : normalisation des titres et des artistes")
    func normalize() throws {
        let doc = try ParityJSON.load("golden/normalize.json")
        var total = 0
        var failures: [String] = []
        func check(_ fn: String, _ run: (String) -> Any, _ eq: (Any, Any) -> Bool) {
            for row in doc[fn] as! [[Any]] {
                total += 1
                let input = row[0] as! String
                let got = run(input)
                if !eq(got, row[1]) { failures.append("\(fn)(« \(input) ») → \(got), attendu \(row[1])") }
            }
        }
        let str: (Any, Any) -> Bool = { ($0 as? String) == ($1 as? String) }
        check("normalizeTitle", { TrackMatcher.normalizeTitle($0) }, str)
        check("titleKey", { TrackMatcher.titleKey($0) }, str)
        check("queryTitle", { TrackMatcher.queryTitle($0) }, str)
        check("shortQueryTitle", { TrackMatcher.shortQueryTitle($0) }, str)
        check("normalizeArtist", { TrackMatcher.normalizeArtist($0) }, str)
        check("primaryArtist", { TrackMatcher.primaryArtist($0) }, str)
        check("withoutThe", { TrackMatcher.withoutThe($0) }, str)
        check("artistTokens", { Array(TrackMatcher.artistTokens($0)).sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) } },
              { ($0 as? [String]) == ($1 as? [String]) })
        check("looksLikeVideoTitle", { TrackMatcher.looksLikeVideoTitle($0) }, { ($0 as? Bool) == ($1 as? Bool) })
        print("PARITE normalize.json cas=\(total)")
        for f in failures { Issue.record(Comment(rawValue: f)) }
        #expect(total >= 500)
        #expect(failures.isEmpty)
    }

    @Test("retry-after.json : secondes, dates HTTP, plafond, inf/nan/hexadécimal rejetés")
    func retryAfter() throws {
        let doc = try ParityJSON.load("golden/retry-after.json")
        let now = Date(timeIntervalSince1970: ParityJSON.num(doc["nowEpoch"])!)
        #expect(ParityJSON.num(doc["maxRetryAfter"]) == RequestGate.maxRetryAfter)
        var failures: [String] = []
        let cases = doc["cases"] as! [[Any]]
        for row in cases {
            let input = row[0] as? String
            let expected = ParityJSON.num(row[1])
            let got = RequestGate.parseRetryAfter(input, now: now)
            let ok = (got == nil && expected == nil) || (got != nil && expected != nil && ParityJSON.close(got!, expected!))
            if !ok { failures.append("« \(input ?? "nil") » → \(String(describing: got)), attendu \(String(describing: expected))") }
        }
        print("PARITE retry-after.json cas=\(cases.count)")
        for f in failures { Issue.record(Comment(rawValue: f)) }
        #expect(failures.isEmpty)
    }

    @Test("lrc/parse-cases.json : lignes, offset, métadonnées")
    func lrc() throws {
        let doc = try ParityJSON.load("lrc/parse-cases.json")
        let cases = doc["cases"] as! [[String: Any]]
        var failures: [String] = []
        for c in cases {
            let r = LRCParser.parseDetailed(c["text"] as! String)
            let lines = (c["lines"] as! [[Any]]).map { (ParityJSON.num($0[0])!, $0[1] as! String) }
            let same = lines.count == r.lines.count && zip(lines, r.lines).allSatisfy { ParityJSON.close($0.0, $1.time) && $0.1 == $1.text }
            if !same { failures.append("\(c["name"]!) : lignes \(r.lines.map { "\($0.time)|\($0.text)" })") }
            if r.offsetMillis != (c["offsetMillis"] as! Int) { failures.append("\(c["name"]!) : offset \(r.offsetMillis)") }
            if r.metadata != (c["metadata"] as! [String: String]) { failures.append("\(c["name"]!) : métadonnées \(r.metadata)") }
        }
        print("PARITE lrc/parse-cases.json cas=\(cases.count)")
        for f in failures { Issue.record(Comment(rawValue: f)) }
        #expect(failures.isEmpty)
    }

    // MARK: Porte de requêtes

    @Test("gate.json : scénarios de la porte (espacement, 429, 5xx, disjoncteur, budget, tentatives)")
    func gate() throws {
        let doc = try ParityJSON.load("golden/gate.json")
        let random = ParityJSON.num(doc["random"])!
        let scenarios = doc["scenarios"] as! [[String: Any]]
        var failures: [String] = []
        var checks = 0
        for sc in scenarios {
            let name = sc["name"] as! String
            let cfg = sc["gate"] as! [String: Any]
            var gate = RequestGate(titlesBeforeBreaker: (cfg["titlesBeforeBreaker"] as? Int) ?? 1,
                                   minSpacing: ParityJSON.num(cfg["minSpacing"]) ?? RequestGate.minSpacing, random: { random })
            for (i, step) in (sc["steps"] as! [[String: Any]]).enumerated() {
                let where_ = "\(name) [étape \(i)]"
                switch step["op"] as! String {
                case "beginTitle": gate.beginTitle(now: ParityJSON.num(step["now"]))
                case "beginAttempt": gate.beginAttempt(limit: step["limit"] as! Int)
                case "offline": gate.isOffline = (step["value"] as! NSNumber).boolValue
                case "start": gate.requestStarted(now: ParityJSON.num(step["now"])!)
                case "admit":
                    checks += 1
                    let e = step["expect"] as! [String: Any]
                    let got = gate.admit(now: ParityJSON.num(step["now"])!)
                    if !Self.admissionMatches(got, e) { failures.append("\(where_) : admission \(got), attendu \(e)") }
                case "finish":
                    checks += 1
                    let e = step["expect"] as! [String: Any]
                    let o = step["outcome"] as! [String: Any]
                    let ra = ParityJSON.num(o["retryAfter"])
                    let outcome: RequestGate.Outcome
                    switch o["kind"] as! String {
                    case "success": outcome = .success
                    case "notFound": outcome = .notFound
                    case "budgetCut": outcome = .budgetCut
                    case "cancelled": outcome = .cancelled
                    case "rateLimited": outcome = .rateLimited(retryAfter: ra)
                    case "serverError": outcome = .serverError(status: (o["status"] as? Int) ?? 503, retryAfter: ra)
                    case "timeout": outcome = .timeout
                    default: outcome = .transportFailure
                    }
                    let got = gate.requestFinished(now: ParityJSON.num(step["now"])!, outcome: outcome, fallbackAvailable: (step["fallback"] as? Bool) ?? false)
                    if !Self.verdictMatches(got, e) { failures.append("\(where_) : verdict \(got), attendu \(e)") }
                case "state":
                    checks += 1
                    let e = step["expect"] as! [String: Any]
                    for (k, v) in e {
                        let ok: Bool
                        switch k {
                        case "breakerTrips": ok = gate.breakerTrips == (v as! Int)
                        case "failedTitlesInARow": ok = gate.failedTitlesInARow == (v as! Int)
                        case "consecutiveFailures": ok = gate.consecutiveFailures == (v as! Int)
                        case "attemptRequests": ok = gate.attemptRequests == (v as! Int)
                        case "closedUntil": ok = (v is NSNull) ? gate.closedUntil == nil : (gate.closedUntil.map { ParityJSON.close($0, ParityJSON.num(v)!) } ?? false)
                        case "closedReason": ok = (v is NSNull) ? gate.closedReason == nil : gate.closedReason?.rawValue.lowercased() == (v as! String).lowercased()
                        default: ok = false
                        }
                        if !ok { failures.append("\(where_) : état \(k) ≠ \(v)") }
                    }
                default: failures.append("\(where_) : opération inconnue")
                }
            }
        }
        print("PARITE gate.json scenarios=\(scenarios.count) verifications=\(checks)")
        for f in failures { Issue.record(Comment(rawValue: f)) }
        #expect(failures.isEmpty)
        #expect(scenarios.count >= 15)
    }

    static func admissionMatches(_ a: RequestGate.Admission, _ e: [String: Any]) -> Bool {
        let kind = e["kind"] as! String
        switch a {
        case .proceed(let t): return kind == "proceed" && ParityJSON.close(t, ParityJSON.num(e["timeout"])!)
        case .wait(let s): return kind == "wait" && ParityJSON.close(s, ParityJSON.num(e["seconds"])!)
        case .closed(let until, let reason):
            return kind == "closed" && ParityJSON.close(until, ParityJSON.num(e["until"])!) && reason.rawValue.lowercased() == (e["reason"] as! String).lowercased()
        case .offline: return kind == "offline"
        case .busy: return kind == "busy"
        case .budgetExhausted: return kind == "budgetExhausted"
        case .attemptExhausted: return kind == "attemptExhausted"
        }
    }

    static func verdictMatches(_ v: RequestGate.Verdict, _ e: [String: Any]) -> Bool {
        let kind = e["kind"] as! String
        switch v {
        case .proceed: return kind == "proceed"
        case .retry(let after): return kind == "retry" && ParityJSON.close(after, ParityJSON.num(e["after"])!)
        case .giveUp(let r): return kind == "giveUp" && r.rawValue.lowercased() == (e["reason"] as! String).lowercased()
        }
    }

    // MARK: Déroulé d'un titre (LookupRunner)

    /// Ce que le déroulé d'un scénario produit : issue, identifiant LRCLIB, chemins et instants des requêtes, fin de l'horloge simulée.
    struct Observed {
        var outcome: String
        var lrclibID: Int?
        var definitive: Bool?
        var paths: [String]
        var at: [Double]
        var end: Double
        var busy: Bool
    }

    static func observe(_ sc: [String: Any]) async -> Observed {
        let replies = sc["replies"] as! [String: [[String: Any]]]
        let t = sc["track"] as! [String: Any]
        let track = TrackInfo(title: t["title"] as! String, artist: t["artist"] as! String, album: t["album"] as? String,
                              duration: ParityJSON.num(t["duration"]), player: "fake")
        func wireRecord(_ r: [String: Any]) -> [String: Any] {
            Wire.record(id: r["id"] as! Int, title: r["title"] as! String, artist: r["artist"] as! String, duration: ParityJSON.num(r["duration"]) ?? 200,
                        synced: (r["synced"] as? Bool) ?? true, plain: (r["plain"] as? Bool) ?? true, instrumental: (r["instrumental"] as? Bool) ?? false)
        }
        let clock = VirtualClock()
        var prepared: [String: [ScriptedTransport.Reply]] = [:]
        for (key, list) in replies {
            prepared[key] = list.map { r -> ScriptedTransport.Reply in
                if let rec = r["record"] as? [String: Any] { return Wire.ok(wireRecord(rec)) }
                if let l = r["list"] as? [[String: Any]] { return Wire.list(l.map(wireRecord)) }
                if let e = r["error"] as? String { return .error(e == "timeout" ? .timeout : .transport("test")) }
                return .http(r["status"] as! Int, headers: (r["retryAfter"] as? String).map { ["Retry-After": $0] } ?? [:], body: Data("x".utf8))
            }
        }
        let script = prepared
        let transport = ScriptedTransport(clock: clock) { call, nth in
            let key = call.path == "/api/get" ? "get" : call.path.hasPrefix("/api/get/") ? "getById" : "search"
            guard let list = script[key], !list.isEmpty else { return Wire.notFound }
            return list[min(nth, list.count) - 1]
        }
        let client = LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: transport, userAgent: "Test/0 (test)")
        let runner = LookupRunner(client: client, gate: RequestGate(titlesBeforeBreaker: (sc["titlesBeforeBreaker"] as? Int) ?? 3, random: { 0.5 }),
                                  clock: { clock.now }, sleep: { s in clock.advance(s); await Task.yield() })
        let log = EventLog()
        let outcome = await runner.run(track: track, knownID: sc["knownID"] as? Int) { log.add($0) }
        var o = Observed(outcome: "", lrclibID: nil, definitive: nil, paths: transport.paths, at: transport.calls.map(\.at), end: clock.now, busy: log.busyCount > 0)
        switch outcome {
        case .found(let l):
            o.lrclibID = l.lrclibID
            switch l.kind { case .synced: o.outcome = "foundSynced"; case .plain: o.outcome = "foundPlain"; case .instrumental: o.outcome = "foundInstrumental" }
        case .notFound(_, let d): o.outcome = "notFound"; o.definitive = d
        case .stalled: o.outcome = "stalled"
        case .cancelled: o.outcome = "cancelled"
        }
        return o
    }

    @Test("runner.json : déroulé d'un titre (get, search, reprises, 429, plafond, repli)")
    func runner() async throws {
        let doc = try ParityJSON.load("golden/runner.json")
        let scenarios = doc["scenarios"] as! [[String: Any]]
        var failures: [String] = []
        for sc in scenarios {
            let name = sc["name"] as! String
            let e = sc["expect"] as! [String: Any]
            let o = await Self.observe(sc)
            if o.outcome != (e["outcome"] as! String) { failures.append("\(name) : issue \(o.outcome), attendu \(e["outcome"]!)") }
            if o.lrclibID != (e["lrclibID"] as? Int) { failures.append("\(name) : id \(String(describing: o.lrclibID)), attendu \(String(describing: e["lrclibID"]))") }
            if o.definitive != (e["definitive"] as? Bool) { failures.append("\(name) : définitif \(String(describing: o.definitive))") }
            if o.paths != (e["paths"] as! [String]) { failures.append("\(name) : chemins \(o.paths), attendu \(e["paths"]!)") }
            let at = (e["at"] as! [Any]).map { ParityJSON.num($0)! }
            if at.count != o.at.count || !zip(at, o.at).allSatisfy({ abs($0 - $1) < 1e-6 }) { failures.append("\(name) : instants \(o.at), attendu \(at)") }
            if abs(o.end - ParityJSON.num(e["end"])!) > 1e-6 { failures.append("\(name) : fin \(o.end), attendu \(e["end"]!)") }
            if o.busy != (e["busy"] as! Bool) { failures.append("\(name) : « service occupé » \(o.busy)") }
        }
        print("PARITE runner.json scenarios=\(scenarios.count)")
        for f in failures { Issue.record(Comment(rawValue: f)) }
        #expect(failures.isEmpty)
        #expect(scenarios.count >= 15)
    }
}
