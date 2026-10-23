#if DEBUG
import Foundation
import PlayerKit

/// Faux lecteur en processus (`--fake-player <scénario>`, DEBUG uniquement) : remplace TOUTES les sources, n'émet aucune
/// notification système, ne parle à aucun lecteur. Titres du scénario : inventés (Fixtures/scenarios/) ; les paroles viennent
/// du faux LRCLIB (catalogue en processus ou `--lyrics-endpoint`), plus du scénario (J3).
struct FakeScenario: Decodable {
    struct Track: Decodable {
        var id: String
        var title: String
        var artist: String
        var album: String?
        var duration: Double?
        /// Pochette INVENTÉE (Fixtures/artwork/<nom>.png) et son chemin : « music » = octets par Apple event simulé, « spotify » = URL
        /// puis GET HTTP vers le faux serveur (`--lyrics-endpoint`, `/art/<nom>.png`).
        var artwork: String?
        var artworkMode: String?
    }
    struct Step: Decodable {
        var at: Double
        var `do`: String        // play | pause | resume | stop
        var track: String?
    }
    var name: String
    var tracks: [Track]
    var timeline: [Step]?

    /// `nom` → Fixtures/scenarios/<nom>.json (cherché depuis le dossier courant puis depuis l'exécutable), ou chemin explicite.
    static func load(_ nameOrPath: String) -> FakeScenario? {
        var candidates = [nameOrPath, "Fixtures/scenarios/\(nameOrPath).json"]
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 { candidates.append(dir.appendingPathComponent("Fixtures/scenarios/\(nameOrPath).json").path); dir.deleteLastPathComponent() }
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            if let data = FileManager.default.contents(atPath: c), let s = try? JSONDecoder().decode(FakeScenario.self, from: data) { return s }
        }
        return nil
    }
}

@MainActor
final class FakePlayerSource: PlayerSource {
    let scenario: FakeScenario
    let events: AsyncStream<PlayerEvent>
    private let continuation: AsyncStream<PlayerEvent>.Continuation
    private var current: FakeScenario.Track?
    private var state: PlaybackState = .stopped
    private var startedAt: ContinuousClock.Instant = .now
    private var basePosition: Double = 0
    private var readingTimer: Timer?
    private var timelineTasks: [Task<Void, Never>] = []

    init(scenario: FakeScenario) {
        self.scenario = scenario
        (events, continuation) = AsyncStream.makeStream(of: PlayerEvent.self, bufferingPolicy: .unbounded)
    }

    func start() {
        for step in scenario.timeline ?? [] {
            timelineTasks.append(Task { [weak self] in
                try? await Task.sleep(for: .seconds(step.at))
                guard !Task.isCancelled else { return }
                self?.perform(step.do, track: step.track)
            })
        }
        readingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.emitReading() }
        }
    }

    func stop() {
        timelineTasks.forEach { $0.cancel() }; timelineTasks = []
        readingTimer?.invalidate(); readingTimer = nil
        continuation.finish()
    }

    func perform(_ action: String, track: String? = nil) {
        switch action {
        case "play":
            guard let id = track, let t = scenario.tracks.first(where: { $0.id == id }) else { return }
            current = t; state = .playing; basePosition = 0; startedAt = .now
            continuation.yield(.trackChanged(reading()))
        case "pause":
            guard state == .playing else { return }
            basePosition = position(); state = .paused
            continuation.yield(.reading(reading()))
        case "resume":
            guard state == .paused else { return }
            startedAt = .now; state = .playing
            continuation.yield(.reading(reading()))
        case "seek":
            guard current != nil, let t = track, let secs = Double(t) else { return }
            basePosition = secs; startedAt = .now
            continuation.yield(.reading(reading()))
        case "stop":
            state = .stopped; current = nil
            continuation.yield(.stopped(.spotify))
        case "previous", "next":
            // Boutons ⏮ ⏭ : titre précédent / suivant du scénario (en boucle), lu depuis le début.
            guard !scenario.tracks.isEmpty else { return }
            let i = scenario.tracks.firstIndex { $0.id == current?.id } ?? 0
            let j = (i + (action == "next" ? 1 : scenario.tracks.count - 1)) % scenario.tracks.count
            perform("play", track: scenario.tracks[j].id)
        case "playpause":
            perform(state == .playing ? "pause" : "resume")
        case "perm-needed":
            // Music sans autorisation (-1743/-1744) : le moniteur transmet « permissionNeeded » (§3.6, §3.7).
            continuation.yield(.permissionNeeded(.music))
        case "unreadable":
            // Titre en streaming illisible (-1728) : 3 erreurs de suite → « Titre non lisible » (§3.6).
            for _ in 0..<3 { continuation.yield(.error(.music, .objectNotFound)) }
        default: break
        }
    }

    /// Pochette du titre en cours (autotest des couleurs) : nom du fichier et mode.
    var currentArtwork: (name: String, mode: String)? {
        guard let t = current, let name = t.artwork else { return nil }
        return (name, t.artworkMode ?? "music")
    }

    /// Octets de la pochette inventée (fichier du dépôt de fixtures).
    static func artworkData(named name: String) -> Data? {
        var candidates = ["Fixtures/artwork/\(name).png"]
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 { candidates.append(dir.appendingPathComponent("Fixtures/artwork/\(name).png").path); dir.deleteLastPathComponent() }
        for c in candidates where FileManager.default.fileExists(atPath: c) { return FileManager.default.contents(atPath: c) }
        return nil
    }

    private func position() -> Double {
        guard state == .playing else { return basePosition }
        let d = ContinuousClock.now - startedAt
        return basePosition + Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private func reading() -> PlayerReading {
        let t = current
        let track = t.map { PlayerTrack(name: $0.title, artist: $0.artist, album: $0.album, durationSeconds: $0.duration, trackID: $0.id) }
        return PlayerReading(player: .spotify, state: state, positionSeconds: position(), track: track, at: .now)
    }

    /// Relevé immédiat (réveil de veille).
    private(set) var forcedReadings = 0
    func forceReading() { forcedReadings += 1; emitReading() }

    private func emitReading() {
        guard current != nil else { return }
        continuation.yield(.reading(reading()))
    }
}
#endif
