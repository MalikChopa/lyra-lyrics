import AppKit
import QuartzCore
import AppSupport
import LyricsCore

/// Fenêtre de la Scène (S25, S10) : fenêtre sans bordure au niveau « écran de veille » (comme le panneau), qui couvre tout l'écran choisi,
/// au-dessus des apps en plein écran. Entrée : la petite fenêtre « grandit » jusqu'au plein écran (transformation de couche) ; sortie : l'inverse.
@MainActor
final class SceneController {
    enum State: String { case hidden, entering, shown, exiting }

    let panel: KeyablePanel
    private let model: AppModel
    private let panelController: PanelController
    private let settingsProvider: () -> Settings
    private(set) var view: SceneView?
    private(set) var state: State = .hidden
    private var smallPanelWasShown = false
    private var occluded = false
    /// Autotest : tant qu'une valeur simulée est posée, les vraies notifications d'occlusion sont ignorées.
    private var debugOccluded: Bool?
    private var screenAsleep = false
    private var pending: Task<Void, Never>?
    /// Écran utilisé par la dernière entrée (autotest).
    private(set) var lastScreenName = ""
    private(set) var enterCount = 0
    private(set) var exitCount = 0
    static let zoomDuration = 0.75
    /// Rappels : après l'entrée / la sortie (le contrôleur d'app réévalue le masquage automatique).
    var onExited: (() -> Void)?

    init(model: AppModel, panelController: PanelController, settings: @escaping () -> Settings) {
        self.model = model
        self.panelController = panelController
        self.settingsProvider = settings
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        OverlayConfig.apply(to: panel)
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.title = AppIdentity.displayName
        panel.onEscape = { [weak self] in self?.exit() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.occluded = !self.panel.occlusionState.contains(.visible)
                self.applyPause()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAsleep = true; self?.applyPause() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAsleep = false; self?.applyPause() }
        }
    }

    var isVisible: Bool { state != .hidden }

    // MARK: Écran

    static func screenNames() -> [String] { NSScreen.screens.map(\.localizedName) }

    func pickScreen() -> NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main ?? NSScreen() }
        let windowIndex = screens.firstIndex(of: panelController.screen) ?? 0
        let i = SceneScreenChoice.pick(setting: settingsProvider().sceneScreen, names: screens.map(\.localizedName), mainIndex: 0, windowIndex: windowIndex)
        return screens[i]
    }

    // MARK: Entrée / sortie

    func toggle() { state == .shown ? exit() : (state == .hidden ? enter() : ()) }

    func enter() {
        guard state == .hidden else { return }
        let screen = pickScreen()
        lastScreenName = screen.localizedName
        enterCount += 1
        state = .entering
        smallPanelWasShown = panelController.isShown
        let small = panelController.panel.frame
        panel.setFrame(screen.frame, display: false)
        let v = SceneView(frame: NSRect(origin: .zero, size: screen.frame.size), model: model, settings: settingsProvider)
        v.onDoubleClick = { [weak self] in self?.exit() }
        v.onExit = { [weak self] in self?.exit() }
        panel.acceptsMouseMovedEvents = true
        v.autoresizingMask = [.width, .height]
        panel.contentView = v
        view = v
        v.layoutSubtreeIfNeeded()
        model.setSceneVisible(true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(v)
        NSCursor.setHiddenUntilMouseMoves(true)
        v.start()
        let rect = Self.localRect(of: small, on: screen)
        zoom(v, from: rect, entering: true) { [weak self] in
            guard let self, self.state == .entering else { return }
            self.state = .shown
            v.showCardNow()
        }
        // la petite fenêtre se retire en fondu pendant le zoom (le masquage automatique n'y touche pas : il attend la sortie)
        if smallPanelWasShown { panelController.panel.childWindows?.forEach { $0.orderOut(nil) }; panelController.hide(animated: true) }
    }

    func exit() {
        guard state == .shown || state == .entering, let v = view else { return }
        state = .exiting
        exitCount += 1
        let screen = panel.screen ?? pickScreen()
        let small = panelController.panel.frame
        // la petite fenêtre revient en fondu pendant le zoom inverse
        if smallPanelWasShown { panelController.show(animated: true) }
        zoom(v, from: Self.localRect(of: small, on: screen), entering: false) { [weak self] in
            guard let self else { return }
            self.finishExit()
        }
    }

    private func finishExit() {
        view?.stop()
        panel.orderOut(nil)
        panel.contentView = nil
        view = nil
        state = .hidden
        model.setSceneVisible(false)
        NSCursor.unhide()
        onExited?()
    }

    /// Rectangle de la petite fenêtre en coordonnées de l'écran de la Scène ; ailleurs (autre écran), un rectangle centré.
    static func localRect(of frame: NSRect, on screen: NSScreen) -> CGRect {
        if screen.frame.intersects(frame) {
            return CGRect(x: frame.minX - screen.frame.minX, y: frame.minY - screen.frame.minY, width: frame.width, height: frame.height)
        }
        let w = screen.frame.width * 0.27, h = w * 0.42
        return CGRect(x: (screen.frame.width - w) / 2, y: (screen.frame.height - h) / 2, width: w, height: h)
    }

    /// Zoom entre la petite fenêtre et le plein écran, en animations de couche (position, échelle, rayon des coins, opacité).
    private func zoom(_ v: SceneView, from rect: CGRect, entering: Bool, completion: @escaping @MainActor () -> Void) {
        let stage = v.stage
        let W = v.bounds.width, H = v.bounds.height
        let d = model.reduceMotion ? 0.3 : Self.zoomDuration
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        v.inTransition = true
        let s = max(0.05, rect.width / max(1, W))
        let smallPos = CGPoint(x: rect.midX, y: rect.midY)
        let fullPos = CGPoint(x: W / 2, y: H / 2)
        func animate(_ keyPath: String, _ from: Any, _ to: Any, duration: Double = d, delay: Double = 0) {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from; a.toValue = to; a.duration = duration; a.timingFunction = timing
            a.beginTime = CACurrentMediaTime() + delay; a.fillMode = .both
            stage.add(a, forKey: "pf.zoom." + keyPath)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stage.position = entering ? fullPos : smallPos
        stage.transform = entering ? CATransform3DIdentity : CATransform3DMakeScale(s, s, 1)
        stage.cornerRadius = entering ? 0 : 24 / s
        stage.opacity = entering ? 1 : 0
        CATransaction.commit()
        if model.reduceMotion {
            stage.position = fullPos; stage.transform = CATransform3DIdentity; stage.cornerRadius = 0
            CATransaction.begin(); CATransaction.setDisableActions(true)
            stage.opacity = entering ? 1 : 0
            CATransaction.commit()
            animate("opacity", entering ? 0.0 : 1.0, entering ? 1.0 : 0.0)
        } else {
            animate("position", NSValue(point: entering ? smallPos : fullPos), NSValue(point: entering ? fullPos : smallPos))
            animate("transform.scale", entering ? s : 1.0, entering ? 1.0 : s)
            animate("cornerRadius", entering ? 24 / s : 0.0, entering ? 0.0 : 24 / s)
            // la scène apparaît vite au début du zoom, disparaît vite à la fin (la petite fenêtre prend le relais)
            animate("opacity", entering ? 0.0 : 1.0, entering ? 1.0 : 0.0, duration: d * 0.5, delay: entering ? 0 : d * 0.5)
        }
        pending?.cancel()
        pending = Task { @MainActor [weak self, weak v] in
            try? await Task.sleep(for: .seconds(d + 0.05))
            guard !Task.isCancelled, let self else { return }
            v?.inTransition = false
            v?.stage.removeAllAnimations()
            completion()
        }
    }

    // MARK: Pause des animations

    private func applyPause() {
        view?.setAnimationsPaused((debugOccluded ?? occluded) || screenAsleep)
    }
    /// Autotest : simule une fenêtre masquée / un écran en veille par le même chemin que les notifications.
    func debugSetOccluded(_ on: Bool) { debugOccluded = on; applyPause() }
    var animationsPaused: Bool { view?.animationsPaused ?? false }
}
