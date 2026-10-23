#if DEBUG
import AppKit
import PlayerKit
import LyricsCore
import os

/// Mode `--measure-e2e <fichier>` (DEBUG uniquement, absent de la version publiée, D12) : mesures du bout en bout RÉEL (J4).
///
/// - Journal JSON (une ligne par enregistrement) dans /tmp/pf-j4/ SEULEMENT (refus sinon) : titres réels possibles (D6), JAMAIS de paroles.
/// - Par changement de titre : lecteur, instant de l'événement de la source, instant après arbitrage/anti-rebond, instant où l'état
///   est atteint, délais, état, synchronisé oui/non (`"ev":"e2e"`).
/// - D11 : les premières lignes affichées de chaque titre sont gardées EN MÉMOIRE (jamais écrites), puis, sur la notification
///   `pf.debug.e2e-final`, cherchées dans tous les lieux de D11 ; seuls des COMPTES sont écrits. Un témoin (chaîne inventée) est planté
///   puis retrouvé dans chaque lieu où l'on peut écrire, pour prouver que la recherche voit.
/// - `--sample spotify|music --sample-log <fichier> [--period-ms 250]` : relevé AppleScript à 4 Hz (exécuteur indépendant) comparé à la
///   position estimée PAR LE MODÈLE de l'app (mesures 1 et 2 du §5, lignes `R` lues par `scripts/measure-sync.sh`).
/// - `--est-log <fichier>` : l'estimée du modèle à 10 Hz (lignes `E wall=… est=… state=…`), pour comparer à une référence EXTERNE
///   (utile quand l'app n'a pas l'autorisation Automatisation d'un lecteur : Spotify en mode notification seule, J4).
final class E2ESink: @unchecked Sendable {
    static let shared = E2ESink()
    private var handle: FileHandle?
    private let lock = NSLock()

    func open(path: String) -> Bool {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        return handle != nil
    }

    func write(_ record: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return }
        var r = record
        r["wall"] = (Date().timeIntervalSince1970 * 1000).rounded()          // ms depuis 1970 : comparable aux commandes du pilote
        r["t"] = (ProcessClock.seconds() * 1000).rounded() / 1000
        guard let data = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) else { return }
        handle.write(data + Data("\n".utf8))
    }

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return handle != nil }
}

@MainActor
final class E2EMeasure {
    static let allowedPrefix = "/tmp/pf-j4/"

    private let controller: AppController
    private var model: AppModel { controller.model }
    private let args: [String]

    // Chronologie du titre courant
    private struct Stamp { var wall: Double; var t: Double }
    private var srcPending: [PlayerID: Stamp] = [:]
    private var lastOut: (stamp: Stamp, player: String)?
    private struct Current {
        var player: String; var title: String; var artist: String
        var src: Stamp?; var out: Stamp?; var begin: Stamp
        var state: String?; var lineReported = false; var shown: Stamp?
        var fragments = 0
    }
    private var current: Current?
    /// D11 : fragments EN MÉMOIRE SEULEMENT (jamais écrits, jamais journalisés).
    private var fragments: Set<String> = []

    // Échantillonneur (mesures 1 et 2)
    private var sampleLog: ProbeLog?
    private let sampler = ScriptExecutor(backend: AppleEventBackend())
    private var sampleTimer: DispatchSourceTimer?
    private var estLog: ProbeLog?
    private var estTimer: DispatchSourceTimer?

    init?(args: [String], controller: AppController) {
        guard let i = args.firstIndex(of: "--measure-e2e"), i + 1 < args.count else { return nil }
        let path = URL(fileURLWithPath: args[i + 1]).standardizedFileURL.path
        guard path.hasPrefix(Self.allowedPrefix) else {
            FileHandle.standardError.write(Data("--measure-e2e : seul un fichier sous \(Self.allowedPrefix) est accepté (titres réels)\n".utf8))
            exit(64)
        }
        guard E2ESink.shared.open(path: path) else { return nil }
        self.args = args
        self.controller = controller
    }

    private func value(of flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func start() {
        let sink = E2ESink.shared
        sink.write(["ev": "start", "pid": Int(getpid()), "realPlayers": controller.hub != nil, "args": args.dropFirst().joined(separator: " "),
                    "os": ProcessInfo.processInfo.operatingSystemVersionString])
        model.diagMayLogTitles = true            // titres réels : fichier sous /tmp/pf-j4/ uniquement
        model.diag = { [weak self] record in MainActor.assumeIsolated { self?.onModel(record) } }
        if let hub = controller.hub {
            hub.monitor.tap = { [weak self] event in self?.onSource(event) }
            hub.monitor.tapOutput = { [weak self] event in self?.onOutput(event) }
        }
        probePermissions(when: "start")
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("pf.debug.e2e-final"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.final() }
        }
        if let path = value(of: "--est-log"), let log = ProbeLog(path: path) {
            estLog = log
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(100))
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.logEstimate() } }
            timer.resume()
            estTimer = timer
        }
        if let raw = value(of: "--sample"), let p = PlayerID(rawValue: raw), let path = value(of: "--sample-log") {
            sampleLog = ProbeLog(path: path)
            startSampling(p, periodMs: Int(value(of: "--period-ms") ?? "") ?? 250)
        }
    }

    // MARK: Événements

    private func stamp() -> Stamp { Stamp(wall: (Date().timeIntervalSince1970 * 1000).rounded(), t: ProcessClock.seconds()) }

    private func onSource(_ event: PlayerEvent) {
        var rec: [String: Any] = ["ev": "src"]
        switch event {
        case .trackChanged(let r), .reading(let r):
            let kind: String
            if case .trackChanged = event { kind = "trackChanged" } else { kind = "reading" }
            rec["kind"] = kind; rec["player"] = r.player.rawValue; rec["state"] = r.state.rawValue
            rec["unreadable"] = r.trackUnreadable
            if let p = r.positionSeconds { rec["pos"] = (p * 1000).rounded() / 1000 }
            if let t = r.track {
                rec["id"] = t.trackID ?? ""; rec["title"] = t.name; rec["artist"] = t.artist
                rec["dur"] = t.durationSeconds.map { ($0 * 1000).rounded() / 1000 } ?? -1
            }
            if kind == "trackChanged" || srcPending[r.player] == nil { srcPending[r.player] = stamp() }
        case .stopped(let p): rec["kind"] = "stopped"; rec["player"] = p.rawValue
        case .permissionNeeded(let p): rec["kind"] = "permissionNeeded"; rec["player"] = p.rawValue
        case .error(let p, let e): rec["kind"] = "error"; rec["player"] = p.rawValue; rec["error"] = "\(e)"
        }
        E2ESink.shared.write(rec)
    }

    private func onOutput(_ event: PlayerEvent) {
        var rec: [String: Any] = ["ev": "out"]
        switch event {
        case .trackChanged(let r):
            rec["kind"] = "trackChanged"; rec["player"] = r.player.rawValue; rec["title"] = r.track?.name ?? ""
            lastOut = (stamp(), r.player.rawValue)
        case .reading(let r): rec["kind"] = "reading"; rec["player"] = r.player.rawValue
        case .stopped(let p): rec["kind"] = "stopped"; rec["player"] = p.rawValue
        case .permissionNeeded(let p): rec["kind"] = "permissionNeeded"; rec["player"] = p.rawValue
        case .error(let p, let e): rec["kind"] = "error"; rec["player"] = p.rawValue; rec["error"] = "\(e)"
        }
        E2ESink.shared.write(rec)
    }

    private func onModel(_ record: [String: Any]) {
        var r = record
        r["ev"] = "model"
        E2ESink.shared.write(r)
        switch record["event"] as? String {
        case "track":
            let player = (record["player"] as? String) ?? ""
            let src = PlayerID(rawValue: player).flatMap { srcPending.removeValue(forKey: $0) }
            let out = (lastOut?.player == player) ? lastOut?.stamp : nil
            current = Current(player: player, title: model.title ?? "", artist: model.artist ?? "", src: src, out: out, begin: stamp())
        case "display":
            guard var c = current, let mode = record["display"] as? String, mode != "searching", mode != "nothing" else { return }
            if mode == "unsynced" { keepFragment(model.plainText.split(separator: "\n").map(String.init), &c) }
            if c.state != mode {
                let update = c.state != nil
                c.state = mode
                let now = stamp()
                if c.shown == nil { c.shown = now }
                var rec: [String: Any] = ["ev": "e2e", "player": c.player, "title": c.title, "artist": c.artist, "state": mode,
                                          "synced": mode == "synced", "update": update, "lookup": (record["lookup"] as? String) ?? "",
                                          "sinceModelTrackMs": ((now.t - c.begin.t) * 1000).rounded()]
                if let o = c.out { rec["sinceOutMs"] = ((now.t - o.t) * 1000).rounded() }
                if let s = c.src { rec["sinceSrcMs"] = ((now.t - s.t) * 1000).rounded(); rec["srcWall"] = s.wall }
                if let s = c.src, let o = c.out { rec["debounceMs"] = ((o.t - s.t) * 1000).rounded() }
                E2ESink.shared.write(rec)
            }
            current = c
        case "line":
            guard var c = current, let index = record["index"] as? Int, index >= 0 else { return }
            keepFragment([model.visibleLines[1]], &c)
            if !c.lineReported {
                c.lineReported = true
                let now = stamp()
                var rec: [String: Any] = ["ev": "e2e-line", "player": c.player, "index": index]
                if let s = c.src { rec["sinceSrcMs"] = ((now.t - s.t) * 1000).rounded() }
                if let o = c.out { rec["sinceOutMs"] = ((now.t - o.t) * 1000).rounded() }
                E2ESink.shared.write(rec)
            }
            current = c
        default: break
        }
    }

    /// Garde en mémoire (jamais écrit) jusqu'à 2 lignes d'au moins 12 caractères par titre pour la recherche D11.
    private func keepFragment(_ candidates: [String], _ c: inout Current) {
        for line in candidates where c.fragments < 2 {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 12, fragments.insert(trimmed).inserted { c.fragments += 1 }
        }
    }

    // MARK: Autorisations

    private func probePermissions(when: String) {
        Task { @MainActor in
            let started = ContinuousClock.now
            async let s = PlayerHub.probe(.spotify, timeout: 5)
            async let m = PlayerHub.probe(.music, timeout: 5)
            let (sp, mu) = await (s, m)
            func name(_ a: AutomationStatus) -> String {
                if case .unknown(-1) = a { return "hung(>5s)" }
                return "\(a)"
            }
            let ms = Double((ContinuousClock.now - started).components.attoseconds) / 1e15
            E2ESink.shared.write(["ev": "perm", "when": when, "spotify": name(sp), "music": name(mu), "afterMs": ms.rounded()])
        }
    }

    /// Estimée du modèle, avec l'heure murale en millisecondes (comparable à celle d'un échantillonneur externe).
    private func logEstimate() {
        guard let log = estLog else { return }
        let wall = (Date().timeIntervalSince1970 * 1000).rounded()
        guard let track = model.track, model.display.screen != .nothing else { log.write("E wall=\(Int(wall)) none"); return }
        let est = model.positionEstimate(at: .now)
        log.write("E wall=\(Int(wall)) player=\(track.player) state=\(model.isPaused ? "paused" : "playing") est=\(String(format: "%.4f", est)) id=\(track.sourceID ?? "nil")")
    }

    // MARK: Échantillonneur (mesures 1 et 2 du §5)

    private func startSampling(_ p: PlayerID, periodMs: Int) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(periodMs))
        timer.setEventHandler { [weak self] in Task { @MainActor in await self?.sampleOnce(p) } }
        timer.resume()
        sampleTimer = timer
    }

    private func sampleOnce(_ p: PlayerID) async {
        guard let log = sampleLog else { return }
        guard WorkspacePresence().isRunning(p) else { log.write("R absent"); return }
        let t0 = ContinuousClock.now
        let outcome = await sampler.run(.full(p))
        let t1 = ContinuousClock.now
        let mid = t0 + (t1 - t0) / 2
        let lat = String(format: "%.1f", milliseconds(t1 - t0))
        let ts = String(format: "%.4f", log.seconds(mid))
        switch outcome.flatMap({ PlayerScripts.parseReading(player: p, values: $0) }) {
        case .success(let r):
            var est = "nil"
            if model.track?.player == p.rawValue, model.display.screen != .nothing { est = String(format: "%.4f", model.positionEstimate(at: mid)) }
            log.write("R t=\(ts) lat=\(lat) state=\(r.state.rawValue) pos=\(r.positionSeconds.map { String(format: "%.4f", $0) } ?? "nil") est=\(est) id=\(r.track?.trackID ?? r.track?.identity ?? "nil")")
        case .failure(let e): log.write("R t=\(ts) lat=\(lat) error=\(e) code=\(e.code)")
        }
    }

    // MARK: Fin : autorisations + D11

    private func final() {
        probePermissions(when: "end")
        let needles = fragments.map { Data($0.utf8) }
        let clipboard = NSPasteboard.general.string(forType: .string).map { clip in fragments.filter { clip.contains($0) }.count } ?? 0
        let witness = "PFJ4-TEMOIN-" + UUID().uuidString
        // Témoin dans le journal unifié (visible : privacy public, chaîne inventée).
        Logger(subsystem: "io.github.malikmoussaoui.lyra-lyrics", category: "d11-temoin").notice("\(witness, privacy: .public)")
        let count = fragments.count
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            let result = D11Scanner.run(needles: needles, witness: witness)
            var rec: [String: Any] = ["ev": "d11", "fragments": count, "clipboard": clipboard]
            rec.merge(result) { a, _ in a }
            E2ESink.shared.write(rec)
        }
    }
}

/// Recherche D11 : compte les occurrences, n'écrit jamais de texte. Lieux où une donnée pourrait traîner (+ HTTPStorages, Cookies).
enum D11Scanner {
    static func run(needles: [Data], witness: String) -> [String: Any] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let bundle = "io.github.malikmoussaoui.lyra-lyrics"
        let lib = home.appendingPathComponent("Library")
        let roots: [(String, URL, Bool)] = [      // (nom, dossier, on peut y planter un témoin)
            ("appSupport", lib.appendingPathComponent("Application Support/\(bundle)"), true),
            ("caches", lib.appendingPathComponent("Caches/\(bundle)"), true),
            ("preferences", lib.appendingPathComponent("Preferences"), false),
            ("savedState", lib.appendingPathComponent("Saved Application State"), false),
            ("tmpdir", URL(fileURLWithPath: NSTemporaryDirectory()), true),
            ("logs", lib.appendingPathComponent("Logs"), false),
            ("httpStorages", lib.appendingPathComponent("HTTPStorages"), false),
            ("cookies", lib.appendingPathComponent("Cookies"), false),
            ("pf-j4", URL(fileURLWithPath: "/tmp/pf-j4"), true),
        ]
        // Plante les témoins.
        var planted: [URL] = []
        var createdDirs: [URL] = []
        for (_, dir, writable) in roots where writable {
            if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true); createdDirs.append(dir) }
            let f = dir.appendingPathComponent("pf-j4-temoin.txt")
            if (try? Data(witness.utf8).write(to: f)) != nil { planted.append(f) }
        }
        let witnessNeedle = Data(witness.utf8)
        var real: [String: Int] = [:], wit: [String: Int] = [:]
        var hitFiles: [String] = []
        var scanned = 0, skipped = 0
        for (name, dir, _) in roots {
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { real[name] = 0; wit[name] = 0; continue }
            var r = 0, w = 0
            for case let url as URL in en {
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
                if (v.fileSize ?? 0) > 30_000_000 { skipped += 1; continue }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { skipped += 1; continue }
                scanned += 1
                var fileHits = 0
                for n in needles { fileHits += occurrences(of: n, in: data) }
                if fileHits > 0 { r += fileHits; hitFiles.append(name + "/" + url.lastPathComponent) }
                w += occurrences(of: witnessNeedle, in: data)
            }
            real[name] = r; wit[name] = w
        }
        for f in planted { try? fm.removeItem(at: f) }
        for d in createdDirs where (try? fm.contentsOfDirectory(atPath: d.path))?.isEmpty == true { try? fm.removeItem(at: d) }

        // Journal unifié (processus de l'app, niveaux info et debug compris).
        var logReal = 0, logWitness = 0, logBytes = 0
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["show", "--last", "120m", "--info", "--debug", "--style", "compact", "--predicate", "process == \"LyraLyrics\""]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            logBytes = data.count
            for n in needles { logReal += occurrences(of: n, in: data) }
            logWitness = occurrences(of: witnessNeedle, in: data)
        }
        return ["real": real, "witness": wit, "hitFiles": hitFiles, "filesScanned": scanned, "skippedUnreadableOrBig": skipped,
                "unifiedLog": ["real": logReal, "witness": logWitness, "bytes": logBytes],
                "realTotal": real.values.reduce(0, +) + logReal]
    }

    static func occurrences(of needle: Data, in data: Data) -> Int {
        guard !needle.isEmpty, data.count >= needle.count else { return 0 }
        var count = 0
        var from = data.startIndex
        while let r = data.range(of: needle, in: from..<data.endIndex) {
            count += 1
            from = r.upperBound
        }
        return count
    }
}
#endif
