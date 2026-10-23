import Foundation
import CryptoKit
import LyricsCore

/// Ce que le service rapporte au modèle (sur le fil principal, via la fermeture donnée à `lookup`). Jamais de texte dans
/// les diagnostics ; le texte ne circule que dans `found(Lyrics)`, en mémoire.
enum LyricsServiceEvent: Sendable {
    case searching
    /// Fin d'une attente (429 / disjoncteur) : nouvel essai pour le titre courant.
    case retrying
    /// 429 ou disjoncteur : « Service occupé », nouvel essai dans `retryIn` s (répété chaque seconde).
    case busy(retryIn: Double, reason: String)
    case offline
    case found(Lyrics, cached: Bool)
    /// 404, aucun candidat, 429 répété, budget de 15 s dépassé par lenteur (`budget` vrai).
    case notFound(reason: String, budget: Bool)
}

/// Transport réel : `URLSession` ÉPHÉMÈRE, `urlCache = nil` (D3), aucun cookie, `User-Agent` de l'app (D8).
final class URLSessionTransport: LRCLIBTransport, @unchecked Sendable {
    private let session: URLSession

    init(userAgent: String) {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        session = URLSession(configuration: c)
    }

    func send(_ request: URLRequest, timeout: Double) async throws -> HTTPResponse {
        var r = request
        r.timeoutInterval = timeout
        do {
            let (data, response) = try await session.data(for: r)
            guard let http = response as? HTTPURLResponse else { throw LRCLIBError.transport("réponse non HTTP") }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                if let key = k as? String, let value = v as? String { headers[key] = value }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw LRCLIBError.timeout
            case .cancelled: throw LRCLIBError.cancelled
            case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed: throw LRCLIBError.offline
            default: throw LRCLIBError.transport("URLError \(error.code.rawValue)")
            }
        } catch is CancellationError {
            throw LRCLIBError.cancelled
        }
    }
}

/// Service des paroles (§3.3) : `LRCLIBClient` + `RequestGate` + `LyricsCache` (mémoire) + `LookupIndex` (disque, sans
/// texte). Requêtes séquentielles ; un changement de titre annule la recherche en cours (`Task.cancel`).
actor LyricsService {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.malikmoussaoui.lyra-lyrics"
    /// ASCII seulement (décision du 2026-10-22) : CFNetwork encode un en-tête non ASCII en ISO-8859-1 (mesuré à J3). Pas de contact pour l'instant.
    static let userAgent = AppIdentity.userAgent

    /// `~/Library/Application Support/<bundle id>/lookup-index.json` (D4).
    static func defaultIndexURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent(LookupIndex.fileName)
    }

    /// SHA-256 salé (sel aléatoire par installation, gardé dans les préférences ; D4 : obscurcissement léger).
    static func saltedHasher(defaults: UserDefaults) -> @Sendable (String) -> String {
        let key = "pf.index.salt"
        let salt: String
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            salt = existing
        } else {
            var bytes = [UInt8](repeating: 0, count: 16)
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
            salt = Data(bytes).base64EncodedString()
            defaults.set(salt, forKey: key)
        }
        return { material in
            SHA256.hash(data: Data((salt + "\u{1F}" + material).utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private let client: LRCLIBClient
    private var gate: RequestGate
    private var cache = LyricsCache()
    private var index: LookupIndex
    private let indexURL: URL?
    private let hasher: @Sendable (String) -> String
    private let log: @Sendable ([String: String]) -> Void
    private var currentTask: Task<Void, Never>?
    private var onlineWaiters: [CheckedContinuation<Void, Never>] = []

    init(client: LRCLIBClient, indexURL: URL?, hasher: @escaping @Sendable (String) -> String,
         titlesBeforeBreaker: Int = 1, log: @escaping @Sendable ([String: String]) -> Void = { _ in }) {
        self.client = client
        self.gate = RequestGate(titlesBeforeBreaker: titlesBeforeBreaker)
        self.indexURL = indexURL
        self.index = indexURL.map(LookupIndex.load(from:)) ?? LookupIndex()
        self.hasher = hasher
        self.log = log
        index.purge(now: Date())
    }

    private enum Step { case get, getByID(Int), search
        var name: String { switch self { case .get: return "get"; case .getByID: return "get/{id}"; case .search: return "search" } }
    }

    var indexCount: Int { index.count }
    var cacheCount: Int { cache.count }
    var isOffline: Bool { gate.isOffline }

    /// Hors connexion (`NWPathMonitor`) : aucune requête ; au retour, la recherche du titre courant reprend.
    func setOnline(_ online: Bool) {
        gate.isOffline = !online
        if online {
            let waiters = onlineWaiters
            onlineWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    /// « Vider le cache » : index disque vidé (et fichier réécrit), cache mémoire vidé.
    func clearAll() {
        index.clear()
        cache.clear()
        if let url = indexURL { try? index.save(to: url) }
        log(["lookup": "cache-vide", "index": "0"])
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Lance la recherche d'un titre (annule la précédente). `report` est appelé pour chaque étape visible.
    func lookup(_ track: TrackInfo, report: @escaping @Sendable (LyricsServiceEvent) -> Void) {
        currentTask?.cancel()
        currentTask = Task { await self.run(track, report: report) }
    }

    // MARK: - Déroulé d'un titre

    private func now() -> Double { ProcessClock.seconds() }

    private func run(_ track: TrackInfo, report: @escaping @Sendable (LyricsServiceEvent) -> Void) async {
        let key = track.identity
        if let hit = cache.fetch(key) {
            log(["lookup": "cache", "resultat": hit.isSynced ? "synced" : (hit.plainText != nil ? "plain" : "instrumental")])
            report(.found(hit, cached: true))
            return
        }
        gate.beginTitle()
        let indexKey = LookupIndex.key(for: track, hasher: hasher)
        var step: Step = .get
        switch index.lookup(key: indexKey, now: Date()) {
        case .notFound?:
            log(["lookup": "index", "resultat": "non trouvé (< 24 h)"])
            report(.notFound(reason: "index : non trouvé il y a moins de 24 h", budget: false))
            return
        case .found(let id)?:
            log(["lookup": "index", "resultat": "id \(id)"])
            step = .getByID(id)
        case nil:
            break
        }
        report(.searching)
        var gaveUpRateLimit = false

        while !Task.isCancelled {
            switch gate.admit(now: now()) {
            case .offline:
                report(.offline)
                log(["lookup": "hors-connexion", "etape": step.name])
                await waitForOnline()
                continue
            case .busy:
                try? await Task.sleep(for: .milliseconds(50))
                continue
            case .wait(let s):
                try? await Task.sleep(for: .seconds(s))
                continue
            case .closed(let until, let reason):
                await countdown(until: until, reason: reason.rawValue, report: report)
                if Task.isCancelled { return }
                if gaveUpRateLimit {
                    report(.notFound(reason: "service occupé (429 répété)", budget: false))
                    return
                }
                gate.beginAttempt()
                report(.retrying)
                log(["lookup": "nouvel-essai", "etape": step.name, "raison": reason.rawValue])
                continue
            case .budgetExhausted:
                log(["lookup": "budget-epuise", "etape": step.name])
                report(.notFound(reason: "budget de 15 s dépassé (lenteur)", budget: true))
                return
            case .attemptExhausted:
                report(.notFound(reason: "3 requêtes sans résultat", budget: false))
                return
            case .proceed(let timeout):
                let started = now()
                gate.requestStarted(now: started)
                log(["lookup": "requete", "etape": step.name, "timeout": String(format: "%.1f", timeout)])
                do {
                    switch step {
                    case .get, .getByID:
                        let record: LRCLIBRecord
                        if case .getByID(let id) = step { record = try await client.get(id: id, timeout: timeout) }
                        else { record = try await client.get(track: track, timeout: timeout) }
                        _ = gate.requestFinished(now: now(), outcome: .success)
                        let provenance = step.name
                        if let lyrics = LRCLIBClient.lyrics(from: record, for: track, provenance: provenance) {
                            deliver(lyrics, key: key, indexKey: indexKey, step: step, started: started, report: report)
                            return
                        }
                        log(["lookup": "reponse", "etape": step.name, "statut": "200", "ms": ms(since: started), "resultat": "sans texte"])
                        step = .search
                    case .search:
                        let records = try await client.search(track: track, timeout: timeout)
                        _ = gate.requestFinished(now: now(), outcome: .success)
                        let decision = TrackMatcher.choose(for: track, among: records.map(\.candidate))
                        if let candidate = decision.candidate, let record = records.first(where: { $0.id == candidate.id }),
                           let lyrics = LRCLIBClient.lyrics(from: record, for: track, provenance: "search, \(decision.reason)") {
                            log(["lookup": "reponse", "etape": "search", "statut": "200", "ms": ms(since: started), "candidats": "\(records.count)", "choix": decision.reason])
                            deliver(lyrics, key: key, indexKey: indexKey, step: step, started: started, report: report)
                        } else {
                            log(["lookup": "reponse", "etape": "search", "statut": "200", "ms": ms(since: started), "candidats": "\(records.count)", "choix": decision.reason])
                            index.record(key: indexKey, outcome: .notFound, now: Date())
                            saveIndex()
                            report(.notFound(reason: "aucun candidat (\(decision.reason))", budget: false))
                        }
                        return
                    }
                } catch LRCLIBError.notFound {
                    _ = gate.requestFinished(now: now(), outcome: .notFound)
                    log(["lookup": "reponse", "etape": step.name, "statut": "404", "ms": ms(since: started)])
                    switch step {
                    case .get: step = .search
                    case .getByID: step = .get
                    case .search: return
                    }
                } catch LRCLIBError.rateLimited(let retryAfter) {
                    let seconds = RequestGate.parseRetryAfter(retryAfter, now: Date())
                    let verdict = gate.requestFinished(now: now(), outcome: .rateLimited(retryAfter: seconds))
                    log(["lookup": "reponse", "etape": step.name, "statut": "429", "ms": ms(since: started),
                         "retryAfter": retryAfter ?? "", "verdict": describe(verdict)])
                    if case .giveUp = verdict { gaveUpRateLimit = true }
                } catch LRCLIBError.serverError(let status, let retryAfter) {
                    let seconds = RequestGate.parseRetryAfter(retryAfter, now: Date())
                    let verdict = gate.requestFinished(now: now(), outcome: .serverError(status: status, retryAfter: seconds))
                    log(["lookup": "reponse", "etape": step.name, "statut": "\(status)", "ms": ms(since: started),
                         "retryAfter": retryAfter ?? "", "verdict": describe(verdict)])
                    if case .giveUp = verdict, gate.closedUntil == nil {
                        // J4 : titre abandonné après 3 essais en 5xx, porte restée ouverte (le titre suivant sera cherché normalement).
                        report(.notFound(reason: "service occupé (5xx répété pour ce titre)", budget: false))
                        return
                    }
                } catch LRCLIBError.timeout {
                    if timeout < RequestGate.perRequestTimeout - 0.001 {
                        _ = gate.requestFinished(now: now(), outcome: .budgetCut)
                        log(["lookup": "reponse", "etape": step.name, "statut": "coupée par le budget", "ms": ms(since: started)])
                    } else {
                        let verdict = gate.requestFinished(now: now(), outcome: .timeout)
                        log(["lookup": "reponse", "etape": step.name, "statut": "délai dépassé", "ms": ms(since: started), "verdict": describe(verdict)])
                    }
                } catch LRCLIBError.cancelled {
                    _ = gate.requestFinished(now: now(), outcome: .cancelled)
                    return
                } catch is CancellationError {
                    _ = gate.requestFinished(now: now(), outcome: .cancelled)
                    return
                } catch {
                    if Task.isCancelled {
                        _ = gate.requestFinished(now: now(), outcome: .cancelled)
                        return
                    }
                    let verdict = gate.requestFinished(now: now(), outcome: .transportFailure)
                    log(["lookup": "reponse", "etape": step.name, "statut": "panne de transport", "ms": ms(since: started),
                         "erreur": String(describing: error).prefix(80).description, "verdict": describe(verdict)])
                }
            }
        }
    }

    private func deliver(_ lyrics: Lyrics, key: String, indexKey: String, step: Step, started: Double,
                         report: @escaping @Sendable (LyricsServiceEvent) -> Void) {
        let kind = lyrics.isSynced ? "synced" : (lyrics.plainText != nil ? "plain" : "instrumental")
        log(["lookup": "reponse", "etape": step.name, "statut": "200", "ms": ms(since: started), "resultat": kind,
             "id": lyrics.lrclibID.map(String.init) ?? "", "provenance": lyrics.provenance])
        cache.store(lyrics, for: key)
        if let id = lyrics.lrclibID {
            index.record(key: indexKey, outcome: .found(id: id), now: Date())
            saveIndex()
        }
        report(.found(lyrics, cached: false))
    }

    /// « Service occupé » : rapporte le temps restant chaque seconde jusqu'à la réouverture.
    private func countdown(until: Double, reason: String, report: @escaping @Sendable (LyricsServiceEvent) -> Void) async {
        log(["lookup": "porte-fermee", "raison": reason, "secondes": String(format: "%.1f", until - now())])
        while !Task.isCancelled {
            let remaining = until - now()
            if remaining <= 0 { return }
            report(.busy(retryIn: remaining, reason: reason))
            try? await Task.sleep(for: .seconds(min(1, remaining)))
        }
    }

    private func waitForOnline() async {
        guard gate.isOffline else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in onlineWaiters.append(c) }
    }

    private func saveIndex() {
        guard let url = indexURL else { return }
        do { try index.save(to: url) } catch { log(["lookup": "index-ecriture-echec", "erreur": String(describing: error).prefix(80).description]) }
    }

    private func ms(since started: Double) -> String { String(Int(((now() - started) * 1000).rounded())) }

    private func describe(_ v: RequestGate.Verdict) -> String {
        switch v {
        case .proceed: return "continuer"
        case .retry(let after): return String(format: "nouvel essai dans %.1f s", after)
        case .giveUp(let r): return "abandon (\(r.rawValue))"
        }
    }
}
