import AppKit
import SwiftUI
import Observation
import PlayerKit
import AppSupport
import LyricsCore

/// Écran affiché (nom de `DisplayState.Screen`), lisible par l'autotest (`mode=`).
enum DisplayMode: String {
    case nothing, searching, synced, unsynced, instrumental, unavailable, busy, offline, permission, unreadable
}

/// Modèle de l'app (§3.3) : reçoit les `PlayerEvent` (vrais lecteurs à J4, faux lecteur en DEBUG), confie chaque titre à
/// `LyricsService`, tient `DisplayState` (réducteur pur), `PositionEstimator` + `SyncEngine` (minuteur 10 Hz) et publie
/// seulement quand la ligne change. Aucun texte de paroles ne sort d'ici autrement que vers les vues.
@MainActor
@Observable
final class AppModel {
    // MARK: Paroles et lecture
    private(set) var display = DisplayState.initial
    private(set) var track: TrackInfo?
    private(set) var lyrics: Lyrics?
    private(set) var currentIndex: Int = -1
    /// Secondes avant le nouvel essai (« Service occupé »).
    private(set) var busyRetryIn: Double = 0
    /// Dernier résultat de recherche, en clair mais SANS texte (provenance, raison) : diagnostic et autotest.
    private(set) var lastLookup = ""
    /// Décalage manuel du titre courant (± 5 s, pas 0,1 s), remis à zéro au changement de titre (mémoire seulement).
    private(set) var manualOffset: Double = 0
    /// Avancement 0…1 du bloc « non synchronisées » (position / durée ; sans durée : 4 min).
    private(set) var unsyncedProgress: Double = 0
    /// Message du volet après « Vider le cache ».
    var cacheMessage: String?
    private(set) var lastIndexCount = -1
    /// Nombre de fois où « Paroles indisponibles » a été atteint depuis le lancement (autotest : une erreur passagère ne doit jamais l'y mener).
    @ObservationIgnored private(set) var unavailableEntries = 0

    var mode: DisplayMode { DisplayMode(rawValue: display.screen.name) ?? .nothing }
    var title: String? { track?.title }
    var artist: String? { track?.artist }
    var isPaused: Bool { display.paused }
    var searchHint: Bool { if case .searching(true) = display.screen { return true } else { return false } }
    var plainText: String { lyrics?.plainText ?? "" }

    // MARK: État d'interface (J2)
    var hovering = false
    var hoveredButton: String?
    /// Fenêtre de paroles affichée à l'écran (§3.4 : le minuteur et toute publication vers SwiftUI s'arrêtent sinon).
    @ObservationIgnored private(set) var windowVisible = true
    /// Publications de ligne ou de progression vers SwiftUI (diagnostic de la mesure du CPU).
    @ObservationIgnored private(set) var publishCount = 0
    var settingsOpen = false
    /// Mesure de mise en page (renseignée par `PanelController`).
    /// Largeur actuelle de la fenêtre de paroles (460 pt par défaut, ou imposée par le redimensionnement à la souris).
    var windowWidth = LyricsMetrics.windowWidth
    var textWidth: Double { LyricsMetrics.textWidth(forWindowWidth: windowWidth) }
    var fit = LineFit(currentSize: 26, neighbourSize: 17.16, contentHeight: 0, windowHeight: LyricsMetrics.minHeight, shrunk: false, exceedsMaxHeight: false)
    /// Hauteur réellement rendue par SwiftUI pour le bloc des trois lignes (diagnostic).
    var renderedLinesHeight: Double = 0
    /// Hauteur du texte du bloc « non synchronisées » (pour le défilement).
    var unsyncedContentHeight: Double = 0
    var systemReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    var reduceTransparencyOverride: Bool?
    var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Forcé par l'autotest (le réglage du système n'est jamais modifié).
    var reduceMotionOverride: Bool?
    /// « Réduire les animations » : toute transition est coupée (§4).
    var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    /// Animation à appliquer, ou `nil` si les animations sont réduites : l'UNIQUE point d'entrée des animations de l'app.
    func animation(_ a: Animation) -> Animation? { reduceMotion ? nil : a }
    /// Réveils de veille traités (diagnostic et autotest).
    var wakeCount = 0
    /// Hauteur max du volet de réglages (zone visible − marges), posée par `SettingsPanelController` ; au-delà, le contenu défile.
    var settingsMaxHeight: Double = 10_000
    /// Hauteur naturelle (sans défilement) du contenu du volet, mesurée par SwiftUI.
    var settingsContentHeight: Double = 0
    @ObservationIgnored var onSettingsContentHeight: (() -> Void)?
    /// Ouverture du volet : relit l'état de l'autorisation Spotify (posé par `AppController`).
    @ObservationIgnored var onSettingsOpened: (() -> Void)?
    var hotKeyAvailable = true
    var hotKeyMessage: String?
    var onDisplayedLinesChanged: (() -> Void)?
    /// Pile de lignes en cours (autotest et mesures) ; faible : appartient à la vue.
    @ObservationIgnored weak var lineStack: LineStackView?

    // MARK: Avis passager (1.0.1)
    /// Courte phrase affichée en haut de la fenêtre de paroles (≈ 3 s) : « Clic-à-travers activé · ⌃⌥⌘L pour revenir », ou l'explication
    /// de l'autorisation Spotify pour les boutons de lecture.
    private(set) var notice: String?
    /// Bouton éventuel de l'avis (ex. « Ouvrir les Réglages »).
    struct NoticeAction { var label: String; var perform: @MainActor () -> Void }
    private(set) var noticeAction: NoticeAction?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// Avis posés (diagnostic et autotest).
    @ObservationIgnored private(set) var noticesShown: [String] = []

    func showNotice(_ text: String, seconds: Double = 3, action: NoticeAction? = nil) {
        notice = text
        noticeAction = action
        noticesShown.append(text)
        diag?(["event": "notice", "text": text])
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.notice = nil; self.noticeAction = nil
            self.onDisplayedLinesChanged?()
        }
        onDisplayedLinesChanged?()
    }

    func clearNotice() {
        noticeTask?.cancel(); noticeTask = nil
        if notice != nil { notice = nil; noticeAction = nil; onDisplayedLinesChanged?() }
    }

    // MARK: Pochette et boutons de lecture
    /// Couleurs tirées de la pochette du titre en cours (nil : styles unis, réglage désactivé ou pochette indisponible).
    private(set) var palette: ArtworkPalette?
    /// Identité du titre dont la palette est affichée (diagnostic).
    private(set) var paletteIdentity: String?
    @ObservationIgnored var onTrackStarted: ((TrackInfo) -> Void)?
    @ObservationIgnored var onTrackStopped: (() -> Void)?
    /// Exécute une commande de lecture auprès du lecteur actif (posé par `AppController`).
    @ObservationIgnored var onPlayback: ((PlaybackCommand) -> Void)?
    /// Clic sur un bouton quand l'autorisation est refusée : propose « Ouvrir les Réglages » (posé par `AppController`).
    @ObservationIgnored var onPlaybackRefused: (() -> Void)?
    /// Commandes de lecture envoyées (diagnostic et autotest).
    @ObservationIgnored private(set) var playbackSent: [PlaybackCommand] = []

    func applyPalette(identity: String, _ p: ArtworkPalette?) {
        guard identity == track?.identity else { return }
        palette = p; paletteIdentity = p == nil ? nil : identity
        diag?(["event": "palette", "present": p != nil, "accent": p?.accent.hex ?? "", "tint": p?.tint.hex ?? "", "contrast": p.map { ($0.accentContrast * 100).rounded() / 100 } ?? 0])
        onDisplayedLinesChanged?()
    }
    func clearPalette() { if palette != nil { palette = nil; paletteIdentity = nil } }

    /// État des boutons précédent / lecture-pause / suivant (1.0.1).
    /// - Autorisation Automatisation accordée, NON DÉTERMINÉE, inconnue ou pas encore lue : boutons actifs ; si elle n'est pas accordée, le
    ///   premier clic la demande (`hint` l'annonce dans l'infobulle) ;
    /// - REFUSÉE : boutons grisés (`enabled` faux), mais un clic propose « Ouvrir les Réglages » (`refused`) ;
    /// - aucun titre, ou Music en attente d'autorisation : grisés sans proposition.
    struct PlaybackAvailability: Equatable {
        var enabled: Bool
        var reason: String?
        var refused = false
        var hint: String?
    }

    var playbackAvailability: PlaybackAvailability {
        guard let track else { return PlaybackAvailability(enabled: false, reason: "Aucune lecture en cours") }
        switch track.player {
        case "spotify":
            if spotifyAccess == .denied {
                return PlaybackAvailability(enabled: false, reason: "Autorisation refusée : clique pour ouvrir les Réglages Système (Automatisation).", refused: true)
            }
            if spotifyAccess == .granted { return PlaybackAvailability(enabled: true, reason: nil) }
            return PlaybackAvailability(enabled: true, reason: nil, hint: "Le premier clic demande l'autorisation de piloter Spotify.")
        case "music":
            if case .permissionNeeded = display.screen { return PlaybackAvailability(enabled: false, reason: "Autorisation nécessaire : autorise \(AppIdentity.displayName) à contrôler Apple Music.") }
            return PlaybackAvailability(enabled: true, reason: nil)
        default:
            return PlaybackAvailability(enabled: true, reason: nil)
        }
    }
    #if DEBUG
    @ObservationIgnored var usesFakePlayer = false
    #endif

    /// Clic sur un bouton de lecture. Refusée : « Ouvrir les Réglages » ; sinon `onPlayback` (AppController) vérifie l'autorisation,
    /// la demande au premier clic si besoin, puis envoie la commande.
    func sendPlayback(_ command: PlaybackCommand) {
        let availability = playbackAvailability
        if availability.refused {
            diag?(["event": "playback-refused", "command": command.rawValue])
            onPlaybackRefused?()
            return
        }
        guard availability.enabled else { return }
        playbackSent.append(command)
        diag?(["event": "playback", "command": command.rawValue])
        onPlayback?(command)
    }

    /// Couleur de la ligne courante : accent de la pochette si le réglage est actif et qu'une palette existe, sinon la pastille choisie.
    func lineColor(_ s: Settings) -> RGB {
        if s.artworkColors, let palette { return palette.accent }
        let v = UInt32(s.colorHex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return RGB(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    /// Autorisation Automatisation de Spotify (nil = pas encore lue ; `.unknown(-1)` = l'appel ne rend pas la main, voir J1).
    var spotifyAccess: AutomationStatus?
    /// Boutons du §3.7 : « Autoriser » (Music), « Ouvrir les Réglages » (refus), « Améliorer la précision » (Spotify).
    @ObservationIgnored var onRequestMusicAccess: (() -> Void)?
    @ObservationIgnored var onRequestSpotifyAccess: (() -> Void)?
    var permissionRefused: Bool { if case .permissionNeeded(true) = display.screen { return true } else { return false } }

    // MARK: Collaborateurs (non observés)
    @ObservationIgnored var service: LyricsService?
    /// Journal de diagnostic (DEBUG) : états, indices, positions, horodatages ; jamais de paroles.
    @ObservationIgnored var diag: (([String: Any]) -> Void)?
    /// Titres dans le diagnostic : seulement en faux lecteur (§3.2).
    @ObservationIgnored var diagMayLogTitles = false
    @ObservationIgnored private var estimator = PositionEstimator()
    @ObservationIgnored private var engine = SyncEngine()
    @ObservationIgnored private var allowBackwardOnce = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var timerEnabled = false
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var unreadableCount = 0
    /// Mesure 3 du §5 : instant (ProcessClock), indice et position estimée à chaque changement de ligne affichée.
    @ObservationIgnored private(set) var lineChanges: [(t: Double, index: Int, position: Double)] = []
    @ObservationIgnored private(set) var lyricsArrivedAt: Double?

    func effectiveStyle(_ style: BackgroundStyle) -> BackgroundStyle {
        reduceTransparency && style != .solid ? .solid : style
    }

    /// Nombre de lignes visibles (réglage 1, 3 ou 5), posé par `AppController` depuis les réglages.
    var lineCount = LineCount.default
    /// Incrémenté à chaque changement de titre ou arrêt : la pile de lignes est alors remplacée par un fondu (pas de défilement).
    private(set) var trackEpoch = 0

    /// Lignes affichées, `lineCount` entrées, la courante au milieu (`count / 2`) ; entrées vides sinon.
    /// « Recherche des paroles… » au centre après 1,5 s.
    var visibleLines: [String] { lineItems(count: lineCount).map(\.text) }

    /// Les mêmes lignes avec leur identité (clé stable d'une ligne de paroles d'un état à l'autre, voir `LineItem`).
    func lineItems(count: Int) -> [LineItem] {
        let r = count / 2
        switch display.screen {
        case .synced:
            let lines = engine.lines
            if currentIndex < 0 {
                // Avant la première ligne : « ♪ » courante, les premières lignes en dessous.
                return (-r...r).map { o in
                    if o == 0 { return LineItem(key: "ph", order: -1, offset: 0, text: SyncEngine.placeholder) }
                    let i = o - 1
                    if o > 0, i < lines.count { return LineItem(key: "L\(i)", order: i, offset: o, text: lines[i].text) }
                    return LineItem(key: "b\(o < 0 ? o - 1 : i)", order: o < 0 ? o - 1 : i, offset: o, text: "")
                }
            }
            let index = min(currentIndex, max(lines.count - 1, 0))
            return (-r...r).map { o in
                let i = index + o
                if i >= 0, i < lines.count { return LineItem(key: "L\(i)", order: i, offset: o, text: lines[i].text) }
                return LineItem(key: "b\(i)", order: i, offset: o, text: "")
            }
        case .searching(let hint):
            return (-r...r).map { o in
                if o == 0 { return LineItem(key: "s0", order: 0, offset: 0, text: hint ? "Recherche des paroles…" : "", dim: true) }
                return LineItem(key: "s\(o)", order: o, offset: o, text: "")
            }
        default:
            return (-r...r).map { o in LineItem(key: "e\(o)", order: o, offset: o, text: "") }
        }
    }

    var barText: (title: String, artist: String?) {
        guard let track else { return (display.barTitleWhenIdle ?? "Aucune lecture", nil) }
        return (track.title, isPaused ? "\(track.artist) · En pause" : track.artist)
    }

    var positionEstimate: Double { estimator.estimate(at: ProcessClock.seconds()) }
    /// Position estimée à un instant donné (mesures 1 et 2 du §5 en mode mesure).
    func positionEstimate(at instant: ContinuousClock.Instant) -> Double { estimator.estimate(at: ProcessClock.seconds(instant)) }

    // MARK: Événements des lecteurs

    func ingest(_ event: PlayerEvent) {
        // Un titre ou un relevé qui arrive prouve que la lecture est de nouveau possible (ou qu'un autre lecteur prend la main).
        switch event {
        case .trackChanged, .reading:
            if case .permissionNeeded = display.screen { display = DisplayState.reduce(display, .permissionGranted) }
        default: break
        }
        switch event {
        case .trackChanged(let r):
            guard let pt = r.track else { handleStop(); break }
            let info = TrackInfo(title: pt.name, artist: pt.artist, album: pt.album, duration: pt.durationSeconds, sourceID: pt.trackID, player: r.player.rawValue)
            if info.identity != track?.identity { startTrack(info) }
            applyReading(r)
        case .reading(let r):
            if let pt = r.track {
                let info = TrackInfo(title: pt.name, artist: pt.artist, album: pt.album, duration: pt.durationSeconds, sourceID: pt.trackID, player: r.player.rawValue)
                if info.identity != track?.identity { startTrack(info) }
            }
            applyReading(r)
        case .stopped:
            handleStop()
        case .permissionNeeded:
            display = DisplayState.reduce(display, .permissionNeeded)
            logDisplay()
        case .error(_, let error):
            if error == .objectNotFound {
                unreadableCount += 1
                if unreadableCount >= 3 { display = DisplayState.reduce(display, .trackUnreadable); logDisplay() }
            }
        }
        updateTimer()
        onDisplayedLinesChanged?()
    }

    /// Réponse à l'invite « Autoriser » de Music (clic de l'utilisateur).
    func musicPermissionAnswered(_ status: AutomationStatus) {
        switch status {
        case .granted: display = DisplayState.reduce(display, .permissionGranted)
        case .denied: display = DisplayState.reduce(display, .permissionRefused)
        default: break
        }
        diag?(["event": "permission", "player": "music", "status": "\(status)"])
        logDisplay()
        updateTimer()
        onDisplayedLinesChanged?()
    }

    private func startTrack(_ info: TrackInfo) {
        track = info
        trackEpoch += 1
        lyrics = nil; currentIndex = -1; manualOffset = 0; unsyncedProgress = 0; unreadableCount = 0
        engine = SyncEngine(); estimator.reset(); lyricsArrivedAt = nil; lastLookup = ""
        display = DisplayState.reduce(display, .trackChanged)
        var record: [String: Any] = ["event": "track", "display": mode.rawValue, "duration": info.duration ?? 0, "player": info.player]
        if diagMayLogTitles { record["title"] = info.title; record["artist"] = info.artist }
        diag?(record)
        guard let service else { return }
        let identity = info.identity
        onTrackStarted?(info)
        let report: @Sendable (LyricsServiceEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.applyServiceEvent(event, identity: identity) }
        }
        Task { await service.lookup(info, report: report) }
        scheduleHint()
    }

    private func applyReading(_ r: PlayerReading) {
        let at = r.at.map { ProcessClock.seconds($0) } ?? ProcessClock.seconds()
        let state: PlaybackReading.State = r.state == .playing ? .playing : (r.state == .paused ? .paused : .stopped)
        if let p = r.positionSeconds {
            let kind = estimator.apply(PlaybackReading(position: p, at: at, state: state))
            if kind != .silent { allowBackwardOnce = true }
            diag?(["event": "reading", "position": (p * 1000).rounded() / 1000, "state": state.rawValue, "recal": kind.rawValue])
        }
        let wasPaused = display.paused
        display = DisplayState.reduce(display, state == .paused ? .paused : .resumed)
        if wasPaused != display.paused {
            allowBackwardOnce = true
            diag?(["event": "pause", "paused": display.paused])
        }
        evaluateLine(now: ProcessClock.seconds())
    }

    private func handleStop() {
        if let service { Task { await service.cancel() } }
        hintTask?.cancel()
        track = nil; lyrics = nil; currentIndex = -1; manualOffset = 0; unsyncedProgress = 0; trackEpoch += 1
        engine = SyncEngine(); estimator.reset(); lastLookup = ""
        palette = nil
        onTrackStopped?()
        display = DisplayState.reduce(display, .stopped)
        logDisplay()
    }

    // MARK: Service des paroles

    private func applyServiceEvent(_ event: LyricsServiceEvent, identity: String) {
        guard identity == track?.identity else { return }
        switch event {
        case .searching:
            break
        case .retrying:
            display = DisplayState.reduce(display, .waitEnded)
            scheduleHint()
        case .busy(let seconds, let reason):
            busyRetryIn = seconds
            display = DisplayState.reduce(display, .serviceBusy(retryIn: seconds))
            lastLookup = "occupé (\(reason))"
        case .offline:
            display = DisplayState.reduce(display, .wentOffline)
        case .found(let found, let cached):
            lyrics = found
            lyricsArrivedAt = ProcessClock.seconds()
            lastLookup = cached ? "cache" : found.provenance
            switch found.kind {
            case .synced(let lines):
                engine = SyncEngine(lines: lines, manualOffset: manualOffset)
                display = DisplayState.reduce(display, .lyricsSynced)
                allowBackwardOnce = true
                evaluateLine(now: ProcessClock.seconds())
            case .plain:
                display = DisplayState.reduce(display, .lyricsUnsynced)
            case .instrumental:
                display = DisplayState.reduce(display, .instrumental)
            }
        case .notFound(let reason):
            lastLookup = reason
            unavailableEntries += 1
            display = DisplayState.reduce(display, .notFound)
        case .stalled(let reason):
            busyRetryIn = 0
            lastLookup = "service occupé (\(reason))"
            display = DisplayState.reduce(display, .serviceStalled)
        }
        logDisplay()
        updateTimer()
        onDisplayedLinesChanged?()
    }

    /// Libellé du bouton de l'état affiché (nil : pas de bouton) : « Autoriser » / « Ouvrir les Réglages » (Music), « Réessayer ».
    var stateActionLabel: String? {
        switch mode {
        case .permission: return permissionRefused ? "Ouvrir les Réglages" : "Autoriser"
        case .unavailable, .busy: return "Réessayer"
        default: return nil
        }
    }
    var stateActionAccessibilityLabel: String? {
        switch mode {
        case .permission: return permissionRefused ? "Ouvrir les Réglages Système" : AppIdentity.allowAccessibilityLabel
        case .unavailable, .busy: return "Réessayer la recherche des paroles"
        default: return nil
        }
    }

    /// Bouton « Réessayer » (états « Paroles indisponibles » et « Service occupé ») : recherche relancée de zéro pour le titre courant.
    func retryLookup() {
        guard let service, let info = track, mode == .unavailable || mode == .busy else { return }
        display = DisplayState.reduce(display, .trackChanged)
        lyrics = nil; lastLookup = "nouvel essai demandé"
        diag?(["event": "retry", "mode": mode.rawValue])
        let identity = info.identity
        let report: @Sendable (LyricsServiceEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.applyServiceEvent(event, identity: identity) }
        }
        Task { await service.retry(info, report: report) }
        scheduleHint()
        logDisplay()
        updateTimer()
        onDisplayedLinesChanged?()
    }

    /// « Recherche des paroles… » après 1,5 s de recherche (délégué).
    private func scheduleHint() {
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            if case .searching(false) = self.display.screen {
                self.display = DisplayState.reduce(self.display, .searchHintDue)
                self.logDisplay()
                self.onDisplayedLinesChanged?()
            }
        }
    }

    private func logDisplay() {
        var record: [String: Any] = ["event": "display", "display": mode.rawValue, "paused": display.paused, "lookup": lastLookup]
        if case .busy(let s) = display.screen { record["retryIn"] = (s * 10).rounded() / 10 }
        diag?(record)
    }

    // MARK: Réseau, cache, décalage

    func setOnline(_ online: Bool) {
        if let service { Task { await service.setOnline(online) } }
        if online {
            if case .offline = display.screen, let lyrics {
                // Les paroles du titre sont déjà en mémoire : on les remet (sans cela l'écran restait sur « Recherche »).
                switch lyrics.kind {
                case .synced: display = DisplayState.reduce(display, .lyricsSynced); allowBackwardOnce = true; evaluateLine(now: ProcessClock.seconds())
                case .plain: display = DisplayState.reduce(display, .lyricsUnsynced)
                case .instrumental: display = DisplayState.reduce(display, .instrumental)
                }
            } else {
                display = DisplayState.reduce(display, .backOnline)
            }
        } else if lyrics == nil {
            // Des paroles déjà affichées ne disparaissent pas parce que le réseau tombe : « Hors connexion » = recherche impossible.
            display = DisplayState.reduce(display, .wentOffline)
        }
        logDisplay()
        updateTimer()
        onDisplayedLinesChanged?()
    }

    func clearCache() {
        guard let service else { return }
        Task {
            await service.clearAll()
            lastIndexCount = await service.indexCount
            cacheMessage = "Cache vidé"
        }
    }

    func refreshStats() async {
        guard let service else { return }
        lastIndexCount = await service.indexCount
    }

    func setManualOffset(_ value: Double) {
        manualOffset = SyncEngine.snappedOffset(value)
        engine.manualOffset = manualOffset
        allowBackwardOnce = true
        diag?(["event": "offset", "offset": manualOffset])
        evaluateLine(now: ProcessClock.seconds())
        onDisplayedLinesChanged?()
    }

    func adjustOffset(by delta: Double) { setManualOffset(manualOffset + delta) }

    // MARK: Minuteur et ligne courante

    private func evaluateLine(now: Double) {
        guard case .synced = display.screen, lyrics?.isSynced == true else { return }
        // Fenêtre cachée : rien n'est publié (SwiftUI redessinerait une fenêtre invisible) ; `setWindowVisible(true)` rattrape.
        guard windowVisible else { return }
        let position = estimator.estimate(at: now)
        let index = engine.index(at: position, previous: currentIndex, allowBackward: allowBackwardOnce)
        allowBackwardOnce = false
        if index != currentIndex {
            currentIndex = index
            publishCount += 1
            lineChanges.append((t: now, index: index, position: position))
            diag?(["event": "line", "index": index, "position": (position * 1000).rounded() / 1000])
            onDisplayedLinesChanged?()
        }
    }

    /// Minuteur 10 Hz, en mode .common (continue pendant un glisser, §3.4) ; ne publie que si l'indice change.
    /// Politique (§3.4/§4) : actif SEULEMENT si la fenêtre est affichée ET qu'une lecture est en cours ET que l'écran a un
    /// défilement à suivre (paroles synchronisées ou bloc non synchronisé). `updateTimer()` est rappelée à chaque changement.
    func startTimer() { timerEnabled = true; updateTimer() }
    func stopTimer() { timerEnabled = false; updateTimer() }
    var timerRunning: Bool { timer != nil }

    func updateTimer() {
        var needed = timerEnabled && windowVisible && estimator.isPlaying && !display.paused
        switch display.screen {
        case .synced, .unsynced: break
        default: needed = false
        }
        if needed, timer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !needed, let t = timer {
            t.invalidate(); timer = nil
        }
    }

    /// Appelée par `PanelController.show()/hide()`. À la ré-apparition : ligne et progression remises à jour d'un coup.
    func setWindowVisible(_ visible: Bool) {
        guard visible != windowVisible else { return }
        windowVisible = visible
        if visible {
            allowBackwardOnce = true
            evaluateLine(now: ProcessClock.seconds())
            tick()
            onDisplayedLinesChanged?()
        }
        updateTimer()
        diag?(["event": "visible", "visible": visible, "timerRunning": timerRunning])
    }

    func tick() {
        guard windowVisible else { return }
        let now = ProcessClock.seconds()
        switch display.screen {
        case .synced:
            guard estimator.isPlaying else { return }
            evaluateLine(now: now)
        case .unsynced:
            let position = estimator.estimate(at: now)
            let span = (track?.duration).flatMap { $0 > 0 ? $0 : nil } ?? 240
            let progress = min(1, max(0, position / span))
            if abs(progress - unsyncedProgress) >= 0.002 { unsyncedProgress = progress; publishCount += 1 }
        default:
            break
        }
    }

    func resetLineChanges() { lineChanges.removeAll() }
}
