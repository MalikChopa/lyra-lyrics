import AppKit
import AppSupport
import LyricsCore
import PlayerKit

/// Chef d'orchestre de l'app : réglages, modèle, service des paroles, fenêtres, raccourci, barre de menus, icône Dock.
@MainActor
final class AppController {
    let store: SettingsStore
    let model = AppModel()
    let recorder = ShortcutRecorder()
    let hotKey = HotKeyService()
    let mainMenu = MainMenuHandler()
    let network = NetworkWatcher()
    private(set) var panelController: PanelController!
    private(set) var settingsController: SettingsPanelController!
    private(set) var aboutController: AboutPanelController!
    private(set) var statusItem: StatusItemController!
    // 1.1.0
    private(set) var welcomeController: WelcomeController!
    private(set) var manualSearch: ManualSearchController!
    let loginItem = LoginItemService()
    let updates = UpdateService()
    private(set) var scene: SceneController!
    private(set) var autoHide = AutoHideState()
    private var autoHideGraceUntil = 0.0
    private var autoHideTask: Task<Void, Never>?
    private(set) var autoHideActions: [AutoHideState.Action] = []
    /// Pochette du titre en cours : politique dans `ArtworkService` (AppSupport).
    private(set) var artwork: ArtworkService!
    private var started = false
    /// Vrais lecteurs (Spotify, Music) ; nil quand un faux lecteur, une sonde ou des aperçus les remplacent (DEBUG).
    private(set) var hub: PlayerHub?
    /// Le transport parle-t-il au vrai réseau (lrclib.net) ? Faux pour le faux serveur local et le transport en processus.
    private(set) var usesNetwork = true
    /// Autorisation avant une commande de lecture (sonde injectable : tests sans invite ni Apple event).
    var permissionFlow = PlaybackPermissionFlow()
    /// Envoi d'une commande de lecture (Apple event hors du fil principal) ; remplaçable dans les tests (DEBUG).
    var commandSender: @Sendable (PlaybackCommand, PlayerID) -> Result<Void, ScriptError> = { AppleEventClient(timeout: 1).send($0, to: $1) }
    /// Une demande d'autorisation (invite) est en cours : les clics suivants sont ignorés.
    private(set) var playbackPermissionBusy = false
    #if DEBUG
    var fakePlayer: FakePlayerSource?
    /// Autotest : les boutons passent par le vrai déroulé d'autorisation (sonde et envoi simulés) au lieu du faux lecteur.
    var playbackFlowUnderTest = false
    #endif

    init(defaults: UserDefaults) {
        store = SettingsStore(defaults: defaults)
        // Politique d'activation : UN réglage (`showsDockIcon`, décoché par défaut), appliqué avant l'affichage de quoi que ce soit.
        applyActivationPolicy()

        let made = Diagnostics.makeLyricsService(defaults: defaults)
        model.service = made.service
        usesNetwork = made.usesNetwork

        let panelActions = PanelActions(
            cycleStyle: { [unowned self] in self.cycleStyle() },
            toggleSettings: { [unowned self] in self.toggleSettings() },
            openAbout: { [unowned self] in self.openAbout() },
            requestMusicAccess: { [unowned self] in self.requestMusicAccess() },
            retryLookup: { [unowned self] in self.model.retryLookup() },
            openManualSearch: { [unowned self] in self.openManualSearch() },
            openScene: { [unowned self] in self.toggleScene() })
        panelController = PanelController(model: model, store: store, actions: panelActions)

        let settingsActions = SettingsActions(
            setStyle: { [unowned self] in self.setStyle($0) },
            setSize: { [unowned self] v in self.change { $0.size = v } },
            setOpacity: { [unowned self] v in self.change { $0.backgroundOpacity = v } },
            setFont: { [unowned self] v in self.change { $0.font = v } },
            setWeight: { [unowned self] v in self.change { $0.fontWeight = v } },
            setGlow: { [unowned self] v in self.change { $0.glow = v } },
            setLineCount: { [unowned self] v in self.change { $0.lineCount = v } },
            applyTheme: { [unowned self] t in self.change { $0.apply(theme: t) } },
            resetWindowSize: { [unowned self] in self.panelController.resetSize(); self.refreshWindows() },
            setArtworkColors: { [unowned self] v in self.change { $0.artworkColors = v } },
            setColor: { [unowned self] v in self.change { $0.colorIndex = v } },
            setClickThrough: { [unowned self] v in self.setClickThrough(v) },
            setDockIcon: { [unowned self] v in self.change { $0.showsDockIcon = v } },
            adjustOffset: { [unowned self] d in self.model.adjustOffset(by: d) },
            resetOffset: { [unowned self] in self.model.setManualOffset(0) },
            clearCache: { [unowned self] in self.model.clearCache() },
            resetHotKey: { [unowned self] in _ = self.applyHotKey(defaultHotKey) },
            openAbout: { [unowned self] in self.openAbout() },
            requestSpotifyAccess: { [unowned self] in self.hub?.requestSpotifyAccess() },
            closeSettings: { [unowned self] in self.settingsController.close() },
            openAutomationSettings: { [unowned self] in self.openAutomationSettings() },
            setLaunchAtLogin: { [unowned self] in self.setLaunchAtLogin($0) },
            setAutoHide: { [unowned self] v in self.change { $0.autoHide = v } },
            setCheckUpdates: { [unowned self] v in self.change { $0.checkUpdates = v } },
            openManualSearch: { [unowned self] in self.openManualSearch() },
            openWelcome: { [unowned self] in self.openWelcome() },
            openUpdatePage: { [unowned self] in self.openUpdatePage() },
            openScene: { [unowned self] in self.toggleScene() },
            setSceneScreen: { [unowned self] v in self.change { $0.sceneScreen = v } },
            setSceneEffects: { [unowned self] v in self.change { $0.sceneEffects = v } },
            setSceneLayout: { [unowned self] v in self.change { $0.sceneLayout = v } },
            setAnimatedBackground: { [unowned self] v in self.change { $0.animatedBackground = v } },
            setKaraokeFill: { [unowned self] v in self.change { $0.karaokeFill = v } })
        settingsController = SettingsPanelController(parent: panelController, model: model, store: store, recorder: recorder, actions: settingsActions)
        aboutController = AboutPanelController(parent: panelController)
        welcomeController = WelcomeController(parent: panelController, model: model, hotKey: { [unowned self] in self.store.settings.hotKey.display },
                                              actions: WelcomeActions(allowSpotify: { [unowned self] in self.hub?.requestSpotifyAccess() },
                                                                      start: { [unowned self] in self.finishWelcome() }))
        manualSearch = ManualSearchController(parent: panelController, model: model)
        model.onActivityMayHaveChanged = { [unowned self] in self.evaluateAutoHide() }
        scene = SceneController(model: model, panelController: panelController, settings: { [unowned self] in self.store.settings })
        scene.onExited = { [unowned self] in self.evaluateAutoHide(); self.statusItem?.refresh() }
        model.onSceneChange = { [unowned self] in self.scene.view?.refresh() }

        recorder.apply = { [unowned self] in self.applyHotKey($0) }
        recorder.suspendGlobal = { [unowned self] suspend in
            if suspend { self.hotKey.unregister(); self.settingsController.panel.makeKey() }
            else { self.registerStoredHotKey() }
        }
        hotKey.onPress = { [unowned self] in self.handleHotKey() }
        model.lineCount = store.settings.lineCount
        setUpArtwork()
        model.onPlayback = { [unowned self] in self.perform($0) }
        model.onSettingsOpened = { [unowned self] in if self.model.spotifyAccess != .granted { self.hub?.refreshSpotifyAccess() } }
        model.onPlaybackRefused = { [unowned self] in self.offerAutomationSettings("Autorisation refusée pour \(Self.playerName(PlayerID(rawValue: self.model.track?.player ?? "spotify") ?? .spotify)).") }
        panelController.onMoved = { [unowned self] in self.settingsController.place() }
        model.onDisplayedLinesChanged = { [unowned self] in
            if self.model.windowVisible { self.panelController.relayout() }
            self.scene.view?.refresh()
        }

        mainMenu.openAbout = { [unowned self] in self.openAbout() }
        mainMenu.openSettings = { [unowned self] in self.openSettings() }

        // Réveil de veille (§3.4) : relevé forcé, la position estimée a pu dériver.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.systemReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self.model.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.refreshWindows()
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        mainMenu.install()
        statusItem = StatusItemController(actions: MenuActions(
            toggleVisibility: { [unowned self] in self.toggleVisibility() },
            toggleClickThrough: { [unowned self] in self.setClickThrough(!self.store.settings.clickThrough) },
            setStyle: { [unowned self] in self.setStyle($0) },
            openSettings: { [unowned self] in self.openSettings() },
            openAbout: { [unowned self] in self.openAbout() },
            quit: { NSApp.terminate(nil) },
            state: { [unowned self] in (self.panelController.isShown, self.store.settings.clickThrough, self.store.settings.style) },
            hotKeyDisplay: { [unowned self] in self.store.settings.hotKey.display },
            openScene: { [unowned self] in self.toggleScene() },
            openManualSearch: { [unowned self] in self.openManualSearch() },
            openWelcome: { [unowned self] in self.openWelcome() },
            openUpdate: { [unowned self] in self.openUpdatePage() },
            updateTag: { [unowned self] in self.model.updateRelease?.tag }))
        panelController.start()
        registerStoredHotKey()
        model.startTimer()
        if Diagnostics.usesRealPlayers {
            #if DEBUG
            // `--players-closed` : vrais chemins de code, mais présence des lecteurs forcée à « non lancés » (mesure : 0 Apple event).
            let hub = PlayerHub(model: model, presence: CommandLine.arguments.contains("--players-closed") ? ClosedPresence() : WorkspacePresence())
            #else
            let hub = PlayerHub(model: model)
            #endif
            self.hub = hub
            model.onRequestSpotifyAccess = { [unowned hub] in hub.requestSpotifyAccess() }
            hub.start()
            #if DEBUG
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let h = self?.hub else { return }
                    DiagLog.shared.write(["event": "hub-stats", "appleEventsSent": h.appleEventsSent, "forcedReads": h.forcedReads])
                }
            }
            #endif
        }
        // 1.1.0 : accueil du premier lancement, état réel du lancement à l'ouverture de session, masquage automatique, mises à jour.
        if Diagnostics.usesRealPlayers {
            autoHideGraceUntil = ProcessClock.seconds() + 6
            showWelcomeIfFirstLaunch()
            syncLoginState()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                await self?.checkForUpdates(force: false)
            }
        }
        evaluateAutoHide()
        if usesNetwork {
            // Hors connexion → aucune requête ; reprise au retour du réseau (§3.5). Jamais pour le bouclage local.
            network.onChange = { [weak self] online in self?.model.setOnline(online) }
            network.start()
        }
    }

    // MARK: Politique d'activation (réglage unique `showsDockIcon`)

    func applyActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy = store.settings.showsDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != wanted {
            NSApp.setActivationPolicy(wanted)
            if started { panelController.show() }
        }
    }

    var activationPolicyName: String {
        switch NSApp.activationPolicy() {
        case .regular: return "regular"
        case .accessory: return "accessory"
        case .prohibited: return "prohibited"
        @unknown default: return "inconnu"
        }
    }

    // MARK: Réglages

    /// Toute modification passe par ici : stockage borné, puis effets sur fenêtres, politique et raccourci.
    func change(_ f: (inout Settings) -> Void) {
        let before = store.settings
        store.update(f)
        let after = store.settings
        if before.showsDockIcon != after.showsDockIcon { applyActivationPolicy() }
        if before.lineCount != after.lineCount { model.lineCount = after.lineCount }
        if before.autoHide != after.autoHide { evaluateAutoHide() }
        if before.artworkColors != after.artworkColors { artworkSettingChanged(after.artworkColors) }
        if !before.clickThrough && after.clickThrough {
            // Le clic-à-travers rend la fenêtre de paroles insensible : le ⚙ n'est plus cliquable, donc le volet (et « À propos »)
            // se ferment tout seuls, et un avis de 3 s dit comment revenir.
            settingsController.close()
            aboutController.close()
            model.showNotice("Clic-à-travers activé · \(after.hotKey.display) pour le couper")
        } else if before.clickThrough && !after.clickThrough {
            model.clearNotice()
        }
        refreshWindows()
    }

    func refreshWindows() {
        panelController.applyWindowProperties()
        panelController.relayout()
        settingsController.place()
        statusItem?.refresh()
    }

    func setStyle(_ style: BackgroundStyle) { change { $0.style = style } }
    func cycleStyle() { setStyle(store.settings.style.next) }
    func setClickThrough(_ on: Bool) { change { $0.clickThrough = on } }

    // MARK: Fenêtres

    /// Raccourci global (décision du 2026-11-17) : il BASCULE le clic-à-travers dans les deux sens ; si la fenêtre est cachée il la montre
    /// (règle pure `HotKeyRule`, même fixture que Windows), il ne la cache jamais. Cacher / montrer la fenêtre se fait par le menu de la barre de menus.
    func handleHotKey() {
        if scene.isVisible { scene.exit(); return }          // le raccourci est aussi la sortie de la Scène
        let outcome = HotKeyRule.decide(windowShown: panelController.isShown, clickThrough: store.settings.clickThrough)
        if outcome.showWindow { panelController.show() }
        setClickThrough(outcome.clickThrough)
        if outcome.showWindow { autoHide.manualChange(windowShown: panelController.isShown) }
        statusItem?.refresh()
    }

    /// Cacher / montrer fait par l'UTILISATEUR (raccourci, menu) : le masquage automatique ne l'annule jamais.
    func toggleVisibility() {
        if panelController.isShown {
            settingsController.close()
            panelController.hide()
            model.hovering = false
        } else {
            panelController.show()
        }
        autoHide.manualChange(windowShown: panelController.isShown)
        statusItem?.refresh()
    }
    /// Scène plein écran : double-clic sur la fenêtre, menu, réglages. Fermée : le volet et À propos se ferment avant le zoom.
    func toggleScene() {
        if scene.isVisible { scene.exit(); return }
        settingsController.close(); aboutController.close(); manualSearch.close()
        scene.enter()
    }
    func openSettings() { if !panelController.isShown { panelController.show() }; settingsController.open() }
    func toggleSettings() { settingsController.isOpen ? settingsController.close() : openSettings() }
    func openAbout() { aboutController.open() }

    // MARK: Raccourci

    func registerStoredHotKey() {
        let ok = hotKey.register(store.settings.hotKey)
        model.hotKeyAvailable = ok
        model.hotKeyMessage = ok ? nil : "raccourci indisponible"
    }

    /// Essaie la nouvelle combinaison ; en cas d'échec, l'ancienne est rétablie et « raccourci indisponible » s'affiche.
    func applyHotKey(_ combo: HotKeyCombo) -> Bool {
        if hotKey.register(combo) {
            store.update { $0.hotKey = combo }
            model.hotKeyAvailable = true; model.hotKeyMessage = nil
            return true
        }
        _ = hotKey.register(store.settings.hotKey)
        model.hotKeyMessage = "raccourci indisponible"
        return false
    }

    // MARK: Veille / réveil

    /// `didWake` → relevé forcé auprès des vrais lecteurs (ou du faux lecteur en DEBUG). Compte les réveils (autotest).
    func handleWake() {
        model.wakeCount += 1
        model.diag?(["event": "wake", "count": model.wakeCount])
        if let hub { Task { await hub.forceRead() } }
        #if DEBUG
        fakePlayer?.forceReading()
        #endif
    }

    // MARK: Autorisations (§3.7)

    /// Ouvre une URL du système (volet Automatisation). Remplaçable : l'autotest n'ouvre JAMAIS les Réglages Système.
    var urlOpener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// URLs que l'app a demandé d'ouvrir (diagnostic).
    var openedURLs: [URL] = []

    /// « Autoriser » (invite du système) ; après un refus, le même bouton devient « Ouvrir les Réglages ».
    func requestMusicAccess() {
        if model.permissionRefused {
            openedURLs.append(PlayerHub.automationSettingsURL)
            urlOpener(PlayerHub.automationSettingsURL)
        } else {
            hub?.requestMusicAccess()
        }
    }

    // MARK: Dock

    /// Clic sur l'icône du Dock : montre la fenêtre.
    /// 1.1.0 (A3) : montre la fenêtre ET ouvre le volet de réglages (relancer l'app = « je cherche les réglages »).
    func handleReopen() {
        reopenCount += 1
        // Relancer l'app (Spotlight, Finder) est aussi une sortie de secours du clic-à-travers.
        if store.settings.clickThrough { setClickThrough(false) }
        if !panelController.isShown { panelController.show() }
        autoHide.manualChange(windowShown: panelController.isShown)
        openSettings()
        statusItem?.refresh()
    }
    private(set) var reopenCount = 0
}


// MARK: 1.1.0 : accueil, ouverture de session, recherche manuelle, masquage automatique, mises à jour
extension AppController {
    func showWelcomeIfFirstLaunch() {
        guard !store.settings.welcomeSeen else { return }
        welcomeController.open()
    }
    func openWelcome() { welcomeController.open() }
    /// « Commencer » (ou fermeture) : l'accueil ne reviendra pas tout seul.
    func finishWelcome() {
        welcomeController.close()
        if !store.settings.welcomeSeen { store.update { $0.welcomeSeen = true } }
        evaluateAutoHide()
    }

    func openManualSearch() {
        guard model.track != nil else { return }
        if !panelController.isShown { panelController.show() }
        manualSearch.open()
    }

    /// Case « Lancer à l'ouverture de session ».
    func setLaunchAtLogin(_ on: Bool) {
        let r = loginItem.setEnabled(on)
        change { $0.launchAtLogin = r.enabled }
        switch (on, r.path) {
        case (true, .smAppService): model.loginMessage = r.message ?? "Enregistré auprès du système (Réglages > Général > Éléments de connexion)."
        case (true, .launchAgent): model.loginMessage = "Le système a refusé l'enregistrement direct : un agent de lancement est utilisé (~/Library/LaunchAgents). Il disparaît quand tu décoches."
        case (true, .none): model.loginMessage = r.message ?? "Le lancement automatique n'a pas pu être activé."
        default: model.loginMessage = nil
        }
        model.diag?(["event": "login-item", "on": on, "path": r.path.rawValue, "enabled": r.enabled])
    }

    /// Au lancement : l'état réel (l'utilisateur a pu retirer l'élément dans les Réglages Système) fait foi.
    func syncLoginState() {
        let actual = loginItem.isEnabled()
        if actual != store.settings.launchAtLogin { change { $0.launchAtLogin = actual } }
    }

    // C1 : masquage automatique
    func evaluateAutoHide() {
        guard started, !model.sceneVisible, !welcomeController.isOpen else { return }
        let now = ProcessClock.seconds()
        if now < autoHideGraceUntil {
            autoHideTask?.cancel()
            let wait = autoHideGraceUntil - now + 0.05
            autoHideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.evaluateAutoHide()
            }
            return
        }
        let action = autoHide.evaluate(mode: store.settings.autoHide, activity: model.activity, windowShown: panelController.isShown)
        guard let action else { return }
        autoHideActions.append(action)
        model.diag?(["event": "auto-hide", "action": "\(action)", "activity": model.activity.rawValue])
        switch action {
        case .hide:
            settingsController.close()
            panelController.hide(animated: true)
            model.hovering = false
        case .show:
            panelController.show(animated: true)
        }
        statusItem?.refresh()
    }

    // E1 : mises à jour
    func checkForUpdates(force: Bool) async {
        let s = store.settings
        guard force || s.checkUpdates else { return }
        let now = Date().timeIntervalSince1970
        guard force || UpdateCheck.isDue(last: s.lastUpdateCheck, now: now) else { return }
        // La date est notée AVANT la requête : au plus une tentative par jour, même si elle échoue.
        store.update { $0.lastUpdateCheck = now }
        let outcome = await updates.check()
        if case .newer(let release) = outcome { model.updateRelease = release } else { model.updateRelease = nil }
        model.diag?(["event": "update-check", "outcome": "\(outcome)"])
        statusItem?.refresh()
    }

    func openUpdatePage() {
        guard let url = model.updateRelease?.url, UpdateCheck.isTrusted(url) else { return }
        openedURLs.append(url)
        urlOpener(url)
    }
}

// MARK: Pochette et boutons de lecture
extension AppController {
    func setUpArtwork() {
        #if DEBUG
        let loopbackHosts: Set<String> = CommandLine.arguments.contains("--fake-player") ? ["127.0.0.1"] : []
        #else
        let loopbackHosts: Set<String> = []
        #endif
        let providers = ArtworkProviders(
            musicData: { [weak self] in
                #if DEBUG
                if let data = await self?.fakeArtworkData(mode: "music") { return data }
                if await self?.fakePlayer != nil { return nil }
                #endif
                return await Task.detached(priority: .utility) { try? AppleEventClient(timeout: 3).readArtwork(player: .music).get().dataValue }.value
            },
            spotifyURL: { [weak self] in
                #if DEBUG
                if let url = await self?.fakeArtworkURL() { return url }
                if await self?.fakePlayer != nil { return nil }
                #endif
                return await Task.detached(priority: .utility) { try? AppleEventClient(timeout: 3).readArtwork(player: .spotify).get().stringValue }.value
            },
            transport: URLSessionArtworkTransport(userAgent: AppIdentity.userAgent, extraHosts: loopbackHosts),
            extraHosts: loopbackHosts)
        artwork = ArtworkService(enabled: { [unowned self] in self.store.settings.artworkColors }, providers: providers,
                                 deliver: { [unowned self] identity, palette in self.model.applyPalette(identity: identity, palette) })
        model.onTrackStarted = { [unowned self] info in
            self.requestArtwork(for: info)
            // 1.0.1 : l'état de l'autorisation Spotify est relu quand un titre Spotify démarre s'il n'est pas déjà accordé ou refusé
            // (lu une seule fois au lancement, il restait « Spotify fermé » si Spotify n'était pas ouvert à ce moment-là).
            if info.player == "spotify", self.model.spotifyAccess != .granted, self.model.spotifyAccess != .denied { self.hub?.refreshSpotifyAccess() }
        }
        artwork.deliverData = { [unowned self] identity, data in
            Task.detached(priority: .utility) {
                let image = ArtworkImage.downscaled(data, maxPixel: 1200)
                let blur = image.flatMap { SceneArtwork.blurred($0) }
                let box = ArtworkImageBox(image: image)
                await MainActor.run { self.model.applyArtworkImage(identity: identity, box.image, blur: blur) }
            }
        }
        model.onTrackStopped = { [unowned self] in self.artwork.cancel() }
    }

    /// Pochette demandée seulement si le réglage est actif ET l'autorisation du lecteur est DÉJÀ accordée (aucune invite provoquée).
    func requestArtwork(for info: TrackInfo) {
        var kind: ArtworkSourceKind = info.player == "music" ? .appleMusic : .spotify
        var permitted = info.player == "music" || model.spotifyAccess == .granted
        #if DEBUG
        if fakePlayer != nil {
            permitted = true
            kind = (fakePlayer?.currentArtwork?.mode.hasPrefix("spotify") == true) ? .spotify : .appleMusic
        }
        #endif
        artwork.trackChanged(identity: info.identity, source: kind, permitted: permitted)
    }

    func artworkSettingChanged(_ enabled: Bool) {
        if enabled {
            if let info = model.track { requestArtwork(for: info) }
        } else {
            artwork.cancel()
            model.clearPalette()
        }
    }

    /// Boutons ⏮ ⏯ ⏭ (1.0.1) : le clic de l'utilisateur est le seul déclencheur. Autorisation Automatisation connue accordée → Apple event
    /// tout de suite (hors du fil principal). Sinon (non déterminée, inconnue, lue bloquée) → `PlaybackPermissionFlow` : explication d'une
    /// ligne dans la fenêtre, invite du système (`AEDeterminePermissionToAutomateTarget`, ask = true, hors du fil principal, 180 s),
    /// puis la commande part si l'accord est donné. Refus : « Ouvrir les Réglages » (jamais redemandé).
    func perform(_ command: PlaybackCommand) {
        #if DEBUG
        if let fakePlayer, !playbackFlowUnderTest {
            fakePlayer.perform(command == .playPause ? "playpause" : command.rawValue)
            return
        }
        #endif
        guard let player = model.track.flatMap({ PlayerID(rawValue: $0.player) }) else { return }
        guard !playbackPermissionBusy else { return }              // une invite est déjà en cours : pas de seconde demande
        Task { @MainActor [weak self] in await self?.performPlayback(command, player: player) }
    }

    /// Nom du lecteur dans les phrases de l'interface.
    static func playerName(_ player: PlayerID) -> String { player == .spotify ? "Spotify" : "Apple Music" }

    private func performPlayback(_ command: PlaybackCommand, player: PlayerID) async {
        let name = Self.playerName(player)
        let sender = commandSender
        func send() async -> Result<Void, ScriptError> {
            await Task.detached(priority: .userInitiated) { sender(command, player) }.value
        }
        func finish(_ result: Result<Void, ScriptError>) async {
            model.diag?(["event": "playback-sent", "command": command.rawValue, "ok": (try? result.get()) != nil])
            // Apple Music ne notifie pas : relevé immédiat pour que l'affichage suive sans attendre les 2 s.
            if player == .music { try? await Task.sleep(for: .milliseconds(250)); await hub?.forceRead() }
        }
        // Autorisation déjà connue accordée (Spotify) ou Music (sa propre invite « Autoriser ») : envoi direct.
        let knownGranted = player == .music || model.spotifyAccess == .granted
        if knownGranted {
            let result = await send()
            if case .failure(let e) = result, e == .denied || e == .consentRequired {
                model.diag?(["event": "playback-permission-lost", "player": player.rawValue])
            } else {
                await finish(result)
                return
            }
        }
        playbackPermissionBusy = true
        defer { playbackPermissionBusy = false }
        let explanation = "Autorise \(AppIdentity.displayName) à piloter \(name) pour utiliser les boutons"
        let outcome = await permissionFlow.prepare(player) { [weak self] in
            await MainActor.run { self?.model.showNotice(explanation, seconds: PlaybackPermissionFlow.askTimeout) }
        }
        if model.notice == explanation { model.clearNotice() }
        model.diag?(["event": "playback-permission", "player": player.rawValue, "outcome": "\(outcome)"])
        switch outcome {
        case .granted:
            if player == .spotify {
                model.spotifyAccess = .granted
                Task { await hub?.spotify.pollNow() }             // relevés de position AppleScript, désormais permis
            } else {
                model.musicPermissionAnswered(.granted)
            }
            await finish(await send())
        case .refused:
            if player == .spotify { model.spotifyAccess = .denied } else { model.musicPermissionAnswered(.denied) }
            offerAutomationSettings("Autorisation refusée pour \(name).")
        case .notRunning:
            model.showNotice("\(name) n'est pas ouvert.")
        case .noAnswer:
            offerAutomationSettings("Pas de réponse de \(name).")
        }
    }

    /// Avis avec le bouton « Ouvrir les Réglages » (volet Automatisation).
    func offerAutomationSettings(_ text: String) {
        model.showNotice(text, seconds: 8, action: AppModel.NoticeAction(label: "Ouvrir les Réglages") { [weak self] in self?.openAutomationSettings() })
    }

    func openAutomationSettings() {
        openedURLs.append(PlayerHub.automationSettingsURL)
        urlOpener(PlayerHub.automationSettingsURL)
    }
}

#if DEBUG
extension AppController {
    func fakeArtworkData(mode: String) -> Data? {
        guard let art = fakePlayer?.currentArtwork, art.mode == mode else { return nil }
        return FakePlayerSource.artworkData(named: art.name)
    }
    /// Spotify simulé : `http://127.0.0.1:<port>/art/<nom>.png` (port du faux serveur `--lyrics-endpoint`) : le GET est RÉEL (bouclage).
    func fakeArtworkURL() -> String? {
        guard let art = fakePlayer?.currentArtwork, art.mode.hasPrefix("spotify"),
              let endpoint = Diagnostics.value(of: "--lyrics-endpoint") else { return nil }
        return endpoint + "/art/" + art.name + ".png" + (art.mode == "spotify-lent" ? "?delay=2" : "")
    }
}
#endif
