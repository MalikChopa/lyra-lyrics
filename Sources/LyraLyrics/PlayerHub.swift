import AppKit
import PlayerKit

/// Branchement des VRAIS lecteurs (version publiée comprise) : `SpotifySource` (notification, sans permission) et `MusicSource`
/// (AppleScript, permission) → `NowPlayingMonitor` (le plus récent à passer en lecture gagne, anti-rebond 600 ms) → `AppModel`.
/// Un exécuteur par source (sinon l'un prend « le relevé en vol » de l'autre). Transport : Apple events à la main, hors du fil
/// principal (J1, mesure 5). Aucune invite spontanée : `requestPermission` n'est appelé que sur un clic de l'utilisateur.
@MainActor
final class PlayerHub {
    let spotify: SpotifySource
    let music: MusicSource
    let monitor: NowPlayingMonitor
    private weak var model: AppModel?
    private var consumer: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?
    /// Relevés forcés demandés (réveil de veille) : diagnostic et autotest.
    private(set) var forcedReads = 0

    private let executors: [ScriptExecutor]
    /// Apple events réellement envoyés aux lecteurs depuis le lancement (mesure J5 : 0 quand les lecteurs sont fermés).
    var appleEventsSent: Int { executors.reduce(0) { $0 + $1.sentCount } }

    init(model: AppModel, presence: PlayerPresence = WorkspacePresence()) {
        self.model = model
        let spotifyExecutor = ScriptExecutor(backend: AppleEventBackend())
        let musicExecutor = ScriptExecutor(backend: AppleEventBackend())
        executors = [spotifyExecutor, musicExecutor]
        spotify = SpotifySource(executor: spotifyExecutor, presence: presence)
        music = MusicSource(executor: musicExecutor, presence: presence)
        monitor = NowPlayingMonitor(sources: [spotify, music])
    }

    func start() {
        let events = monitor.events
        consumer = Task { @MainActor [weak self] in
            for await event in events { self?.model?.ingest(event) }
        }
        monitor.start()
        // Lecteur quitté en cours de lecture : on relit tout de suite la présence (sans attendre le minuteur de 2 à 5 s) ;
        // `pollNow` constate l'absence et émet `stopped` SANS envoyer d'Apple event.
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == PlayerID.spotify.bundleID || id == PlayerID.music.bundleID else { return }
            Task { @MainActor in await self?.forceRead() }
        }
        refreshSpotifyAccess()
    }

    func stop() {
        monitor.stop()
        consumer?.cancel()
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
    }

    /// Relevé immédiat des deux sources (réveil de veille : la position estimée a pu dériver ; lecteur quitté). Une source dont le
    /// lecteur n'est pas lancé n'envoie rien (voir `pollNow`).
    func forceRead() async {
        forcedReads += 1
        await spotify.pollNow()
        await music.pollNow()
    }

    // MARK: Permissions (§3.7)

    /// État de l'autorisation Spotify, lu hors du fil principal avec un délai (J1 : l'appel peut ne jamais rendre la main).
    /// 1.0.1 : une seule lecture à la fois (un appel bloqué laisse un thread en attente : on n'en empile pas) ; une lecture qui ne rend pas
    /// la main ne remplace pas un état déjà connu.
    func refreshSpotifyAccess() {
        guard !probing else { return }
        probing = true
        Task { @MainActor [weak self] in
            let status = await Self.probe(.spotify, timeout: 4)
            self?.probing = false
            guard let model = self?.model else { return }
            if status == .unknown(-1), model.spotifyAccess != nil { return }
            model.spotifyAccess = status
        }
    }
    private var probing = false

    /// Clic sur « Autoriser » (Music) : l'invite du système apparaît, la réponse arrive hors du fil principal.
    func requestMusicAccess() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await self.music.requestPermission()
            self.model?.musicPermissionAnswered(status)
            if status == .granted { await self.music.pollNow() }
        }
    }

    /// Clic sur « Améliorer la précision » (Spotify) : relevés AppleScript de position seulement après accord.
    func requestSpotifyAccess() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await self.spotify.requestPermission()
            self.model?.spotifyAccess = status
            if status == .granted { await self.spotify.pollNow() }
        }
    }

    /// `PermissionProbe.status` (sans demander) hors du fil principal ; `.unknown(-1)` si rien en `timeout` secondes (bloqué).
    nonisolated static func probe(_ player: PlayerID, timeout: Double) async -> AutomationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<AutomationStatus, Never>) in
            let once = OnceFlag()
            DispatchQueue.global(qos: .userInitiated).async {
                let s = PermissionProbe.status(for: player)
                if once.take() { cont.resume(returning: s) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.take() { cont.resume(returning: .unknown(-1)) }
            }
        }
    }

    /// URL du volet Automatisation (non vérifiée sur macOS 27, §3.7 point 4).
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

#if DEBUG
/// Aucun lecteur n'est « lancé » (mesure J5, `--players-closed`).
@MainActor
struct ClosedPresence: PlayerPresence {
    func isRunning(_ player: PlayerID) -> Bool { false }
}
#endif
