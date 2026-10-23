import Foundation

/// Réponse HTTP minimale rendue par un transport (statut, en-têtes, corps).
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
    /// En-tête insensible à la casse.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Transport injectable : `URLSession` éphémère côté app, bouchon dans les tests, moteur en processus en DEBUG.
public protocol LRCLIBTransport: Sendable {
    func send(_ request: URLRequest, timeout: Double) async throws -> HTTPResponse
}

public enum LRCLIBError: Error, Sendable, Equatable {
    case notFound
    case rateLimited(retryAfter: String?)
    case serverError(status: Int, retryAfter: String?)
    case unexpectedStatus(Int)
    case invalidJSON
    case timeout
    case cancelled
    case offline
    case transport(String)
}

/// Entrée LRCLIB telle que reçue (`id`, `trackName`, `artistName`, `albumName`, `duration`, `instrumental`, `plainLyrics`,
/// `syncedLyrics`). NON `Codable` (D2) : construite depuis un type de fil `Decodable` seulement, jamais réencodée.
public struct LRCLIBRecord: Sendable, Equatable {
    public var id: Int
    public var trackName: String
    public var artistName: String
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool
    public var plainLyrics: String?
    public var syncedLyrics: String?

    public init(id: Int, trackName: String, artistName: String, albumName: String? = nil, duration: Double? = nil,
                instrumental: Bool = false, plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.id = id; self.trackName = trackName; self.artistName = artistName; self.albumName = albumName
        self.duration = duration; self.instrumental = instrumental; self.plainLyrics = plainLyrics; self.syncedLyrics = syncedLyrics
    }

    public var candidate: TrackMatcher.Candidate {
        TrackMatcher.Candidate(id: id, title: trackName, artist: artistName, album: albumName, duration: duration, instrumental: instrumental,
                               hasSynced: !(syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               hasPlain: !(plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Type de fil : `Decodable` seulement.
    struct Wire: Decodable {
        var id: Int?
        var trackName: String?
        var artistName: String?
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?

        var record: LRCLIBRecord? {
            guard let id else { return nil }
            return LRCLIBRecord(id: id, trackName: trackName ?? "", artistName: artistName ?? "", albumName: albumName, duration: duration,
                                instrumental: instrumental ?? false, plainLyrics: plainLyrics, syncedLyrics: syncedLyrics)
        }
    }
}

public struct LookupResult: Sendable, Equatable {
    public var records: [LRCLIBRecord]
    /// « get » ou « search ».
    public var via: String
    public init(records: [LRCLIBRecord], via: String) { self.records = records; self.via = via }
}

/// Client LRCLIB (§3.2) : `GET /api/get` (titre, artiste, album, durée en s) puis, si 404, `GET /api/search` ; `GET /api/get/{id}`.
/// `User-Agent` `NomAppli/version (lien)`. Le transport est injecté ; côté app : session éphémère, `urlCache = nil` (D3).
public struct LRCLIBClient: Sendable {
    public static let publicBaseURL = URL(string: "https://lrclib.net")!

    public let baseURL: URL
    public let transport: LRCLIBTransport
    public let userAgent: String

    public init(baseURL: URL = LRCLIBClient.publicBaseURL, transport: LRCLIBTransport, userAgent: String) {
        self.baseURL = baseURL; self.transport = transport; self.userAgent = userAgent
    }

    public func makeRequest(path: String, query: [(String, String)] = []) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    /// `/api/get` : 404 → `LRCLIBError.notFound`.
    public func get(track: TrackInfo, timeout: Double = RequestGate.perRequestTimeout) async throws -> LRCLIBRecord {
        var query = [("track_name", track.title), ("artist_name", track.artist)]
        if let album = track.album, !album.isEmpty { query.append(("album_name", album)) }
        if let d = track.duration, d > 0 { query.append(("duration", String(Int(d.rounded())))) }
        let response = try await transport.send(makeRequest(path: "/api/get", query: query), timeout: timeout)
        try Self.check(response)
        guard let record = Self.decodeOne(response.body) else { throw LRCLIBError.invalidJSON }
        return record
    }

    public func get(id: Int, timeout: Double = RequestGate.perRequestTimeout) async throws -> LRCLIBRecord {
        let response = try await transport.send(makeRequest(path: "/api/get/\(id)"), timeout: timeout)
        try Self.check(response)
        guard let record = Self.decodeOne(response.body) else { throw LRCLIBError.invalidJSON }
        return record
    }

    /// `/api/search` (`track_name` + `artist_name`) : tableau (vide si rien).
    public func search(track: TrackInfo, timeout: Double = RequestGate.perRequestTimeout) async throws -> [LRCLIBRecord] {
        let query = [("track_name", TrackMatcher.normalizeTitle(track.title)), ("artist_name", track.artist)]
        let response = try await transport.send(makeRequest(path: "/api/search", query: query), timeout: timeout)
        if response.status == 404 { return [] }
        try Self.check(response)
        guard let records = Self.decodeMany(response.body) else { throw LRCLIBError.invalidJSON }
        return records
    }

    /// `get` puis, si 404, `search` ; `betweenRequests` laisse la porte imposer l'espacement.
    public func lookup(track: TrackInfo, timeout: Double = RequestGate.perRequestTimeout,
                       betweenRequests: @Sendable () async throws -> Void = {}) async throws -> LookupResult {
        do {
            let record = try await get(track: track, timeout: timeout)
            return LookupResult(records: [record], via: "get")
        } catch LRCLIBError.notFound {
            try await betweenRequests()
            let records = try await search(track: track, timeout: timeout)
            return LookupResult(records: records, via: "search")
        }
    }

    /// Paroles à afficher pour une entrée : instrumental ; LRC parsé si la durée colle (≤ 5 s) ou est inconnue ; sinon texte
    /// seul (bloc « non synchronisées ») ; `nil` s'il n'y a aucun texte.
    public static func lyrics(from record: LRCLIBRecord, for track: TrackInfo, provenance: String) -> Lyrics? {
        if record.instrumental { return Lyrics(kind: .instrumental, lrclibID: record.id, provenance: provenance) }
        let verdict = TrackMatcher.durationVerdict(track: track.duration, candidate: record.duration)
        let lines = record.syncedLyrics.map(LRCParser.parse) ?? []
        var why = provenance
        switch verdict {
        case .unknown: why += ", durée inconnue"
        case .close(let d): why += String(format: ", durée %+.0f s", d)
        case .far(let d): why += String(format: ", durée %+.0f s (> 5 s)", d)
        }
        if !lines.isEmpty, case .far = verdict {
            let text = (record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? LRCParser.plainText(from: lines)
            return Lyrics(kind: .plain(text), lrclibID: record.id, provenance: why)
        }
        if !lines.isEmpty { return Lyrics(kind: .synced(lines), lrclibID: record.id, provenance: why) }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return Lyrics(kind: .plain(plain), lrclibID: record.id, provenance: why + ", texte seul")
        }
        return nil
    }

    // MARK: Détails

    static func check(_ response: HTTPResponse) throws {
        switch response.status {
        case 200...299: return
        case 404: throw LRCLIBError.notFound
        case 429: throw LRCLIBError.rateLimited(retryAfter: response.header("Retry-After"))
        case 500...599: throw LRCLIBError.serverError(status: response.status, retryAfter: response.header("Retry-After"))
        default: throw LRCLIBError.unexpectedStatus(response.status)
        }
    }

    static func decodeOne(_ data: Data) -> LRCLIBRecord? {
        (try? JSONDecoder().decode(LRCLIBRecord.Wire.self, from: data))?.record
    }

    static func decodeMany(_ data: Data) -> [LRCLIBRecord]? {
        guard let wires = try? JSONDecoder().decode([LRCLIBRecord.Wire].self, from: data) else { return nil }
        return wires.compactMap(\.record)
    }
}
