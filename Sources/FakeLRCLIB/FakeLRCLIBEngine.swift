import Foundation

/// Catalogue du faux LRCLIB (`Fixtures/lrclib/catalog.json`) : entrées INVENTÉES et comportements scénarisés.
/// `Decodable` seulement : rien de ce module ne réencode un texte de paroles.
public struct FakeCatalog: Decodable, Sendable {
    public struct Record: Decodable, Sendable {
        public var id: Int
        public var trackName: String
        public var artistName: String
        public var albumName: String?
        public var duration: Double?
        public var instrumental: Bool?
        public var plainLyrics: String?
        public var syncedLyrics: String?
    }
    /// S'applique quand `track_name` (get/search) ou `q` vaut `trackName` (insensible à la casse) ; `times` = nombre
    /// d'applications avant de laisser passer (absent ou 0 = toujours) ; `delaySeconds` = lenteur avant la réponse.
    public struct Behaviour: Decodable, Sendable {
        public var trackName: String
        public var status: Int?
        public var retryAfter: String?
        public var delaySeconds: Double?
        public var times: Int?
    }
    public var note: String?
    public var records: [Record]
    public var behaviours: [Behaviour]?
}

/// Moteur HTTP du faux LRCLIB, sans réseau : `/api/get`, `/api/get/{id}`, `/api/search`, plus `/_fake/log`, `/_fake/reset`,
/// `/_fake/quit`. Partagé par `pf-fake-lrclib` (sockets) et par le transport en processus de l'app (DEBUG).
public final class FakeLRCLIBEngine: @unchecked Sendable {
    public struct Response: Sendable {
        public var status: Int
        public var headers: [(String, String)]
        public var body: Data
        /// Lenteur à appliquer AVANT d'envoyer la réponse (le moteur ne dort pas lui-même).
        public var delay: Double
        public var shouldQuit: Bool
    }

    /// Journal des requêtes (métadonnées seulement : jamais de paroles).
    public struct LogEntry: Sendable, Encodable {
        public var t: Double
        public var method: String
        public var path: String
        public var query: [String: String]
        public var status: Int
        public var delay: Double
    }

    private let lock = NSLock()
    private let catalog: FakeCatalog
    private var behaviourUses: [Int: Int] = [:]
    private var log: [LogEntry] = []
    private let origin = Date()

    /// Dossier des pochettes INVENTÉES servies par `GET /art/<nom>.png` (autotest des couleurs de pochette).
    public var artDirectory: String?

    public init(catalog: FakeCatalog) { self.catalog = catalog }

    /// `Fixtures/artwork` cherché depuis le dossier courant puis depuis l'exécutable.
    public static func defaultArtDirectory() -> String? {
        var candidates = ["Fixtures/artwork"]
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 { candidates.append(dir.appendingPathComponent("Fixtures/artwork").path); dir.deleteLastPathComponent() }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    public static func loadCatalog(at path: String) throws -> FakeCatalog {
        try JSONDecoder().decode(FakeCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// Cherche `Fixtures/lrclib/catalog.json` depuis le dossier courant puis en remontant depuis l'exécutable.
    public static func defaultCatalogPath(executable: String = CommandLine.arguments[0]) -> String? {
        var candidates = ["Fixtures/lrclib/catalog.json"]
        var dir = URL(fileURLWithPath: executable).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<7 {
            candidates.append(dir.appendingPathComponent("Fixtures/lrclib/catalog.json").path)
            dir.deleteLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    public var recordCount: Int { catalog.records.count }

    public var requestLog: [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        behaviourUses = [:]
        log = []
    }

    /// Traite `GET <path>?<query>` ; `rawTarget` = chemin + requête tels que reçus.
    public func handle(method: String, rawTarget: String) -> Response {
        // Référence relative (« /chemin?requête ») : aucun littéral d'URL dans ce module (D12, `strings` de la release).
        let components = URLComponents(string: rawTarget)
        let path = components?.path ?? rawTarget
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return handle(method: method, path: path, query: query)
    }

    public func handle(method: String, path: String, query: [String: String]) -> Response {
        lock.lock(); defer { lock.unlock() }
        var response = route(method: method, path: path, query: query)
        if let b = behaviour(for: query) {
            response.delay = b.delaySeconds ?? 0
            if let status = b.status {
                response.status = status
                response.headers = [("Content-Type", "application/json")]
                if let ra = b.retryAfter { response.headers.append(("Retry-After", ra)) }
                response.body = Self.json(["code": status, "name": Self.statusName(status), "message": "comportement scénarisé du faux serveur"])
            }
        }
        if !path.hasPrefix("/_fake/") {
            let t = Date().timeIntervalSince(origin)
            log.append(LogEntry(t: (t * 1000).rounded() / 1000, method: method, path: path, query: query, status: response.status, delay: response.delay))
        }
        return response
    }

    // MARK: Routes

    private func route(method: String, path: String, query: [String: String]) -> Response {
        guard method == "GET" else { return Self.error(405, "MethodNotAllowed") }
        switch path {
        case "/api/get":
            guard let record = findExact(query) else { return Self.error(404, "TrackNotFound", "Failed to find specified track") }
            return Self.ok(Self.json(Self.dict(record)))
        case "/api/search":
            return Self.ok(Self.json(search(query).map(Self.dict)))
        case "/_fake/log":
            let data = (try? JSONEncoder().encode(log)) ?? Data("[]".utf8)
            return Self.ok(data)
        case "/_fake/reset":
            behaviourUses = [:]; log = []
            return Self.ok(Self.json(["ok": true]))
        case "/_fake/quit":
            var r = Self.ok(Self.json(["ok": true, "quit": true]))
            r.shouldQuit = true
            return r
        default:
            if path.hasPrefix("/art/"), path.hasSuffix(".png"), let dir = artDirectory {
                let name = String(path.dropFirst("/art/".count).dropLast(".png".count))
                guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                      let data = FileManager.default.contents(atPath: dir + "/" + name + ".png") else { return Self.error(404, "NotFound") }
                // `?delay=<s>` : lenteur de la réponse (autotest de l'annulation au changement de titre)
                return Response(status: 200, headers: [("Content-Type", "image/png")], body: data, delay: min(10, Double(query["delay"] ?? "") ?? 0), shouldQuit: false)
            }
            if path.hasPrefix("/api/get/"), let id = Int(path.dropFirst("/api/get/".count)) {
                guard let record = catalog.records.first(where: { $0.id == id }) else { return Self.error(404, "TrackNotFound", "Failed to find specified track") }
                return Self.ok(Self.json(Self.dict(record)))
            }
            return Self.error(404, "NotFound")
        }
    }

    private func behaviour(for query: [String: String]) -> FakeCatalog.Behaviour? {
        let wanted = (query["track_name"] ?? query["q"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        for (i, b) in (catalog.behaviours ?? []).enumerated() where b.trackName.lowercased() == wanted {
            let used = behaviourUses[i, default: 0]
            if let times = b.times, times > 0, used >= times { continue }
            behaviourUses[i] = used + 1
            return b
        }
        return nil
    }

    /// `/api/get` : titre et artiste égaux (insensibles à la casse), durée à ± 2 s si les deux sont connues (comme LRCLIB).
    private func findExact(_ q: [String: String]) -> FakeCatalog.Record? {
        guard let title = q["track_name"]?.lowercased(), let artist = q["artist_name"]?.lowercased() else { return nil }
        let duration = q["duration"].flatMap(Double.init)
        return catalog.records.first { r in
            guard r.trackName.lowercased() == title, r.artistName.lowercased() == artist else { return false }
            if let d = duration, let rd = r.duration { return abs(d - rd) <= 2 }
            return true
        }
    }

    /// `/api/search` : `track_name` contenu dans le titre, `artist_name` contenu dans l'artiste ; ou `q` (tous les mots).
    private func search(_ q: [String: String]) -> [FakeCatalog.Record] {
        let title = (q["track_name"] ?? "").lowercased()
        let artist = (q["artist_name"] ?? "").lowercased()
        let words = (q["q"] ?? "").lowercased().split(separator: " ").map(String.init)
        return Array(catalog.records.filter { r in
            let hay = "\(r.trackName) \(r.artistName) \(r.albumName ?? "")".lowercased()
            if !words.isEmpty { return words.allSatisfy { hay.contains($0) } }
            guard !title.isEmpty else { return false }
            return r.trackName.lowercased().contains(title) && (artist.isEmpty || r.artistName.lowercased().contains(artist))
        }.prefix(20))
    }

    // MARK: Encodage (dictionnaires : aucun type Encodable ne porte de texte de paroles)

    private static func dict(_ r: FakeCatalog.Record) -> [String: Any] {
        [
            "id": r.id, "name": r.trackName, "trackName": r.trackName, "artistName": r.artistName,
            "albumName": r.albumName as Any, "duration": r.duration as Any, "instrumental": r.instrumental ?? false,
            "plainLyrics": r.plainLyrics as Any, "syncedLyrics": r.syncedLyrics as Any,
        ].mapValues { ($0 as? String) == nil && ($0 as? Double) == nil && ($0 as? Int) == nil && ($0 as? Bool) == nil ? NSNull() : $0 }
    }

    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static func ok(_ body: Data) -> Response {
        Response(status: 200, headers: [("Content-Type", "application/json")], body: body, delay: 0, shouldQuit: false)
    }

    private static func error(_ status: Int, _ name: String, _ message: String = "") -> Response {
        Response(status: status, headers: [("Content-Type", "application/json")],
                 body: json(["code": status, "name": name, "message": message]), delay: 0, shouldQuit: false)
    }

    public static func statusName(_ status: Int) -> String {
        switch status {
        case 404: return "TrackNotFound"
        case 429: return "TooManyRequests"
        case 503: return "ServerOverloaded"
        default: return "Error\(status)"
        }
    }

    public static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}
