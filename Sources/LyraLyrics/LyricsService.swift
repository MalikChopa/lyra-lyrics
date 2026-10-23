import Foundation
import CryptoKit
import LyricsCore

/// Ce que le service rapporte au modèle (sur le fil principal, via la fermeture donnée à `lookup`). Jamais de texte dans
/// les diagnostics ; le texte ne circule que dans `found(Lyrics)`, en mémoire.
enum LyricsServiceEvent: Sendable {
    case searching
    /// Fin d'une attente (429 / disjoncteur) : nouvel essai pour le titre courant.
    case retrying
    /// 429, disjoncteur ou reprise espacée après des erreurs passagères : « Service occupé », nouvel essai dans `retryIn` s (chaque seconde).
    case busy(retryIn: Double, reason: String)
    case offline
    case found(Lyrics, cached: Bool)
    /// 404, aucun candidat : la recherche a abouti et il n'y a pas de paroles (état « Paroles indisponibles »).
    case notFound(reason: String)
    /// Erreurs passagères du service qui durent (reprises automatiques épuisées) : « Service occupé » + « Réessayer », JAMAIS « indisponible ».
    case stalled(reason: String)
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

/// Service des paroles (§3.3) : `LookupRunner` (déroulé d'un titre, LyricsCore) + `LyricsCache` (mémoire) + `LookupIndex` (disque, sans
/// texte). Requêtes séquentielles ; un changement de titre annule la recherche en cours (`Task.cancel`).
actor LyricsService {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.malikmoussaoui.lyra-lyrics"
    /// ASCII seulement (décision du 2026-10-22) : CFNetwork encode un en-tête non ASCII en ISO-8859-1 (mesuré à J3). Pas de contact pour l'instant.
    static let userAgent = AppIdentity.userAgent
    /// Révision des règles de recherche : fait partie de la clé de l'index disque, pour que les « non trouvé » de la 1.0.0 (dus au
    /// 503 et à la durée) ne bloquent pas un titre pendant 24 h après la mise à jour.
    static let matchingRevision = "2"

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

    private let runner: LookupRunner
    private var cache = LyricsCache()
    private var index: LookupIndex
    private let indexURL: URL?
    private let hasher: @Sendable (String) -> String
    private let log: @Sendable ([String: String]) -> Void
    private var currentTask: Task<Void, Never>?

    init(client: LRCLIBClient, indexURL: URL?, hasher: @escaping @Sendable (String) -> String,
         titlesBeforeBreaker: Int = 1, minSpacing: Double = RequestGate.minSpacing,
         config: LookupRunner.Config = LookupRunner.Config(), log: @escaping @Sendable ([String: String]) -> Void = { _ in }) {
        self.runner = LookupRunner(client: client, gate: RequestGate(titlesBeforeBreaker: titlesBeforeBreaker, minSpacing: minSpacing),
                                   config: config, clock: { ProcessClock.seconds() },
                                   sleep: { seconds in try? await Task.sleep(for: .seconds(max(0, seconds))) }, log: log)
        self.indexURL = indexURL
        self.index = indexURL.map(LookupIndex.load(from:)) ?? LookupIndex()
        self.hasher = hasher
        self.log = log
        index.purge(now: Date())
    }

    var indexCount: Int { index.count }
    var cacheCount: Int { cache.count }
    var isOffline: Bool { get async { await runner.isOffline } }

    /// Hors connexion (`NWPathMonitor`) : aucune requête ; au retour, la recherche du titre courant reprend.
    func setOnline(_ online: Bool) {
        let runner = runner
        Task { await runner.setOnline(online) }
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
        currentTask = Task { await self.run(track, forced: false, report: report) }
    }

    /// Bouton « Réessayer » : oublie le « non trouvé » noté pour ce titre (index et cache) et recommence de zéro.
    func retry(_ track: TrackInfo, report: @escaping @Sendable (LyricsServiceEvent) -> Void) {
        currentTask?.cancel()
        index.remove(key: indexKey(for: track))
        cache.remove(track.identity)
        log(["lookup": "reessayer"])
        currentTask = Task { await self.run(track, forced: true, report: report) }
    }

    // MARK: - Déroulé d'un titre

    private func indexKey(for track: TrackInfo) -> String {
        LookupIndex.key(for: track, hasher: { [hasher] in hasher(Self.matchingRevision + "\u{1F}" + $0) })
    }

    private func run(_ track: TrackInfo, forced: Bool, report: @escaping @Sendable (LyricsServiceEvent) -> Void) async {
        let key = track.identity
        if !forced, let hit = cache.fetch(key) {
            log(["lookup": "cache", "resultat": hit.isSynced ? "synced" : (hit.plainText != nil ? "plain" : "instrumental")])
            report(.found(hit, cached: true))
            return
        }
        let indexKey = indexKey(for: track)
        var knownID: Int?
        switch forced ? nil : index.lookup(key: indexKey, now: Date()) {
        case .notFound?:
            log(["lookup": "index", "resultat": "non trouvé (< 24 h)"])
            report(.notFound(reason: "index : non trouvé il y a moins de 24 h"))
            return
        case .found(let id)?:
            log(["lookup": "index", "resultat": "id \(id)"])
            knownID = id
        case nil:
            break
        }
        let outcome = await runner.run(track: track, knownID: knownID) { event in
            switch event {
            case .searching: report(.searching)
            case .retrying: report(.retrying)
            case .busy(let seconds, let reason): report(.busy(retryIn: seconds, reason: reason))
            case .offline: report(.offline)
            }
        }
        if Task.isCancelled { return }
        switch outcome {
        case .found(let lyrics):
            let kind = lyrics.isSynced ? "synced" : (lyrics.plainText != nil ? "plain" : "instrumental")
            log(["lookup": "livre", "resultat": kind, "id": lyrics.lrclibID.map(String.init) ?? "", "provenance": lyrics.provenance])
            cache.store(lyrics, for: key)
            if let id = lyrics.lrclibID {
                index.record(key: indexKey, outcome: .found(id: id), now: Date())
                saveIndex()
            }
            report(.found(lyrics, cached: false))
        case .notFound(let reason, let definitive):
            if definitive {
                index.record(key: indexKey, outcome: .notFound, now: Date())
                saveIndex()
            }
            report(.notFound(reason: reason))
        case .stalled(let reason):
            log(["lookup": "service-occupe", "raison": reason])
            report(.stalled(reason: reason))
        case .cancelled:
            break
        }
    }

    private func saveIndex() {
        guard let url = indexURL else { return }
        do { try index.save(to: url) } catch { log(["lookup": "index-ecriture-echec", "erreur": String(describing: error).prefix(80).description]) }
    }
}
