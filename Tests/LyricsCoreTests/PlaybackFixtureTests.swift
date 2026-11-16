import Testing
import Foundation
@testable import LyricsCore

/// W3 : scénarios de lecture PARTAGÉS avec le modèle pur C# (`PlaybackModelTests.SharedScenarios_PlaybackJson`).
/// `AppModel.swift` vit dans l'exécutable `LyraLyrics` (non atteignable depuis les tests) : ce pilote rejoue donc ses règles
/// (startTrack, applyReading, applyServiceEvent, setOnline, retryLookup, setManualOffset, handleStop, `allowBackwardOnce`) avec les
/// vraies briques de `LyricsCore` (`DisplayState.reduce`, `PositionEstimator`, `SyncEngine`). Il prouve que réducteur, estimateur et moteur
/// donnent les mêmes suites d'états que le C# ; il ne prouve PAS `AppModel.swift` lui-même (côté Mac non couvert, à dire dans le journal).
struct PlaybackDriver {
    var display = DisplayState.initial
    var estimator = PositionEstimator()
    var engine = SyncEngine()
    var track: String?
    var lyrics: LyricsKindBox?
    var currentIndex = -1
    var manualOffset = 0.0
    var allowBackwardOnce = false
    var now = 0.0
    var hintDueAt: Double?

    enum LyricsKindBox { case synced([LyricLine]), plain, instrumental }

    mutating func evaluateLine() {
        guard case .synced = display.screen, case .synced = lyrics else { return }
        let index = engine.index(at: estimator.estimate(at: now), previous: currentIndex, allowBackward: allowBackwardOnce)
        allowBackwardOnce = false
        currentIndex = index
    }
    mutating func startTrack(_ id: String) {
        track = id; lyrics = nil; currentIndex = -1; manualOffset = 0
        engine = SyncEngine(); estimator.reset()
        display = DisplayState.reduce(display, .trackChanged)
        hintDueAt = now + 1.5
    }
    mutating func applyReading(pos: Double, state: PlaybackReading.State) {
        let kind = estimator.apply(PlaybackReading(position: pos, at: now, state: state))
        if kind != .silent { allowBackwardOnce = true }
        let wasPaused = display.paused
        display = DisplayState.reduce(display, state == .paused ? .paused : .resumed)
        if wasPaused != display.paused { allowBackwardOnce = true }
        evaluateLine()
    }
    mutating func handleStop() {
        hintDueAt = nil
        track = nil; lyrics = nil; currentIndex = -1; manualOffset = 0
        engine = SyncEngine(); estimator.reset()
        display = DisplayState.reduce(display, .stopped)
    }
    mutating func show(_ l: LyricsKindBox) {
        switch l {
        case .synced: display = DisplayState.reduce(display, .lyricsSynced); allowBackwardOnce = true; evaluateLine()
        case .plain: display = DisplayState.reduce(display, .lyricsUnsynced)
        case .instrumental: display = DisplayState.reduce(display, .instrumental)
        }
    }
    mutating func service(kind: String, target: String, retryIn: Double, lines: [LyricLine]) {
        guard target == track else { return }
        switch kind {
        case "retrying": display = DisplayState.reduce(display, .waitEnded); hintDueAt = now + 1.5
        case "busy": display = DisplayState.reduce(display, .serviceBusy(retryIn: retryIn))
        case "offline": display = DisplayState.reduce(display, .wentOffline)
        case "found-synced":
            lyrics = .synced(lines); engine = SyncEngine(lines: lines, manualOffset: manualOffset); hintDueAt = nil; show(.synced(lines))
        case "found-plain": lyrics = .plain; hintDueAt = nil; show(.plain)
        case "found-instrumental": lyrics = .instrumental; hintDueAt = nil; show(.instrumental)
        case "notfound": display = DisplayState.reduce(display, .notFound)
        case "stalled": display = DisplayState.reduce(display, .serviceStalled)
        default: Issue.record("kind inconnu \(kind)")
        }
    }
    mutating func retry() {
        guard track != nil else { return }
        switch display.screen {
        case .unavailable, .busy: break
        default: return
        }
        display = DisplayState.reduce(display, .trackChanged); lyrics = nil; hintDueAt = now + 1.5
    }
    mutating func setOnline(_ online: Bool) {
        if online {
            if case .offline = display.screen, let l = lyrics { show(l) }
            else { display = DisplayState.reduce(display, .backOnline) }
        } else if lyrics == nil { display = DisplayState.reduce(display, .wentOffline) }
    }
    mutating func setOffset(_ v: Double) {
        manualOffset = SyncEngine.snappedOffset(v); engine.manualOffset = manualOffset; allowBackwardOnce = true; evaluateLine()
    }
    mutating func tick() {
        if let due = hintDueAt, now >= due {
            hintDueAt = nil
            if case .searching(false) = display.screen { display = DisplayState.reduce(display, .searchHintDue) }
        }
        if case .synced = display.screen, estimator.isPlaying { evaluateLine() }
    }

    func observe(_ key: String) -> Any? {
        switch key {
        case "screen": return display.screen.name
        case "hint": if case .searching(let h) = display.screen { return h } else { return nil }
        case "hasTrack": return display.hasTrack
        case "paused": return display.paused
        case "index": return Double(currentIndex)
        case "offset": return manualOffset
        case "retryIn": if case .busy(let s) = display.screen { return s } else { return nil }
        default: return nil
        }
    }
}

@Suite("Parité : scénarios de lecture (golden/playback.json)")
struct PlaybackFixtureTests {
    @Test("playback.json : mêmes états, mêmes lignes que le modèle C#")
    func scenarios() throws {
        let doc = try ParityJSON.load("golden/playback.json")
        let sets = (doc["lineSets"] as! [String: [[Any]]]).mapValues { $0.map { LyricLine(time: ($0[0] as! NSNumber).doubleValue, text: $0[1] as! String) } }
        var failures: [String] = []
        var steps = 0
        for sc in doc["scenarios"] as! [[String: Any]] {
            var d = PlaybackDriver()
            var current = "?"
            for st in sc["steps"] as! [[String: Any]] {
                steps += 1
                d.now = (st["t"] as! NSNumber).doubleValue
                let op = st["op"] as! String
                func state() -> PlaybackReading.State {
                    switch st["state"] as? String { case "paused": return .paused; case "stopped": return .stopped; default: return .playing }
                }
                let pos = ParityJSON.num(st["pos"]) ?? 0
                switch op {
                case "track":
                    current = st["id"] as! String
                    if d.track != current { d.startTrack(current) }
                    d.applyReading(pos: pos, state: state())
                case "reading": d.applyReading(pos: pos, state: state())
                case "stop": if d.track != nil { d.handleStop() }; current = "?"
                case "tick": d.tick()
                case "offset": d.setOffset(ParityJSON.num(st["value"])!)
                case "retry": d.retry()
                case "net-off": d.setOnline(false)
                case "net-on": d.setOnline(true)
                case "service":
                    d.service(kind: st["kind"] as! String, target: (st["for"] as? String) ?? current, retryIn: ParityJSON.num(st["retryIn"]) ?? 0,
                              lines: (st["lines"] as? String).flatMap { sets[$0] } ?? [])
                default: failures.append("op inconnue \(op)")
                }
                for (key, want) in st["expect"] as! [String: Any] {
                    let got = d.observe(key)
                    let ok: Bool
                    if let w = want as? String { ok = (got as? String) == w }
                    else if let w = want as? Bool, CFGetTypeID(want as CFTypeRef) == CFBooleanGetTypeID() { ok = (got as? Bool) == w }
                    else if let w = ParityJSON.num(want) { ok = (got as? Double).map { abs($0 - w) < 1e-9 } ?? false }
                    else { ok = false }
                    if !ok { failures.append("\(sc["name"] as! String) / t=\(d.now) \(op): \(key) = \(String(describing: got)), attendu \(want)") }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(15).joined(separator: "\n"))")
        #expect(steps >= 100)
    }
}
