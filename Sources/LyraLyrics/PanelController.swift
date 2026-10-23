import AppKit
import SwiftUI
import AppSupport

/// Fenêtre de paroles : hébergement SwiftUI, taille selon le contenu (§4), position mémorisée (UUID d'écran).
@MainActor
final class PanelController: NSObject {
    let panel = LyricsPanel()
    private let model: AppModel
    private let store: SettingsStore
    private var host: PanelHostingView<LyricsView>!
    /// Conteneur du contenu : la vue SwiftUI plus les huit zones de prise du redimensionnement (bords et coins).
    private let container = NSView()
    private var handles: [ResizeHandleView] = []
    /// Redimensionnement à la souris en cours (le volet de réglages garde alors son côté).
    private(set) var isResizing = false
    private var resizeStart: (frame: NSRect, mouse: NSPoint)?
    /// Taille en cours de glissement : n'est écrite dans les réglages qu'au relâchement (pas d'écriture disque à chaque événement).
    private var liveSize: (width: Double, height: Double)?
    private var programmatic = false
    /// Autotest : tant que c'est vrai, le suivi du pointeur RÉEL ne modifie plus `hovering` (le clic synthétique simule un pointeur
    /// posé sur la barre ; sans cela, une sortie réelle du pointeur entre l'ordre et le clic le remettait à faux : défaut intermittent).
    var hoverPinned = false
    private var saveTask: Task<Void, Never>?
    /// Appelé après tout déplacement (le volet de réglages se replace, §7).
    var onMoved: (() -> Void)?

    init(model: AppModel, store: SettingsStore, actions: PanelActions) {
        self.model = model
        self.store = store
        super.init()
        host = PanelHostingView(rootView: LyricsView(model: model, store: store, actions: actions))
        host.sizingOptions = []
        host.onHover = { [weak self] inside in
            guard let self, !self.hoverPinned else { return }
            self.model.hovering = inside && !self.panel.ignoresMouseEvents
        }
        container.wantsLayer = false
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor), host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor), host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        for zone in ResizeZone.allCases {
            let h = ResizeHandleView(zone: zone)
            h.controller = self
            handles.append(h)
            container.addSubview(h)
        }
        panel.contentView = container
        layoutHandles()
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didMove() }
        }
        // Un redimensionnement par le bord droit ne « déplace » pas la fenêtre : le volet doit quand même suivre.
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onMoved?() }
        }
    }

    var screen: NSScreen { panel.screen ?? NSScreen.main ?? NSScreen.screens[0] }

    /// Premier affichage : position restaurée (écran disparu → écran principal) ou position de la maquette (centrée, à 52 % du haut).
    func start() {
        let s = store.settings
        let target = ScreenInfo.screen(withUUID: s.position?.screenUUID) ?? NSScreen.main ?? NSScreen.screens[0]
        let center: NSPoint
        if let p = s.position {
            center = NSPoint(x: target.frame.minX + p.centerX, y: target.frame.minY + p.centerY)
        } else {
            let v = target.visibleFrame
            center = NSPoint(x: v.midX, y: v.minY + v.height * 0.48)
        }
        place(center: center, on: target)
        applyWindowProperties()
        panel.orderFrontRegardless()
    }

    /// Taille imposée (redimensionnement à la souris) ramenée entre 280 × 110 pt et 90 % de la zone visible ; nil = automatique.
    func manualSize(on screen: NSScreen) -> (width: Double, height: Double)? {
        guard let m = liveSize ?? store.settings.manualSize else { return nil }
        let v = screen.visibleFrame
        return LyricsMetrics.clampedSize(width: m.width, height: m.height, visible: (v.width, v.height))
    }

    func recomputeFit(on screen: NSScreen) -> LineFit {
        let s = store.settings
        let fitter = FontResolver.fitter(font: s.font, weight: s.fontWeight)
        let fit: LineFit
        if let m = manualSize(on: screen) {
            // Largeur = retour à la ligne ; hauteur = taille de police effective (entre le plancher et le réglage « Taille »).
            fit = fitter.fit(lines: model.visibleLines, baseSize: Double(s.size), fixedWindowWidth: m.width, fixedWindowHeight: m.height, ratio: s.neighbourRatio)
            if model.windowWidth != m.width { model.windowWidth = m.width }
        } else {
            if model.windowWidth != LyricsMetrics.windowWidth { model.windowWidth = LyricsMetrics.windowWidth }
            fit = fitter.fit(lines: model.visibleLines, baseSize: Double(s.size), visibleHeight: screen.visibleFrame.height, ratio: s.neighbourRatio)
        }
        if model.fit != fit { model.fit = fit }       // une affectation identique réveillerait SwiftUI pour rien
        return fit
    }

    /// Replace la fenêtre autour de `center` avec la hauteur du contenu (ou la taille imposée), bornée à la zone visible de l'écran.
    func place(center: NSPoint, on screen: NSScreen) {
        let fit = recomputeFit(on: screen)
        let width = manualSize(on: screen)?.width ?? LyricsMetrics.windowWidth
        setFrameProgrammatically(clamped(NSRect(x: center.x - width / 2, y: center.y - fit.windowHeight / 2,
                                                width: width, height: fit.windowHeight), in: screen.visibleFrame))
    }

    /// Après un changement de lignes, de taille ou de police : hauteur recalculée, centre conservé (comme la maquette).
    func relayout() {
        guard panel.contentView != nil else { return }
        place(center: NSPoint(x: panel.frame.midX, y: panel.frame.midY), on: screen)
    }

    func applyWindowProperties() {
        let style = model.effectiveStyle(store.settings.style)
        panel.hasShadow = style != .clear
        panel.ignoresMouseEvents = store.settings.clickThrough
        for h in handles { h.isHidden = store.settings.clickThrough }
        if store.settings.clickThrough { model.hovering = false }
        panel.invalidateShadow()
    }

    /// Déplacement « par le code » traité comme un déplacement de l'utilisateur (position enregistrée).
    func move(toCenter center: NSPoint) {
        place(center: center, on: screen)
        didMove(force: true)
    }

    /// Décale horizontalement (volet qui ne tient ni à droite ni à gauche).
    func shift(dx: Double) {
        var f = panel.frame
        f.origin.x += dx
        setFrameProgrammatically(clamped(f, in: screen.visibleFrame))
    }

    private func clamped(_ rect: NSRect, in v: NSRect) -> NSRect {
        var f = rect
        f.origin.x = min(max(f.origin.x, v.minX), max(v.minX, v.maxX - f.width))
        f.origin.y = min(max(f.origin.y, v.minY), max(v.minY, v.maxY - f.height))
        if f.maxY > v.maxY { f.origin.y = v.maxY - f.height }
        return f
    }

    private func setFrameProgrammatically(_ frame: NSRect) {
        guard frame != panel.frame else { return }
        programmatic = true
        panel.setFrame(frame, display: true, animate: false)
        programmatic = false
        layoutHandles()
        panel.invalidateShadow()
    }

    private func didMove(force: Bool = false) {
        onMoved?()
        guard force || !programmatic else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !force { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled, let self else { return }
            self.savePosition()
        }
    }

    func savePosition() {
        let s = screen
        let p = WindowPosition(screenUUID: ScreenInfo.uuid(of: s), centerX: panel.frame.midX - s.frame.minX, centerY: panel.frame.midY - s.frame.minY)
        store.update { $0.position = p }
    }

    // MARK: Redimensionnement à la souris

    func handle(for zone: ResizeZone) -> ResizeHandleView? { handles.first { $0.zone == zone } }

    func layoutHandles() {
        let g = LyricsMetrics.resizeGrip, c = g * 2
        let b = container.bounds
        for h in handles {
            switch h.zone {
            case .left: h.frame = NSRect(x: 0, y: c, width: g, height: max(0, b.height - 2 * c))
            case .right: h.frame = NSRect(x: b.width - g, y: c, width: g, height: max(0, b.height - 2 * c))
            case .bottom: h.frame = NSRect(x: c, y: 0, width: max(0, b.width - 2 * c), height: g)
            case .top: h.frame = NSRect(x: c, y: b.height - g, width: max(0, b.width - 2 * c), height: g)
            case .bottomLeft: h.frame = NSRect(x: 0, y: 0, width: c, height: c)
            case .bottomRight: h.frame = NSRect(x: b.width - c, y: 0, width: c, height: c)
            case .topLeft: h.frame = NSRect(x: 0, y: b.height - c, width: c, height: c)
            case .topRight: h.frame = NSRect(x: b.width - c, y: b.height - c, width: c, height: c)
            }
        }
    }

    /// Début d'un glissement de bord (`mouse` = position de la souris à l'écran).
    func beginResize(at mouse: NSPoint) {
        guard !store.settings.clickThrough else { return }
        isResizing = true
        resizeStart = (panel.frame, mouse)
    }

    /// Glissement : le bord (ou coin) tiré suit la souris, le bord opposé reste fixe ; taille bornée à 280 × 110 pt au minimum et à
    /// 90 % de la zone visible au maximum. La police effective et le retour à la ligne sont recalculés tout de suite.
    func continueResize(zone: ResizeZone, to mouse: NSPoint) {
        guard isResizing, let start = resizeStart else { return }
        let v = screen.visibleFrame
        let maxW = max(LyricsMetrics.minResizeWidth, v.width * LyricsMetrics.maxResizeFraction)
        let maxH = max(LyricsMetrics.minResizeHeight, v.height * LyricsMetrics.maxResizeFraction)
        let dx = mouse.x - start.mouse.x, dy = mouse.y - start.mouse.y
        var f = start.frame
        if zone.movesLeft { let w = min(max(start.frame.width - dx, LyricsMetrics.minResizeWidth), maxW); f.origin.x = start.frame.maxX - w; f.size.width = w }
        if zone.movesRight { f.size.width = min(max(start.frame.width + dx, LyricsMetrics.minResizeWidth), maxW) }
        if zone.movesBottom { let h = min(max(start.frame.height - dy, LyricsMetrics.minResizeHeight), maxH); f.origin.y = start.frame.maxY - h; f.size.height = h }
        if zone.movesTop { f.size.height = min(max(start.frame.height + dy, LyricsMetrics.minResizeHeight), maxH) }
        applyManualSize(width: f.width, height: f.height)
        setFrameProgrammatically(f)
    }

    func endResize() {
        guard isResizing else { return }
        isResizing = false
        resizeStart = nil
        if let live = liveSize { store.update { $0.windowWidth = live.width; $0.windowHeight = live.height } }
        liveSize = nil
        savePosition()
        onMoved?()
    }

    /// Retient la taille (réglages) et recalcule la mise en page ; ne déplace pas la fenêtre.
    private func applyManualSize(width: Double, height: Double) {
        liveSize = (width.rounded(), height.rounded())
        _ = recomputeFit(on: screen)
    }

    /// « Taille par défaut » : retour à 460 pt de large et à la hauteur automatique.
    func resetSize() {
        liveSize = nil
        store.update { $0.windowWidth = nil; $0.windowHeight = nil }
        relayout()
    }

    var isShown: Bool { panel.isVisible }
    func show() { panel.orderFrontRegardless(); model.setWindowVisible(true) }
    func hide() { panel.orderOut(nil); model.setWindowVisible(false) }
}


/// Les huit zones de prise du redimensionnement.
enum ResizeZone: CaseIterable {
    case left, right, bottom, top, bottomLeft, bottomRight, topLeft, topRight
    var movesLeft: Bool { self == .left || self == .bottomLeft || self == .topLeft }
    var movesRight: Bool { self == .right || self == .bottomRight || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }

    /// Curseur de redimensionnement adapté (API macOS 15+ : `NSCursor.frameResize`).
    var cursor: NSCursor {
        switch self {
        case .left: return .frameResize(position: .left, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .top: return .frameResize(position: .top, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        }
    }
}

/// Zone de prise invisible (6 pt sur les bords, 12 pt aux coins). Le panneau est sans bordure et non activant : le système ne
/// fournit aucune poignée, on suit donc la souris à la main (position à l'écran calculée depuis l'événement, pas depuis le pointeur
/// réel : l'autotest envoie des événements synthétiques).
@MainActor
final class ResizeHandleView: NSView {
    let zone: ResizeZone
    weak var controller: PanelController?
    private var area: NSTrackingArea?
    /// Dernier curseur appliqué (autotest : prouve le curseur choisi par zone).
    nonisolated(unsafe) static var lastCursorZone: ResizeZone?

    init(zone: ResizeZone) {
        self.zone = zone
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func cursorUpdate(with event: NSEvent) { zone.cursor.set(); Self.lastCursorZone = zone }
    override func mouseEntered(with event: NSEvent) { zone.cursor.set(); Self.lastCursorZone = zone }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    #if DEBUG
    /// Autotest : les événements souris RÉELS (numéro d'événement non nul ; les événements synthétiques de l'autotest portent 0) sont
    /// ignorés pendant un autotest, pour qu'une main posée sur la souris ne fausse pas les mesures.
    nonisolated(unsafe) static var ignoreRealEvents = false
    private func ignored(_ event: NSEvent) -> Bool { Self.ignoreRealEvents && event.eventNumber != 0 }
    #else
    private func ignored(_ event: NSEvent) -> Bool { false }
    #endif
    private func screenPoint(_ event: NSEvent) -> NSPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? .zero }
    override func mouseDown(with event: NSEvent) { guard !ignored(event) else { return }; controller?.beginResize(at: screenPoint(event)) }
    override func mouseDragged(with event: NSEvent) { guard !ignored(event) else { return }; controller?.continueResize(zone: zone, to: screenPoint(event)) }
    override func mouseUp(with event: NSEvent) { guard !ignored(event) else { return }; controller?.endResize() }
}
