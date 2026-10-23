import Foundation

/// Music : `com.apple.Music.playerInfo` sert de déclencheur (clés mesurées en J1 : pas de position) ;
/// AppleScript toutes les 2 s en lecture (5 s sinon). Rien ne part sans autorisation accordée : état « Autorisation nécessaire ».
@MainActor
public final class MusicSource: PlayerSource {
    public static let playingInterval = 2
    public static let idleInterval = 5

    private let executor: ScriptExecutor
    private let presence: PlayerPresence
    private let permission: @Sendable (PlayerID) -> AutomationStatus
    private var polling = false
    private let emitter = EventEmitter(player: .music)
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var tick = 0
    private var wasRunning = false
    private var lastPermission: AutomationStatus?

    public var events: AsyncStream<PlayerEvent> { emitter.stream }

    public init(executor: ScriptExecutor, presence: PlayerPresence,
                permission: @escaping @Sendable (PlayerID) -> AutomationStatus = { PermissionProbe.status(for: $0) }) {
        self.executor = executor
        self.presence = presence
        self.permission = permission
    }

    public func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notificationArrived() }
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick += 1
                let playing = self.emitter.lastReading?.state == .playing
                if self.tick % (playing ? Self.playingInterval : Self.idleInterval) == 0 { Task { @MainActor in await self.pollNow() } }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        wasRunning = presence.isRunning(.music)
    }

    public func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        timer?.invalidate(); timer = nil
        pendingNotificationPoll?.cancel()
        emitter.finish()
    }

    /// Une pause/lecture/seek publie plusieurs notifications d'affilée (mesuré : 3 en <100 ms) : un seul relevé, 0,3 s après la dernière.
    private var pendingNotificationPoll: DispatchWorkItem?
    func notificationArrived() {
        pendingNotificationPoll?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in await self?.pollNow() } }
        pendingNotificationPoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    public func pollNow() async {
        if polling { return }
        polling = true
        defer { polling = false }
        guard presence.isRunning(.music) else {
            if wasRunning { wasRunning = false; emitter.playerQuit() }
            return
        }
        wasRunning = true
        let status = await checkPermission(.music)
        if status != lastPermission {
            lastPermission = status
            if status == .denied || status == .notDetermined { emitter.emit(.permissionNeeded(.music)) }
        }
        guard status == .granted else { return }
        let t0 = ContinuousClock.now
        let outcome = await executor.run(.full(.music))
        let t1 = ContinuousClock.now
        switch outcome.flatMap({ PlayerScripts.parseReading(player: .music, values: $0) }) {
        case .success(var reading):
            reading.at = t0 + (t1 - t0) / 2
            emitter.ingest(reading)
        case .failure(.denied), .failure(.consentRequired): emitter.emit(.permissionNeeded(.music))
        case .failure(.busy): break
        case .failure(let error): emitter.emit(.error(.music, error))
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` peut BLOQUER (mesuré en J1 : plus de 3 min après un rebuild) : jamais sur le fil principal.
    private func checkPermission(_ p: PlayerID) async -> AutomationStatus {
        let check = permission
        return await Task.detached { check(p) }.value
    }

    /// Demande explicite (clic de l'utilisateur), hors du fil principal.
    public nonisolated func requestPermission() async -> AutomationStatus {
        await Task.detached { PermissionProbe.status(for: .music, ask: true) }.value
    }
}
