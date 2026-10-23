#if DEBUG
import AppKit
import PlayerKit

/// Mode `--probe-players` (DEBUG uniquement, jamais dans la version publiée, D12).
/// Journal de sonde : titres réels possibles (D6, §3.2) ; fichier HORS projet (/tmp/pf-j1/), détruit en fin de jalon. Aucune parole.
///
/// Arguments :
///   --probe-players [--probe-log <fichier>] [--ask spotify|music]
///   [--sample spotify|music [--period-ms 250]]           mesures 1 et 2 du §5 (lignes `R`)
///   [--bench-latency spotify|music [--n 100]]             mesure 4
///   [--bench-transport spotify|music [--seconds 180] [--period-ms 250]]   mesure 5
final class ProbeLog: @unchecked Sendable {
    private let handle: FileHandle
    private let origin = ContinuousClock.now
    private let lock = NSLock()
    init?(path: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: path) else { return nil }
        handle = h
    }
    func seconds(_ i: ContinuousClock.Instant) -> Double {
        let d = i - origin
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
    func write(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        handle.write(Data((line + "\n").utf8))
    }
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
    return sorted[max(0, min(sorted.count - 1, rank))]
}

func milliseconds(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

@MainActor
final class ProbeMode {
    private let args: [String]
    private let log: ProbeLog
    private let presence = WorkspacePresence()
    private let executor: ScriptExecutor
    /// Exécuteur INDÉPENDANT pour l'échantillonnage à 4 Hz (référence) : sinon il occupe « le relevé en vol » des sources.
    private let sampler = ScriptExecutor(backend: AppleEventBackend())
    private var monitor: NowPlayingMonitor?
    private var spotify: SpotifySource?
    private var music: MusicSource?
    private var consumer: Task<Void, Never>?
    private var sampleTimer: DispatchSourceTimer?
    // Estimateur (mesure 1 : recalé par les événements de la source, PAS par les relevés d'échantillonnage).
    private var estPos: Double?
    private var estAt: ContinuousClock.Instant?
    private var estPlaying = false
    private var sampled: PlayerID?
    private var transportBench: TransportBench?

    init?(args: [String]) {
        self.args = args
        guard args.contains("--probe-players") else { return nil }
        let path = ProbeMode.value(of: "--probe-log", in: args) ?? "/tmp/pf-j1/probe.log"
        guard let log = ProbeLog(path: path) else { return nil }
        self.log = log
        // Transport du produit : Apple events à la main hors fil principal (retenu, mesure 5) ; `--transport nsas` = repli.
        let backend: ScriptBackend = ProbeMode.value(of: "--transport", in: args) == "nsas" ? NSAppleScriptBackend() : AppleEventBackend()
        executor = ScriptExecutor(backend: backend)
    }

    static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private func player(after flag: String) -> PlayerID? { ProbeMode.value(of: flag, in: args).flatMap { PlayerID(rawValue: $0) } }

    func run() {
        log.write("# probe start macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) pid=\(getpid()) args=\(args.dropFirst().joined(separator: " "))")
        if let p = player(after: "--bench-latency") {
            benchLatency(p, n: Int(ProbeMode.value(of: "--n", in: args) ?? "") ?? 100); return
        }
        if let p = player(after: "--bench-transport") {
            benchTransport(p, seconds: Double(ProbeMode.value(of: "--seconds", in: args) ?? "") ?? 180,
                           periodMs: Int(ProbeMode.value(of: "--period-ms", in: args) ?? "") ?? 250); return
        }
        startEvents()
        if let p = player(after: "--ask") { ask(p) }
        if let p = player(after: "--sample") {
            sampled = p
            startSampling(p, periodMs: Int(ProbeMode.value(of: "--period-ms", in: args) ?? "") ?? 250)
        }
    }

    // MARK: événements

    private func startEvents() {
        let s = SpotifySource(executor: executor, presence: presence)
        let m = MusicSource(executor: executor, presence: presence)
        spotify = s; music = m
        let monitor = NowPlayingMonitor(sources: [s, m])
        self.monitor = monitor
        for p in PlayerID.allCases {
            log.write("P \(p.rawValue) running=\(presence.isRunning(p))")
            let started = ContinuousClock.now
            Task.detached { [log] in
                let status = PermissionProbe.status(for: p)
                log.write("P \(p.rawValue) permission=\(status) after=\(String(format: "%.2f", milliseconds(ContinuousClock.now - started) / 1000)) s")
            }
        }
        let events = monitor.events
        consumer = Task { @MainActor [weak self] in
            for await event in events { self?.handle(event) }
        }
        monitor.start()
    }

    private func handle(_ event: PlayerEvent) {
        let now = ContinuousClock.now
        let t = String(format: "%.3f", log.seconds(now))
        switch event {
        case .trackChanged(let r): log.write("E t=\(t) trackChanged \(describe(r))"); recalibrate(r)
        case .reading(let r): log.write("E t=\(t) reading \(describe(r))"); recalibrate(r)
        case .stopped(let p): log.write("E t=\(t) stopped \(p.rawValue)"); if p == sampled { estPlaying = false }
        case .permissionNeeded(let p): log.write("E t=\(t) permissionNeeded \(p.rawValue)")
        case .error(let p, let e): log.write("E t=\(t) error \(p.rawValue) \(e)")
        }
    }

    private func describe(_ r: PlayerReading) -> String {
        "p=\(r.player.rawValue) state=\(r.state.rawValue) pos=\(r.positionSeconds.map { String(format: "%.3f", $0) } ?? "nil") "
        + "dur=\(r.track?.durationSeconds.map { String(format: "%.3f", $0) } ?? "nil") unreadable=\(r.trackUnreadable) "
        + "id=\(r.track?.trackID ?? "nil") name=\(r.track?.name ?? "nil") artist=\(r.track?.artist ?? "nil") album=\(r.track?.album ?? "nil")"
    }

    private func recalibrate(_ r: PlayerReading) {
        guard r.player == sampled, let pos = r.positionSeconds else { return }
        estPos = pos; estAt = r.at ?? ContinuousClock.now; estPlaying = r.state == .playing
    }

    private func ask(_ p: PlayerID) {
        log.write("A ask \(p.rawValue) (invite attendue)")
        let source: () async -> AutomationStatus = {
            switch p {
            case .spotify: return await SpotifySource(executor: ScriptExecutor(backend: AppleEventBackend()), presence: WorkspacePresence()).requestPermission()
            case .music: return await MusicSource(executor: ScriptExecutor(backend: AppleEventBackend()), presence: WorkspacePresence()).requestPermission()
            }
        }
        Task { @MainActor [log] in
            let started = ContinuousClock.now
            let status = await source()
            log.write("A answer \(p.rawValue) status=\(status) after=\(String(format: "%.2f", milliseconds(ContinuousClock.now - started) / 1000)) s")
        }
    }

    // MARK: mesures 1 et 2 (échantillonnage)

    private func startSampling(_ p: PlayerID, periodMs: Int) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(periodMs))
        timer.setEventHandler { [weak self] in Task { @MainActor in await self?.sampleOnce(p) } }
        timer.resume()
        sampleTimer = timer
    }

    private func sampleOnce(_ p: PlayerID) async {
        guard presence.isRunning(p) else { log.write("R absent"); return }
        let t0 = ContinuousClock.now
        let outcome = await sampler.run(.full(p))
        let t1 = ContinuousClock.now
        let mid = t0 + (t1 - t0) / 2
        let lat = String(format: "%.1f", milliseconds(t1 - t0))
        switch outcome.flatMap({ PlayerScripts.parseReading(player: p, values: $0) }) {
        case .success(let r):
            var est = "nil"
            if let ep = estPos, let ea = estAt {
                let e = estPlaying ? ep + seconds(mid - ea) : ep
                est = String(format: "%.4f", e)
            }
            log.write("R t=\(String(format: "%.4f", log.seconds(mid))) lat=\(lat) state=\(r.state.rawValue) pos=\(r.positionSeconds.map { String(format: "%.4f", $0) } ?? "nil") est=\(est) id=\(r.track?.trackID ?? r.track?.identity ?? "nil")")
        case .failure(let e): log.write("R t=\(String(format: "%.4f", log.seconds(mid))) lat=\(lat) error=\(e) code=\(e.code)")
        }
    }

    private func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }

    // MARK: mesure 4 (latence)

    private func benchLatency(_ p: PlayerID, n: Int) {
        Task { @MainActor in
            var lats: [Double] = []
            var errors = 0
            for _ in 0..<n {
                let t0 = ContinuousClock.now
                let r = await executor.run(.full(p))
                let l = milliseconds(ContinuousClock.now - t0)
                if case .failure(let e) = r { errors += 1; log.write("L error \(e)") } else { lats.append(l) }
            }
            lats.sort()
            let transport = ProbeMode.value(of: "--transport", in: args) ?? "events"
            log.write(String(format: "L %@ transport=%@ n=%d ok=%d err=%d p50=%.2f ms p95=%.2f ms min=%.2f max=%.2f", p.rawValue, transport, n, lats.count, errors,
                             percentile(lats, 0.5), percentile(lats, 0.95), lats.first ?? .nan, lats.last ?? .nan))
            log.write("# done")
            NSApp.terminate(nil)
        }
    }

    // MARK: mesure 5 (transport sous charge)

    private func benchTransport(_ p: PlayerID, seconds total: Double, periodMs: Int) {
        let bench = TransportBench(player: p, presence: presence, log: log)
        transportBench = bench
        bench.run(seconds: total, periodMs: periodMs)
    }
}

/// Banc de la mesure 5 : à chaque tick (toutes les `periodMs`), un relevé de position, en alternant
/// (0) NSAppleScript sur le fil principal, (1) Apple event à la main sur le fil principal, (2) Apple event à la main hors du fil principal.
/// Un « battement » (fil secondaire, toutes les 5 ms) poste un bloc sur la file principale : son retard = gel de l'interface.
@MainActor
final class TransportBench {
    static let labels = ["nsas-main", "events-main", "events-bg"]
    private let player: PlayerID
    private let presence: PlayerPresence
    private let nsas = NSAppleScriptBackend()
    private let log: ProbeLog
    private let state = BenchState()
    private var timer: DispatchSourceTimer?
    private var tick = 0

    init(player: PlayerID, presence: PlayerPresence, log: ProbeLog) {
        self.player = player; self.presence = presence; self.log = log
    }

    func run(seconds total: Double, periodMs: Int) {
        let st = state, lg = log
        let beat = Thread {
            while !st.stopped {
                let label = st.currentLabel()
                let posted = ContinuousClock.now
                DispatchQueue.main.async {
                    let delay = milliseconds(ContinuousClock.now - posted)
                    st.recordBeat(label: label, delayMs: delay)
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        beat.start()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(periodMs))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.onTick() } }
        timer.resume()
        self.timer = timer
        lg.write("# bench-transport \(player.rawValue) seconds=\(total) period=\(periodMs) ms")
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in MainActor.assumeIsolated { self?.finish() } }
    }

    private func onTick() {
        let which = tick % 3
        tick += 1
        let label = Self.labels[which]
        guard presence.isRunning(player) else { state.recordCall(label: label, ms: 0, outcome: "absent"); return }
        let st = state, p = player
        switch which {
        case 0:
            st.setLabel(label)
            let t0 = ContinuousClock.now
            let r = nsas.execute(source: PlayerScripts.positionOnly(p))
            let ms = milliseconds(ContinuousClock.now - t0)
            st.setLabel(nil)
            record(label, ms, r.map { _ in () })
        case 1:
            st.setLabel(label)
            let t0 = ContinuousClock.now
            let r = AppleEventClient(timeout: 1).read(player: p, path: ["pPos"])
            let ms = milliseconds(ContinuousClock.now - t0)
            st.setLabel(nil)
            record(label, ms, r.map { _ in () })
        default:
            st.setLabel(label)
            DispatchQueue.global().async { [weak self] in
                let t0 = ContinuousClock.now
                let r = AppleEventClient(timeout: 1).read(player: p, path: ["pPos"])
                let ms = milliseconds(ContinuousClock.now - t0)
                let outcome = r.map { _ in () }
                st.setLabel(nil)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.record(label, ms, outcome) } }
            }
        }
    }

    private func record(_ label: String, _ ms: Double, _ r: Result<Void, ScriptError>) {
        switch r {
        case .success: state.recordCall(label: label, ms: ms, outcome: "ok")
        case .failure(let e): state.recordCall(label: label, ms: ms, outcome: "err\(e.code)")
        }
        if ms > 100 || r.isFailure { log.write(String(format: "T %@ ms=%.1f result=%@ t=%.2f", label, ms, "\(r)", log.seconds(ContinuousClock.now))) }
    }

    private func finish() {
        timer?.cancel()
        state.stopped = true
        for l in Self.labels { log.write(state.summary(label: l)) }
        log.write(state.beatSummary())
        log.write("# done")
        NSApp.terminate(nil)
    }
}

extension Result { var isFailure: Bool { if case .failure = self { return true }; return false } }

/// État partagé du banc (protégé par un verrou : le battement tourne sur un autre fil).
final class BenchState: @unchecked Sendable {
    private let lock = NSLock()
    private var label: String?
    private var calls: [String: [(ms: Double, outcome: String)]] = [:]
    private var beats: [String: [Double]] = [:]
    private var _stopped = false
    var stopped: Bool { get { lock.lock(); defer { lock.unlock() }; return _stopped } set { lock.lock(); _stopped = newValue; lock.unlock() } }

    func setLabel(_ l: String?) { lock.lock(); label = l; lock.unlock() }
    func currentLabel() -> String { lock.lock(); defer { lock.unlock() }; return label ?? "idle" }
    func recordCall(label: String, ms: Double, outcome: String) { lock.lock(); calls[label, default: []].append((ms, outcome)); lock.unlock() }
    func recordBeat(label: String, delayMs: Double) { lock.lock(); beats[label, default: []].append(delayMs); lock.unlock() }

    func summary(label: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let c = calls[label] ?? []
        let oks = c.filter { $0.outcome == "ok" }.map(\.ms).sorted()
        var errs: [String: Int] = [:]
        for x in c where x.outcome != "ok" { errs[x.outcome, default: 0] += 1 }
        let errText = errs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return String(format: "S %@ n=%d ok=%d p50=%.2f p95=%.2f max=%.2f ms errors{%@}", label, c.count, oks.count,
                      percentile(oks, 0.5), percentile(oks, 0.95), oks.last ?? .nan, errText)
    }

    func beatSummary() -> String {
        lock.lock(); defer { lock.unlock() }
        var parts: [String] = []
        for (l, v) in beats.sorted(by: { $0.key < $1.key }) {
            let s = v.sorted()
            parts.append(String(format: "%@:n=%d max=%.1f p99=%.1f >50ms=%d >250ms=%d", l, v.count, s.last ?? .nan, percentile(s, 0.99),
                                v.filter { $0 > 50 }.count, v.filter { $0 > 250 }.count))
        }
        return "H heartbeat (retard de la file principale, ms, par transport en vol à l'envoi) " + parts.joined(separator: " | ")
    }
}
#endif
