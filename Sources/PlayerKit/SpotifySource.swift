import Foundation

/// Spotify : notification distribuée = source principale (sans permission) ;
/// position AppleScript toutes les 5 s en lecture, SEULEMENT si l'autorisation est déjà accordée (jamais d'invite spontanée, §3.7).
@MainActor
public final class SpotifySource: PlayerSource {
    public static let pollInterval: TimeInterval = 5

    private let executor: ScriptExecutor
    private let presence: PlayerPresence
    private let permission: @Sendable (PlayerID) -> AutomationStatus
    private var polling = false
    private let emitter = EventEmitter(player: .spotify)
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var wasRunning = false

    public var events: AsyncStream<PlayerEvent> { emitter.stream }

    public init(executor: ScriptExecutor, presence: PlayerPresence,
                permission: @escaping @Sendable (PlayerID) -> AutomationStatus = { PermissionProbe.status(for: $0) }) {
        self.executor = executor
        self.presence = presence
        self.permission = permission
    }

    public func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(SpotifyNotificationParser.notificationName), object: nil, queue: .main
        ) { [weak self] note in
            let reading = SpotifyNotificationParser.parse(userInfo: note.userInfo ?? [:])
            MainActor.assumeIsolated { if let reading { self?.handleNotification(reading) } }
        }
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        wasRunning = presence.isRunning(.spotify)
    }

    public func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        timer?.invalidate(); timer = nil
        emitter.finish()
    }

    func handleNotification(_ reading: PlayerReading) {
        wasRunning = true
        var stamped = reading
        stamped.at = ContinuousClock.now
        emitter.ingest(stamped)
    }

    /// Relevé AppleScript périodique. Aucun Apple event si le lecteur n'est pas lancé, pas en lecture, ou sans autorisation.
    public func pollNow() async {
        if polling { return }
        polling = true
        defer { polling = false }
        guard presence.isRunning(.spotify) else {
            if wasRunning { wasRunning = false; emitter.playerQuit() }
            return
        }
        wasRunning = true
        guard emitter.lastReading == nil || emitter.lastReading?.state == .playing else { return }
        guard await checkPermission(.spotify) == .granted else { return }
        let t0 = ContinuousClock.now
        let outcome = await executor.run(.full(.spotify))
        let t1 = ContinuousClock.now
        switch outcome.flatMap({ PlayerScripts.parseReading(player: .spotify, values: $0) }) {
        case .success(var reading):
            reading.at = t0 + (t1 - t0) / 2
            emitter.ingest(reading)
        case .failure(.busy): break
        case .failure(let error): emitter.emit(.error(.spotify, error))
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` peut BLOQUER (mesuré en J1 : plus de 3 min après un rebuild) : jamais sur le fil principal.
    private func checkPermission(_ p: PlayerID) async -> AutomationStatus {
        let check = permission
        return await Task.detached { check(p) }.value
    }

    /// Demande explicite (clic de l'utilisateur) : bloque jusqu'à la réponse à l'invite, donc hors du fil principal.
    public nonisolated func requestPermission() async -> AutomationStatus {
        await Task.detached { PermissionProbe.status(for: .spotify, ask: true) }.value
    }
}
