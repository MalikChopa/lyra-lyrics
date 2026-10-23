#if DEBUG
import Foundation
import LyricsCore
import PlayerKit

/// Commande de contrôle (DEBUG seulement, absente de la version publiée) : fait passer une liste de titres, tels que Spotify les
/// donne, dans le VRAI chemin de recherche de l'app (`LyricsService` → `LRCLIBClient` → `RequestGate` → `TrackMatcher`) vers le VRAI
/// lrclib.net, et imprime pour chaque titre les requêtes faites, les statuts, le candidat retenu, l'état atteint et la raison d'un échec.
///
/// `LyraLyrics --lookup-check <titres.json> [--label avant|apres] [--cap 60] [--spacing 1.05] [--only 1,5,7] [--skip 1,2] [--wait 40]`
/// - Les durées passent par `SpotifyNotificationParser` (millisecondes → secondes, comme la notification réelle).
/// - Plafond GLOBAL de requêtes réelles partagé entre les exécutions : fichier `/tmp/lyra-101/requests.count` (défaut 60) ; au-delà,
///   la requête n'est pas envoyée. Au moins 1 s entre deux requêtes réelles ; User-Agent de l'app.
/// - Rien n'est écrit sur disque sauf `/tmp/lyra-101/lookup-<label>.log` : statuts, durées, identifiants et DURÉES des candidats,
///   JAMAIS un texte de paroles. L'index disque de l'app n'est pas utilisé.
enum LookupCheck {
    struct Input: Decodable {
        var title: String
        var artist: String
        var album: String?
        var durationMs: Double?
    }

    static let directory = "/tmp/lyra-101"

    static func value(_ flag: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func runAndExit() -> Never {
        Task {
            let code = await run()
            exit(code)
        }
        dispatchMain()
    }

    static func run() async -> Int32 {
        guard let path = value("--lookup-check"), let data = FileManager.default.contents(atPath: path),
              let inputs = try? JSONDecoder().decode([Input].self, from: data) else {
            FileHandle.standardError.write(Data("--lookup-check <titres.json> : fichier illisible\n".utf8))
            return 64
        }
        let label = value("--label") ?? "essai"
        let cap = Int(value("--cap") ?? "") ?? 60
        let spacing = Double(value("--spacing") ?? "") ?? 1.05
        let waitSeconds = Double(value("--wait") ?? "") ?? 40
        let only = Set((value("--only") ?? "").split(separator: ",").compactMap { Int($0) })
        let skip = Set((value("--skip") ?? "").split(separator: ",").compactMap { Int($0) })
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let sink = Sink(path: "\(directory)/lookup-\(label).log")
        let agent = LyricsService.userAgent
        let transport = RecordingTransport(inner: URLSessionTransport(userAgent: agent), cap: cap, sink: sink)
        let client = LRCLIBClient(transport: transport, userAgent: agent)
        let notes = NoteBox()
        let service = LyricsService(client: client, indexURL: nil, hasher: { $0 }, titlesBeforeBreaker: 3, minSpacing: spacing,
                                    log: { notes.add($0) })
        sink.write(["ev": "start", "label": label, "tracks": inputs.count, "cap": cap, "spacing": spacing, "userAgent": agent])
        var summary: [String: Int] = [:]
        var misses: [String] = []
        var requestsTotal = 0
        for (index, input) in inputs.enumerated() {
            let number = index + 1
            if (!only.isEmpty && !only.contains(number)) || skip.contains(number) { continue }
            // Conversion de l'app elle-même : notification Spotify (durée en millisecondes) → TrackInfo, comme `AppModel.ingest`.
            var info: [AnyHashable: Any] = ["Player State": "Playing", "Name": input.title, "Artist": input.artist, "Track ID": "spotify:track:check\(number)"]
            if let album = input.album { info["Album"] = album }
            if let ms = input.durationMs { info["Duration"] = NSNumber(value: ms) }
            guard let reading = SpotifyNotificationParser.parse(userInfo: info), let pt = reading.track else { continue }
            let track = TrackInfo(title: pt.name, artist: pt.artist, album: pt.album, duration: pt.durationSeconds, sourceID: pt.trackID, player: "spotify")
            transport.begin(number: number)
            notes.reset()
            let result = ResultBox()
            let started = Date()
            await service.lookup(track) { event in result.add(event) }
            var verdict = "en attente"
            while Date().timeIntervalSince(started) < waitSeconds {
                if let terminal = result.terminal { verdict = terminal; break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if verdict == "en attente" { verdict = result.terminal ?? "pas de réponse en \(Int(waitSeconds)) s (\(result.lastKind))" }
            await service.cancel()
            let requests = transport.take()
            requestsTotal += requests.count
            let kind = verdict.split(separator: ":").first.map(String.init) ?? verdict
            summary[kind, default: 0] += 1
            if kind != "synced" { misses.append("\(number) \(input.title) / \(input.artist) → \(verdict)") }
            sink.write(["ev": "track", "n": number, "title": input.title, "artist": input.artist, "album": input.album ?? "",
                        "durationS": track.duration ?? 0, "requests": requests.count, "calls": requests.map(\.line),
                        "state": verdict, "elapsedMs": Int(Date().timeIntervalSince(started) * 1000), "notes": notes.lines])
            // Un titre ne doit pas enchaîner sur le suivant sans pause : 1 s au moins entre deux titres (en plus de l'espacement des requêtes).
            try? await Task.sleep(for: .milliseconds(1100))
        }
        sink.write(["ev": "summary", "label": label, "states": summary, "requests": requestsTotal, "globalCount": transport.globalCount(),
                    "misses": misses])
        print("RESUME \(label): \(summary.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")) ; requêtes de cette exécution \(requestsTotal) ; total global \(transport.globalCount())")
        for m in misses { print("MANQUE \(m)") }
        return 0
    }

    // MARK: Outils

    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private let handle: FileHandle?
        init(path: String) {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            handle = FileHandle(forWritingAtPath: path)
            try? handle?.seekToEnd()
        }
        func write(_ record: [String: Any]) {
            lock.lock(); defer { lock.unlock() }
            guard let d = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), let line = String(data: d, encoding: .utf8) else { return }
            print(line); fflush(stdout)
            handle?.write(Data((line + "\n").utf8))
        }
    }

    final class NoteBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func reset() { lock.withLock { items = [] } }
        func add(_ record: [String: String]) {
            let keep = ["lookup", "etape", "statut", "resultat", "verdict", "choix", "provenance", "raison", "candidats", "id", "ms"]
            let text = keep.compactMap { k in record[k].flatMap { $0.isEmpty ? nil : "\(k)=\($0)" } }.joined(separator: " ")
            lock.withLock { items.append(text) }
        }
        var lines: [String] { lock.withLock { items } }
    }

    final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var terminal: String?
        private(set) var lastKind = "aucun événement"
        func add(_ event: LyricsServiceEvent) {
            lock.lock(); defer { lock.unlock() }
            switch event {
            case .found(let l, _):
                let kind = l.isSynced ? "synced" : (l.plainText != nil ? "plain" : "instrumental")
                terminal = "\(kind): \(l.provenance)"
            case .notFound(let reason):
                terminal = "notFound: \(reason)"
            case .stalled(let reason):
                terminal = "stalled: \(reason)"
            case .busy(let s, let reason): lastKind = "busy \(reason) \(Int(s)) s"
            case .offline: lastKind = "offline"
            case .searching: lastKind = "searching"
            case .retrying: lastKind = "retrying"
            default: lastKind = "\(event)"
            }
        }
    }

    struct Call: Sendable { var line: String }

    /// Enveloppe le transport réel : plafond global, espacement, journal des réponses (statut, durée, identifiants, durées et présence
    /// de LRC des candidats — jamais de texte).
    final class RecordingTransport: LRCLIBTransport, @unchecked Sendable {
        let inner: LRCLIBTransport
        let cap: Int
        let sink: Sink
        private let lock = NSLock()
        private var calls: [Call] = []
        private var number = 0
        private var lastSent: Date?
        static let counterPath = "\(LookupCheck.directory)/requests.count"

        init(inner: LRCLIBTransport, cap: Int, sink: Sink) { self.inner = inner; self.cap = cap; self.sink = sink }

        func begin(number: Int) { lock.withLock { self.number = number; calls = [] } }
        func take() -> [Call] { lock.withLock { let c = calls; calls = []; return c } }
        func globalCount() -> Int { Int((try? String(contentsOfFile: Self.counterPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0 }

        private func reserve() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let n = globalCount()
            if n >= cap { return false }
            try? String(n + 1).write(toFile: Self.counterPath, atomically: true, encoding: .utf8)
            return true
        }

        func send(_ request: URLRequest, timeout: Double) async throws -> HTTPResponse {
            guard reserve() else { throw LRCLIBError.transport("plafond de \(cap) requêtes réelles atteint : requête NON envoyée") }
            // Au moins 1 s entre deux requêtes réelles (en plus de l'espacement de la porte).
            let wait: Double = lock.withLock {
                guard let last = lastSent else { return 0 }
                return max(0, 1.0 - Date().timeIntervalSince(last))
            }
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            lock.withLock { lastSent = Date() }
            let url = request.url
            let keys = URLComponents(url: url ?? URL(string: "http://x")!, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name).joined(separator: "+") ?? ""
            let path = url?.path ?? "?"
            let t0 = Date()
            do {
                let response = try await inner.send(request, timeout: timeout)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                var line = "\(path)[\(keys)] \(response.status) \(ms) ms"
                if let ra = response.header("Retry-After") { line += " retry-after=\(ra)" }
                if response.status == 200 { line += " " + Self.describe(response.body) }
                record(line)
                return response
            } catch {
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                record("\(path)[\(keys)] erreur \(String(describing: error).prefix(60)) \(ms) ms")
                throw error
            }
        }

        private func record(_ line: String) { lock.withLock { calls.append(Call(line: line)) } }

        /// « 3 candidats : 101(s,198) 102(p,200) … » — s = LRC, p = texte seul, - = rien ; durée entre parenthèses ; aucun texte.
        static func describe(_ body: Data) -> String {
            guard let any = try? JSONSerialization.jsonObject(with: body) else { return "corps illisible" }
            let list: [[String: Any]] = (any as? [[String: Any]]) ?? ((any as? [String: Any]).map { [$0] } ?? [])
            func flag(_ d: [String: Any]) -> String {
                let s = (d["syncedLyrics"] as? String).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                let p = (d["plainLyrics"] as? String).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                return s ? "s" : (p ? "p" : (d["instrumental"] as? Bool == true ? "i" : "-"))
            }
            let items = list.prefix(8).map { d -> String in
                let id = (d["id"] as? Int).map(String.init) ?? "?"
                let dur = (d["duration"] as? Double).map { String(Int($0.rounded())) } ?? "?"
                return "\(id)(\(flag(d)),\(dur))"
            }
            return "\(list.count) candidat(s) : " + items.joined(separator: " ")
        }
    }
}
#endif
