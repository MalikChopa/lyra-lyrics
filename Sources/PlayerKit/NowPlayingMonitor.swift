import Foundation

/// Arbitrage des sources (§3.2, J4), logique PURE (instants injectés, testable sans lecteur ni minuteur).
/// - Quand les deux lecteurs jouent, celui qui a le plus récemment PASSÉ en lecture gagne ; les événements de l'autre sont ignorés.
/// - Si le lecteur actif se met en pause ou s'arrête et que l'autre joue, l'autre devient actif (son dernier relevé est rejoué).
/// - Anti-rebond de 600 ms sur les changements de titre (délégué) : le dernier `trackChanged` est émis après 600 ms de calme,
///   avec les relevés arrivés entre-temps (dans l'ordre) ; un `trackChanged` plus récent remplace les précédents.
/// - Statut (`permissionNeeded`, `error`) : transmis seulement si le lecteur concerné est actif ou si personne ne l'est
///   (« Autorisation nécessaire » côté Music ne doit pas masquer Spotify en cours, §3.6).
public struct MonitorCore: Sendable {
    public static let debounce: Duration = .milliseconds(600)

    public private(set) var active: PlayerID?
    private var playing: [PlayerID: Bool] = [:]
    private var latest: [PlayerID: PlayerReading] = [:]
    private var pending: [PlayerEvent] = []
    private var deadline: ContinuousClock.Instant?

    public init() {}

    public var nextDeadline: ContinuousClock.Instant? { deadline }
    public var hasPending: Bool { deadline != nil }

    /// Traite un événement de source ; renvoie les événements à transmettre tout de suite.
    public mutating func handle(_ event: PlayerEvent, at now: ContinuousClock.Instant) -> [PlayerEvent] {
        switch event {
        case .permissionNeeded(let p), .error(let p, _):
            return (active == nil || active == p) ? [event] : []

        case .stopped(let p):
            playing[p] = false
            latest[p] = nil
            if let switched = reselect(afterLosing: p, at: now) { return switched }
            guard active == p || active == nil else { return [] }
            return deliver(event)

        case .trackChanged(let r), .reading(let r):
            let p = r.player
            let isPlaying = r.state == .playing
            let wasPlaying = playing[p] ?? false
            playing[p] = isPlaying
            if r.track != nil { latest[p] = r }
            var becameActive = false
            if isPlaying, active != p {
                let activeStillPlaying = active.map { playing[$0] == true } ?? false
                if !wasPlaying || !activeStillPlaying { active = p; becameActive = true }
            } else if active == nil {
                active = p
                becameActive = true
            }
            if becameActive {
                // Nouveau lecteur actif : on repart d'un `trackChanged` (le titre de l'autre lecteur n'est pas le sien).
                pending = []
                return deliverTrackChange(.trackChanged(r), at: now)
            }
            if active != p {
                // Lecteur non actif : seulement l'effet d'une pause/arrêt du lecteur actif (rare) est traité plus haut.
                return []
            }
            if !isPlaying, let switched = reselect(afterLosing: p, at: now) { return switched }
            if case .trackChanged = event { return deliverTrackChange(event, at: now) }
            return deliver(event)
        }
    }

    /// Émet les événements en attente si l'anti-rebond est écoulé.
    public mutating func flushDue(at now: ContinuousClock.Instant) -> [PlayerEvent] {
        guard let d = deadline, now >= d else { return [] }
        let out = pending
        pending = []
        deadline = nil
        return out
    }

    // MARK: interne

    private mutating func deliverTrackChange(_ event: PlayerEvent, at now: ContinuousClock.Instant) -> [PlayerEvent] {
        pending = [event]
        deadline = now + Self.debounce
        return []
    }

    private mutating func deliver(_ event: PlayerEvent) -> [PlayerEvent] {
        if deadline != nil { pending.append(event); return [] }
        return [event]
    }

    /// Le lecteur actif `lost` ne joue plus : si l'autre joue, il devient actif (`trackChanged` de son dernier relevé, anti-rebond).
    private mutating func reselect(afterLosing lost: PlayerID, at now: ContinuousClock.Instant) -> [PlayerEvent]? {
        guard active == lost, playing[lost] != true else { return nil }
        for other in PlayerID.allCases where other != lost && playing[other] == true {
            guard let r = latest[other] else { continue }
            active = other
            pending = []
            return deliverTrackChange(.trackChanged(r), at: now)
        }
        return nil
    }
}

/// Fusion des sources en un seul flux d'événements, avec `MonitorCore` (règle « le plus récent gagne », anti-rebond 600 ms).
@MainActor
public final class NowPlayingMonitor {
    public let events: AsyncStream<PlayerEvent>
    /// Observateur des événements BRUTS des sources, avant arbitrage (mode mesure DEBUG : instant de l'événement de changement).
    public var tap: (@MainActor (PlayerEvent) -> Void)?
    /// Observateur des événements transmis (après arbitrage et anti-rebond).
    public var tapOutput: (@MainActor (PlayerEvent) -> Void)?
    public var activePlayer: PlayerID? { core.active }

    private let sources: [PlayerSource]
    private var tasks: [Task<Void, Never>] = []
    private var core = MonitorCore()
    private let continuation: AsyncStream<PlayerEvent>.Continuation
    private var flushTask: Task<Void, Never>?

    public init(sources: [PlayerSource]) {
        self.sources = sources
        (events, continuation) = AsyncStream.makeStream(of: PlayerEvent.self, bufferingPolicy: .unbounded)
        for source in sources {
            let upstream = source.events
            tasks.append(Task { [weak self] in
                for await event in upstream { self?.receive(event) }
            })
        }
    }

    private func receive(_ event: PlayerEvent) {
        tap?(event)
        emit(core.handle(event, at: .now))
        rearm()
    }

    private func emit(_ out: [PlayerEvent]) {
        for e in out { tapOutput?(e); continuation.yield(e) }
    }

    private func rearm() {
        flushTask?.cancel()
        guard let deadline = core.nextDeadline else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self else { return }
            self.emit(self.core.flushDue(at: .now))
            self.rearm()
        }
    }

    public func start() { sources.forEach { $0.start() } }
    public func stop() {
        sources.forEach { $0.stop() }
        tasks.forEach { $0.cancel() }
        flushTask?.cancel()
        continuation.finish()
    }
}
