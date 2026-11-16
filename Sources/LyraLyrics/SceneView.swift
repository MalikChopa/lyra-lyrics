import AppKit
import QuartzCore
import AppSupport
import LyricsCore

/// Une ligne de la Scène : trois bitmaps (net blanc, accent, flou) dessinés UNE fois à la taille propre de la ligne, puis mis à l'échelle
/// et déplacés par des animations de couche (aucun redessin pendant les mouvements).
@MainActor
final class SceneLine {
    let index: Int
    let text: String
    let container = CALayer()
    let base = TextBitmapLayer()
    let accent = TextBitmapLayer()
    let soft = TextBitmapLayer()
    let size: Double
    let height: Double
    let style: LineStackStyle
    /// Rôle pour lequel la mise en page a été faite (0 courante, 1 suivante, 2 d'après) : les voisines sont mises en page plus large,
    /// de sorte qu'une fois réduites elles occupent la même largeur utile que la courante.
    let role: Int
    var fill: FillMask?
    /// Vrai une fois la sortie mot à mot lancée (la ligne ne doit plus être replacée tant qu'elle n'est pas redevenue courante).
    var leaving = false

    init(index: Int, role: Int = 0, text: String, font: LyricFont, weight: LyricWeight, size: Double, width: Double, textColor: RGB, accentColor: RGB, glow: Bool, scale: Double) {
        self.index = index; self.role = role; self.text = text; self.size = size
        container.name = "r\(role)|\(text)"      // repère d'autotest (sonde de transition)
        height = FontResolver.measureHeight(text, size: size, width: width, font: font, weight: weight)
        style = LineStackStyle(font: font, weight: weight, size: size, ratio: 1, color: textColor, fillColor: accentColor, glow: glow, clearShadow: false, width: width)
        let pad = TextBitmapLayer.padding
        let b = CGRect(x: 0, y: 0, width: width + 2 * pad, height: height + 2 * pad)
        container.bounds = b
        for (layer, color, isSoft, withGlow) in [(soft, NSColor(srgbRed: textColor.r, green: textColor.g, blue: textColor.b, alpha: 1), true, false), (base, NSColor(srgbRed: textColor.r, green: textColor.g, blue: textColor.b, alpha: 1), false, false), (accent, NSColor(srgbRed: accentColor.r, green: accentColor.g, blue: accentColor.b, alpha: 1), false, glow)] {
            layer.contentsScale = scale
            layer.bounds = b
            layer.position = CGPoint(x: b.midX, y: b.midY)
            layer.text = text
            var st = style; st.glow = withGlow
            layer.look = st
            layer.tint = color
            layer.soft = isSoft
            layer.softRadius = max(2.4, size / 26 * 1.6)
            layer.setNeedsDisplay()
            container.addSublayer(layer)
        }
        soft.opacity = 0
        accent.opacity = 0
    }
}

/// Contenu plein écran de la Scène. Tout est en couches Core Animation (aucune vue SwiftUI, aucun redessin par image) :
/// fond (dégradé de la palette + pochette floutée qui dérive), voile de contraste, lignes, passages sans paroles, carte du titre,
/// vignette et grain. Règles de sobriété : voir `docs/ARCHITECTURE.md` §14.6.
@MainActor
final class SceneView: NSView {
    let model: AppModel
    let settingsProvider: () -> Settings
    var onDoubleClick: (() -> Void)?

    // couches
    let stage = CALayer()
    private let gradient = CAGradientLayer()
    private let artHolder = CALayer()
    private var artLayer: CALayer?
    private let scrim = CALayer()
    let content = CALayer()
    private let linesLayer = CALayer()
    private let infoLayer = CALayer()
    private let infoTitle = CATextLayer()
    private let infoSub = CATextLayer()
    private let gapLayer = CALayer()
    private let note = CATextLayer()
    private let emitter = CAEmitterLayer()
    private var shimmer: ShimmerLayer?
    let card = CALayer()
    private let vignette = CAGradientLayer()
    let bar = SceneControlsBar()
    let artPanel = SceneArtPanel()
    private(set) var lastLeave = LeaveRecord()
    private(set) var leaveCount = 0
    private(set) var glideCount = 0
    private(set) var breathPausedCount = 0
    private var breathPaused = false
    private var breathResume: DispatchWorkItem?
    private var layoutSignature = ""
    private var lastArtShown: CGImage?
    private(set) var barCommands: [String] = []
    private let grain = CAReplicatorLayer()

    // état
    private var lines: [Int: SceneLine] = [:]
    private var gaps: [SceneMath.Gap] = []
    private var gapsKey = ""
    private var lastEpoch = -1
    private var lastArtRevision = -1
    private var lastIndex = Int.min
    private var lastMode: DisplayMode?
    private var tickTimer: Timer?
    private var cardTask: Task<Void, Never>?
    private var cardPending = false
    private(set) var artTarget = 0.0
    private(set) var animationsPaused = false
    private var scale: Double { Double(window?.backingScaleFactor ?? 2) }

    // observables d'autotest
    private(set) var cardShownCount = 0
    private(set) var cardActive = false
    private(set) var cardTitle = ""
    private(set) var gapActive = false
    private(set) var gapAnimating = false
    private(set) var gapStarts = 0
    private(set) var gapStops = 0
    private(set) var scrimAlpha = 0.0
    private(set) var minContrast = 21.0
    private(set) var backgroundSwaps = 0
    private(set) var fillStarts = 0
    private(set) var currentLineIndex = -2
    private(set) var lastFillDuration = 0.0
    private(set) var currentTextSize = 0.0
    private(set) var currentTextWidthFraction = 0.0

    init(frame: NSRect, model: AppModel, settings: @escaping () -> Settings) {
        self.model = model
        self.settingsProvider = settings
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if exitControlShown && exitControlFrame.contains(p) { onExit?(); return }
        if exitControlShown, let name = bar.hit(p) { barPress(name); pointerMoved(); return }
        pointerMoved()
        if event.clickCount >= 2 { onDoubleClick?() }
    }

    // MARK: Contrôle de sortie (1.1.0) : discret, apparaît quand la souris bouge, disparaît après 3 s (Échap et double-clic restent)

    /// Quitter la Scène (contrôle de sortie).
    var onExit: (() -> Void)?
    static let exitSize = 44.0
    static let exitMargin = 26.0
    static let exitHideDelay = 3.0
    private let exitControl = CALayer()
    private var exitHideItem: DispatchWorkItem?
    private var exitTracking: NSTrackingArea?
    /// Vrai tant que le contrôle est affiché (logique : l'opacité suit en fondu).
    private(set) var exitControlShown = false
    private(set) var exitShowCount = 0
    var exitControlFrame: CGRect { CGRect(x: W - Self.exitMargin - Self.exitSize, y: H - Self.exitMargin - Self.exitSize, width: Self.exitSize, height: Self.exitSize) }

    private func buildExitControl() {
        exitControl.bounds = CGRect(x: 0, y: 0, width: Self.exitSize, height: Self.exitSize)
        exitControl.cornerRadius = Self.exitSize / 2
        exitControl.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        exitControl.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        exitControl.borderWidth = 1
        exitControl.opacity = 0
        exitControl.contentsScale = 2
        exitControl.contentsGravity = .center
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        exitControl.contents = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer?.addSublayer(exitControl)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = exitTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        exitTracking = t
    }
    override func mouseMoved(with event: NSEvent) { pointerMoved() }

    /// La souris a bougé : montre le contrôle (jamais pendant le zoom) et relance le compte à rebours de 3 s.
    func pointerMoved() {
        guard !inTransition else { return }
        setExitControl(visible: true)
        exitHideItem?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hideExitControlWhenIdle() } }
        exitHideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exitHideDelay, execute: item)
    }

    /// Autotest : cache le contrôle tout de suite (le vrai pointeur de la machine peut l'avoir montré).
    func debugHideExitControl() { exitHideItem?.cancel(); setExitControl(visible: false) }

    private func hideExitControlWhenIdle() {
        // le pointeur posé sur le contrôle le garde visible
        if let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if exitControlShown && exitControlFrame.contains(p) { pointerMoved(); return }
        }
        setExitControl(visible: false)
    }

    private func setExitControl(visible: Bool) {
        if visible && !exitControlShown { exitShowCount += 1 }
        guard visible != exitControlShown else { return }
        exitControlShown = visible
        CATransaction.begin()
        CATransaction.setAnimationDuration(visible ? 0.2 : 0.6)
        exitControl.opacity = visible ? 1 : 0
        bar.layer.opacity = visible ? 1 : 0
        CATransaction.commit()
        if visible { updateBar() }
    }

    override func accessibilityChildren() -> [Any]? {
        let e = ExitAccessibilityElement()
        e.setAccessibilityRole(.button)
        e.setAccessibilityLabel("Quitter le plein écran")
        e.setAccessibilityParent(self)
        e.setAccessibilityFrameInParentSpace(exitControlFrame)
        e.press = { [weak self] in self?.onExit?() }
        var all: [Any] = [e]
        for name in bar.allButtonNames where name != "exit" {
            let b = ExitAccessibilityElement()
            b.setAccessibilityRole(.button)
            b.setAccessibilityLabel(bar.label(of: name))
            b.setAccessibilityParent(self)
            b.setAccessibilityFrameInParentSpace(bar.frame(of: name))
            b.press = { [weak self] in self?.barPress(name) }
            all.append(b)
        }
        return all
    }

    private var W: Double { bounds.width }
    private var H: Double { bounds.height }

    // MARK: Construction

    private func build() {
        layer?.addSublayer(stage)
        stage.masksToBounds = true
        stage.backgroundColor = NSColor.black.cgColor
        stage.addSublayer(gradient)
        stage.addSublayer(artHolder)
        scrim.backgroundColor = NSColor.black.cgColor
        scrim.opacity = 0.4
        stage.addSublayer(scrim)
        stage.addSublayer(content)
        content.addSublayer(artPanel.layer)
        content.addSublayer(linesLayer)
        content.addSublayer(infoLayer)
        content.addSublayer(gapLayer)
        for t in [infoTitle, infoSub, note] {
            t.alignmentMode = .center
            t.truncationMode = .end
            t.isWrapped = true
            infoLayer.addSublayer(t)
        }
        note.removeFromSuperlayer()
        gapLayer.addSublayer(note)
        gapLayer.addSublayer(emitter)
        gapLayer.opacity = 0
        stage.addSublayer(card)
        card.opacity = 0
        stage.addSublayer(vignette)
        stage.addSublayer(grain)
        buildExitControl()
        layer?.addSublayer(bar.layer)
        vignette.type = .radial
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5); vignette.endPoint = CGPoint(x: 1, y: 1)
        vignette.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.34).cgColor]
        vignette.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0, y: 1); gradient.endPoint = CGPoint(x: 1, y: 0)
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.frame = bounds
        exitControl.frame = exitControlFrame
        bar.layout(W: W, scale: scale)
        stage.bounds = CGRect(x: 0, y: 0, width: W, height: H)
        if !inTransition { stage.position = CGPoint(x: W / 2, y: H / 2) }
        for l in [gradient, scrim, content, vignette, linesLayer, infoLayer, gapLayer, card, artPanel.layer] { l.frame = stage.bounds }
        artHolder.frame = stage.bounds
        let fonts = settingsProvider()
        layoutInfo(fonts)
        layoutGap()
        layoutArtPanel()
        layoutGrain()
        CATransaction.commit()
    }
    /// Le contrôleur pose la position de la scène pendant le zoom.
    var inTransition = false

    private func layoutGrain() {
        grain.sublayers = nil
        grain.frame = stage.bounds
        guard let tile = SceneArtwork.grainTile() else { return }
        let side = 256.0 / scale
        let t = CALayer()
        t.contents = tile; t.contentsScale = scale; t.frame = CGRect(x: 0, y: 0, width: side, height: side)
        t.magnificationFilter = .nearest
        let rows = CAReplicatorLayer()
        rows.frame = stage.bounds
        rows.instanceCount = Int((W / side).rounded(.up)) + 1
        rows.instanceTransform = CATransform3DMakeTranslation(side, 0, 0)
        rows.addSublayer(t)
        grain.instanceCount = Int((H / side).rounded(.up)) + 1
        grain.instanceTransform = CATransform3DMakeTranslation(0, side, 0)
        grain.addSublayer(rows)
    }

    private func layoutGap() {
        note.fontSize = H * 0.13
        note.string = "♪"
        note.frame = CGRect(x: textCenterX - H * 0.1, y: H * 0.5, width: H * 0.2, height: H * 0.17)
        note.contentsScale = scale
        note.foregroundColor = NSColor.white.cgColor
        emitter.frame = gapLayer.bounds
        emitter.emitterPosition = CGPoint(x: textCenterX, y: H * 0.12)
        emitter.emitterSize = CGSize(width: textWidth, height: 10)
        emitter.emitterShape = .line
        if emitter.emitterCells == nil, let dot = SceneArtwork.softDot() {
            let c = CAEmitterCell()
            c.contents = dot
            c.birthRate = 3.4; c.lifetime = 8                   // 3,4 × 8 = 27 particules au plus (≤ 30)
            c.velocity = 22; c.velocityRange = 8
            c.emissionLongitude = .pi / 2; c.emissionRange = 0.35
            c.scale = 0.32; c.scaleRange = 0.18
            c.alphaSpeed = -0.07
            c.color = NSColor.white.withAlphaComponent(0.55).cgColor
            emitter.emitterCells = [c]
        }
        emitter.birthRate = gapActive ? 1 : 0
    }

    // MARK: Données

    private var settings: Settings { settingsProvider() }
    private var reduceMotion: Bool { model.reduceMotion }
    // Mise en page (1.1.0) : « Avec la pochette » = pochette nette à gauche, paroles à droite ; « Paroles seules » = paroles centrées.
    var withArtwork: Bool { settings.sceneLayout == .withArtwork }
    var artSide: Double { min(W * 0.34, H * 0.56) }
    var artLeft: Double { W * 0.05 }
    var columnLeft: Double { artLeft + artSide + W * 0.04 }
    var textWidth: Double { withArtwork ? (W * 0.95 - columnLeft) * 0.96 : W * 0.70 }
    var textCenterX: Double { withArtwork ? (columnLeft + W * 0.95) / 2 : W / 2 }
    private var lineTimes: [LyricLineTime] { model.syncedLines.map { LyricLineTime(time: $0.time, text: $0.text) } }

    // MARK: Cycle de vie

    func start() {
        guard tickTimer == nil else { return }
        started = true
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
        lastEpoch = model.trackEpoch; lastArtRevision = -1; lastIndex = Int.min; lastMode = nil
        refresh(animated: false)
    }
    func stop() {
        exitHideItem?.cancel(); exitHideItem = nil
        tickTimer?.invalidate(); tickTimer = nil
        cardTask?.cancel(); cardTask = nil
        setGap(false, immediate: true)
    }

    /// Toutes les 250 ms : passage sans paroles et dérive du remplissage (aucun travail de couche si rien ne change).
    private func tick() {
        guard !animationsPaused else { return }
        let want = desiredGap()
        if want != gapActive { setGap(want, immediate: false); updateLines(animated: true) }
        syncFill()
        if exitControlShown { updateBar() }
    }

    // MARK: Rafraîchissement

    private var started = false
    /// Ce qui est « cuit » dans les bitmaps des lignes (couleurs du texte et de l'accent, police, graisse, lueur) : s'il change, les lignes sont refaites.
    private var lineStyleSignature = ""
    func refresh(animated: Bool = true) {
        guard started else { return }
        applyEffectFlags()
        var animated = animated
        let layoutNow = "\(settings.sceneLayout.rawValue)"
        if layoutNow != layoutSignature {
            let first = layoutSignature.isEmpty
            layoutSignature = layoutNow
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layoutInfo(settings); layoutGap(); layoutArtPanel()
            if let s = shimmer { s.position = CGPoint(x: textCenterX, y: H * 0.5) }
            CATransaction.commit()
            if !first { clearLines(); lastIndex = Int.min; animated = false; cancelCard() }
        }
        if reduceMotion { stopBreath() } else { startBreath() }
        let signature = "\(model.lineColor(settings).hex)|\(fillEnabled ? model.accentColor(settings).hex : "-")|\(settings.font.rawValue)|\(settings.fontWeight.rawValue)|\(settings.glow)"
        if signature != lineStyleSignature {
            if !lineStyleSignature.isEmpty { clearLines(); lastIndex = Int.min; animated = false }
            lineStyleSignature = signature
        }
        let epoch = model.trackEpoch
        if epoch != lastEpoch {
            lastEpoch = epoch
            clearLines()
            lastIndex = Int.min
            if model.track != nil { scheduleCard() } else { cancelCard() }
        }
        updateArtPanel(animated: animated)
        if model.artworkRevision != lastArtRevision {
            lastArtRevision = model.artworkRevision
            updateBackground(animated: animated)
            if cardPending, model.artworkImage != nil { startCard("artwork") }
        } else if lastMode == nil { updateBackground(animated: false) }
        let mode = model.mode
        if mode != lastMode { lastMode = mode; modeChanged() }
        switch mode {
        case .synced: updateLines(animated: animated && !(cardActive))
        default: break
        }
        if mode != .synced { updateInfo() }
        let want = desiredGap()
        if want != gapActive { setGap(want, immediate: false); if mode == .synced { updateLines(animated: animated) } }
    }

    private func modeChanged() {
        // lignes seulement en mode synchronisé ; recherche : barres fantômes ; autres états : bloc d'information
        if lastMode != .synced { clearLines() }
        shimmer?.removeFromSuperlayer(); shimmer = nil
        if lastMode == .searching {
            let s = ShimmerLayer(size: CGSize(width: textWidth, height: H * 0.30), barFractions: [0.8, 0.95, 0.62], barHeight: H * 0.018, spacing: H * 0.03,
                                 animated: !reduceMotion, delay: 0.45)
            s.position = CGPoint(x: textCenterX, y: H * 0.5)
            content.addSublayer(s)
            shimmer = s
        }
        infoLayer.opacity = (lastMode == .synced || lastMode == .searching) ? 0 : 1
        if lastMode != .synced && lastMode != .searching { updateInfo() }
    }

    private func applyEffectFlags() {
        let on = settings.sceneEffects
        CATransaction.begin(); CATransaction.setAnimationDuration(0.6)
        vignette.opacity = on ? 1 : 0
        grain.opacity = on ? 1 : 0
        CATransaction.commit()
    }

    // MARK: Barre de commandes (1.1.0) et clavier

    /// Appui sur un bouton de la barre : mêmes commandes que la barre au survol de la petite fenêtre (déroulé d'autorisation de la 1.0.1 compris).
    func barPress(_ name: String) {
        barCommands.append(name)
        switch name {
        case "previous": model.sendPlayback(.previous)
        case "next": model.sendPlayback(.next)
        case "playPause": model.sendPlayback(.playPause)
        case "exit": onExit?()
        default: break
        }
    }

    /// Temps écoulé, durée et icône de lecture ; seulement quand la barre est visible.
    func updateBar() {
        bar.update(position: model.positionEstimate, duration: model.track?.duration, playing: model.isPlayingNow)
    }

    /// Espace = lecture/pause, flèches = précédent/suivant (Échap est géré par le panneau).
    override func keyDown(with event: NSEvent) {
        #if DEBUG
        if KeyablePanel.selftestActive && !KeyablePanel.injecting { return }
        #endif
        switch event.keyCode {
        case 49: barCommands.append("key-space"); model.sendPlayback(.playPause)
        case 123: barCommands.append("key-left"); model.sendPlayback(.previous)
        case 124: barCommands.append("key-right"); model.sendPlayback(.next)
        default: super.keyDown(with: event); return
        }
        pointerMoved()
    }

    // MARK: Pochette et titre (mise en page « Avec la pochette »)

    private func layoutArtPanel() {
        artPanel.layout(x: artLeft, centerY: H * 0.56, side: artSide, H: H, scale: scale, font: settings.font, weight: settings.fontWeight)
        artPanel.layer.isHidden = !withArtwork
    }

    private func updateArtPanel(animated: Bool) {
        guard withArtwork else { return }
        if let t = model.track { artPanel.setTrack(title: t.title, artist: t.artist) } else { artPanel.setTrack(title: "", artist: "") }
        let image = model.track == nil ? nil : model.artworkImage
        if image !== lastArtShown || !artPanel.hasImage && image != nil {
            artPanel.setArtwork(image, animated: animated && !reduceMotion && lastArtShown != nil)
            lastArtShown = image
        }
    }

    // MARK: Respiration du fond (1.1.0) : le dégradé de la palette respire lentement ; à l'arrêt pendant que les lignes bougent

    private func startBreath() {
        guard !reduceMotion, gradient.animation(forKey: "pf.breath") == nil else { return }
        let a = CABasicAnimation(keyPath: "locations")
        a.fromValue = [0.0, 0.5, 1.0]; a.toValue = [0.0, 0.3, 0.76]
        a.duration = 26; a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(a, forKey: "pf.breath")
        breathPaused = false
    }
    private func stopBreath() { gradient.removeAnimation(forKey: "pf.breath"); breathPaused = false }
    var breathRunning: Bool { gradient.animation(forKey: "pf.breath") != nil && !breathPaused }
    var breathActive: Bool { gradient.animation(forKey: "pf.breath") != nil }

    /// Les lignes bougent : la respiration attend (au plus 2 effets en mouvement : lignes + dérive de la pochette).
    private func pauseBreathWhileLinesMove() {
        guard gradient.animation(forKey: "pf.breath") != nil else { return }
        if !breathPaused {
            let t = gradient.convertTime(CACurrentMediaTime(), from: nil)
            gradient.speed = 0; gradient.timeOffset = t
            breathPaused = true; breathPausedCount += 1
        }
        breathResume?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.resumeBreath() } }
        breathResume = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: item)
    }
    private func resumeBreath() {
        guard breathPaused else { return }
        let pausedAt = gradient.timeOffset
        gradient.speed = 1; gradient.timeOffset = 0; gradient.beginTime = 0
        gradient.beginTime = gradient.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        breathPaused = false
    }

    // MARK: Fond (S1)

    private func updateBackground(animated: Bool) {
        let palette = model.palette
        let reduceTransparency = model.reduceTransparency
        func cg(_ c: RGB, _ k: Double = 1) -> CGColor { NSColor(srgbRed: c.r * k, green: c.g * k, blue: c.b * k, alpha: 1).cgColor }
        let colors: [CGColor]
        var gradientLum = 0.02
        if let p = palette, settings.artworkColors {
            colors = [cg(p.dominant, 0.62), cg(p.tint), cg(p.secondary, 0.45)]
            gradientLum = max(p.dominant.luminance * 0.4, p.secondary.luminance * 0.25, p.tint.luminance)
        } else {
            colors = [NSColor(srgbRed: 0.10, green: 0.13, blue: 0.24, alpha: 1).cgColor, NSColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.14, green: 0.08, blue: 0.20, alpha: 1).cgColor]
            gradientLum = 0.02
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? 1.4 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        gradient.colors = colors
        CATransaction.commit()

        // pochette floutée : fondu enchaîné avec la précédente (« Réduire la transparence » : fond plein, sans image)
        var artLum = 0.0
        if let blur = model.artworkBlur, !reduceTransparency, settings.artworkColors {
            artLum = model.artworkBlurLuminance
            let new = CALayer()
            let bw = W * 1.45, bh = H * 1.45
            new.bounds = CGRect(x: 0, y: 0, width: bw, height: bh)
            new.position = CGPoint(x: W / 2, y: H / 2)
            new.contents = blur
            new.contentsGravity = .resizeAspectFill
            new.magnificationFilter = .linear
            new.opacity = 0
            artHolder.addSublayer(new)
            let old = artLayer
            artLayer = new
            backgroundSwaps += 1
            let dur = animated && !reduceMotion ? 1.4 : 0.01
            artTarget = 0.92
            fade(new, to: 0.92, duration: dur)
            if let old { fade(old, to: 0, duration: dur) { old.removeFromSuperlayer() } }
            if !reduceMotion { addDrift(to: new) }
        } else if let old = artLayer {
            artLayer = nil
            fade(old, to: 0, duration: animated && !reduceMotion ? 1.0 : 0.01) { old.removeFromSuperlayer() }
        }

        // fond effectif réglé pour que le texte garde 4,5 : 1 au moins (SceneMath.background, testé)
        let accentLum = fillEnabled ? min(model.lineColor(settings).luminance, model.accentColor(settings).luminance) : model.lineColor(settings).luminance
        let textLum = min(accentLum, 0.7)
        let bal = SceneMath.background(artLuminance: artLum, gradientLuminance: gradientLum, textLuminance: textLum)
        scrimAlpha = bal.scrim
        minContrast = bal.contrast
        artTarget = artLayer == nil ? 0 : bal.artOpacity
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? 1.0 : 0)
        scrim.opacity = Float(bal.scrim)
        if let art = artLayer, art.opacity > 0 || artTarget > 0 { art.opacity = Float(bal.artOpacity) }
        CATransaction.commit()
    }

    private func fade(_ layer: CALayer, to value: Float, duration: Double, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        if let completion { CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } } }
        layer.opacity = value
        CATransaction.commit()
    }

    /// Dérive lente (cycle 48 s, aller-retour ; un peu plus ample qu'en 1.1.0 initiale) : échelle et position, courbes douces.
    private func addDrift(to layer: CALayer) {
        let s = CABasicAnimation(keyPath: "transform.scale")
        s.fromValue = 1.0; s.toValue = 1.2
        let p = CABasicAnimation(keyPath: "position")
        p.fromValue = NSValue(point: CGPoint(x: W / 2 - W * 0.055, y: H / 2 - H * 0.035))
        p.toValue = NSValue(point: CGPoint(x: W / 2 + W * 0.055, y: H / 2 + H * 0.04))
        for a in [s, p] {
            a.duration = 48; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        layer.add(s, forKey: "pf.drift.scale"); layer.add(p, forKey: "pf.drift.pos")
    }
    /// Sonde d'autotest : état PRÉSENTÉ de chaque couche de ligne (texte, rôle de mise en page, ordonnée dans la scène, opacité effective).
    func debugLineLayers() -> [(text: String, role: Int, y: Double, opacity: Double)] {
        (linesLayer.sublayers ?? []).compactMap { c in
            guard let name = c.name, name.hasPrefix("r"), let bar = name.firstIndex(of: "|"), let p = c.presentation() else { return nil }
            let inner = (c.sublayers ?? []).map { Double($0.presentation()?.opacity ?? $0.opacity) }.max() ?? 1
            return (String(name[name.index(after: bar)...]), Int(name[name.index(after: name.startIndex)..<bar]) ?? -1,
                    Double(p.position.y), c.isHidden ? 0 : Double(p.opacity) * inner)
        }
    }
    var driftActive: Bool { artLayer?.animation(forKey: "pf.drift.scale") != nil }
    var artLayerPresent: Bool { artLayer != nil }

    // MARK: Lignes (S4) et remplissage (S5)

    private func clearLines() {
        for l in lines.values { l.container.removeFromSuperlayer() }
        lines.removeAll()
        currentLineIndex = -2
    }

    /// Échelle d'affichage selon le rôle de la ligne (0 courante, 1 suivante, 2 d'après).
    private static func displayScale(role: Int) -> Double { role == 0 ? 1 : (role == 1 ? 0.5 : 0.42) }
    private static func role(forOffset off: Int) -> Int { off <= 0 ? 0 : min(off, 2) }
    /// Largeur de mise en page : une fois réduite à l'échelle du rôle, la ligne occupe la même largeur utile (`textWidth`) que la courante.
    private func layoutWidth(role: Int) -> Double { textWidth / SceneView.displayScale(role: role) }

    private func fitSize(for text: String, role: Int) -> Double {
        let s = settings
        let sc = SceneView.displayScale(role: role)
        let maxSize = min(max(H * 0.085, 44), 124)
        return SceneMath.fitSize(text: text, width: layoutWidth(role: role), maxHeight: H * 0.27 / sc, maxSize: maxSize) { t, size, width in
            FontResolver.measureHeight(t, size: size, width: width, font: s.font, weight: s.fontWeight)
        }
    }

    private func updateLines(animated: Bool) {
        let all = model.syncedLines
        guard !all.isEmpty else { return }
        let idx = model.currentIndex
        let wanted = Set(((idx - 1)...(idx + 2)).filter { $0 >= 0 && $0 < all.count })
        // Le texte garde la couleur choisie ; l'accent de la pochette ne teinte que la partie remplie du karaoké.
        let textColor = model.lineColor(settings)
        let accent = fillEnabled ? model.accentColor(settings) : textColor
        let s = settings
        for i in Array(lines.keys) where !wanted.contains(i) {
            if let l = lines[i] {
                lines[i] = nil
                // sortie : la ligne a déjà fondu (rôle -1) ; retrait à la fin de l'animation
                let done = l.container
                DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 1.0 : 0)) { done.removeFromSuperlayer() }
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        var ghosts: [CALayer] = []
        var ghostPairs: [(ghost: CALayer, index: Int)] = []
        var starts: [Int: (y: Double, scale: Double, opacity: Double)] = [:]     // lignes neuves : état de départ de l'arrivée (animation explicite)
        for i in wanted.sorted() {
            let off = i - idx
            let role = SceneView.role(forOffset: off)
            if let old = lines[i] {
                // la ligne change de rôle (suivante -> courante...) : nouvelle mise en page, fondu enchaîné avec l'ancienne
                guard off >= 0, old.role != role else { continue }
                let l = SceneLine(index: i, role: role, text: all[i].text, font: s.font, weight: s.fontWeight, size: fitSize(for: all[i].text, role: role),
                                  width: layoutWidth(role: role), textColor: textColor, accentColor: accent, glow: s.glow, scale: scale)
                let pres = old.container.presentation()
                l.container.position = pres?.position ?? old.container.position
                l.container.transform = pres?.transform ?? old.container.transform
                l.container.opacity = 0
                lines[i] = l
                linesLayer.addSublayer(l.container)
                starts[i] = (Double(l.container.position.y), Double(l.container.transform.m11), 0)
                ghosts.append(old.container)
                ghostPairs.append((old.container, i))
                continue
            }
            let l = SceneLine(index: i, role: role, text: all[i].text, font: s.font, weight: s.fontWeight, size: fitSize(for: all[i].text, role: role),
                              width: layoutWidth(role: role), textColor: textColor, accentColor: accent, glow: s.glow, scale: scale)
            lines[i] = l
            linesLayer.addSublayer(l.container)
            // arrivée : en bas, transparente
            let t = target(for: l, offset: off)
            l.container.position = CGPoint(x: textCenterX, y: t.y - H * 0.04)
            l.container.opacity = 0
            l.container.transform = CATransform3DMakeScale(t.scale, t.scale, 1)
            starts[i] = (Double(l.container.position.y), t.scale, 0)
        }
        CATransaction.commit()

        let inGap = gapActive
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? 0.9 : (animated ? 0.3 : 0))
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        if !animated { CATransaction.setDisableActions(true) }
        // L'ancienne mise en page (rôle précédent) voyage de conserve avec la nouvelle jusqu'à la même place en s'effaçant : sans cela elle restait
        // sur place (en bas, à la position de « suivante ») et on voyait pendant ~1 s une copie du texte SOUS la nouvelle ligne courante.
        for (g, i) in ghostPairs where !reduceMotion {
            if let nl = lines[i] {
                let gt = target(for: nl, offset: i - idx)
                g.position = CGPoint(x: textCenterX, y: gt.y)
                g.transform = CATransform3DMakeScale(gt.scale, gt.scale, 1)
            }
        }
        for g in ghosts { if reduceMotion { g.isHidden = true } else { g.opacity = 0 } }       // réduire les animations : l'ancienne mise en page disparaît, la nouvelle fond sur place
        var leavers: [SceneLine] = []
        for (i, l) in lines {
            let off = i - idx
            if off == -1, l.role == 0, !l.leaving, animated, !reduceMotion, !cardActive, l.container.opacity > 0.5 { leavers.append(l); continue }
            if off == -1, l.leaving { continue }                    // déjà en train de partir (animations explicites)
            if off != -1, l.leaving { restore(l) }                  // redevenue courante (retour en arrière) : on la remet en place
            var t = target(for: l, offset: off)
            if off == 0 && inGap { t.opacity = 0 }
            l.container.position = CGPoint(x: textCenterX, y: t.y)
            l.container.transform = CATransform3DMakeScale(t.scale, t.scale, 1)
            l.container.opacity = Float(t.opacity)
            // Une couche créée dans cette même transaction n'a encore jamais été validée : Core Animation n'y applique AUCUNE animation implicite
            // (elle serait apparue d'un coup à sa place finale pendant que l'ancienne mise en page s'effaçait en bas). Animation explicite.
            if let st = starts[i], animated {
                glideIn(l.container, from: st, toY: t.y, toScale: t.scale, toOpacity: t.opacity, move: !reduceMotion, duration: reduceMotion ? 0.3 : 0.9)
            }
            l.soft.opacity = Float(t.soft)
            l.base.opacity = Float(t.sharp)
            // couleur d'accent : la courante (remplie ou allumée d'un coup) ; les autres restent blanches
            if off == 0 { l.accent.opacity = reduceMotion || !fillEnabled ? 1 : 1 } else { l.accent.opacity = 0 }
        }
        CATransaction.commit()
        if lastIndex != idx, animated, !reduceMotion, !lines.isEmpty { pauseBreathWhileLinesMove() }
        for l in leavers { leave(l) }
        if !ghosts.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 1.0 : 0)) { for g in ghosts { g.removeFromSuperlayer() } }
        }
        if let cur = lines[idx] {
            currentLineIndex = idx
            currentTextSize = cur.size
            currentTextWidthFraction = textWidth / W
        } else { currentLineIndex = idx < 0 ? -1 : -2 }
        if lastIndex != idx { lastIndex = idx; prepareFill(forceRestart: true) } else { syncFill() }
    }

    /// Arrivée d'une ligne neuve : de son état de départ à sa place (montée + échelle) et d'invisible à visible, par animations explicites.
    /// Avec « Réduire les animations » : seulement le fondu, sur place.
    private func glideIn(_ c: CALayer, from st: (y: Double, scale: Double, opacity: Double), toY: Double, toScale: Double, toOpacity: Double, move: Bool, duration: Double) {
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        func add(_ keyPath: String, _ from: Double, _ to: Double, _ key: String) {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from; a.toValue = to; a.duration = duration; a.timingFunction = timing; a.fillMode = .both
            c.add(a, forKey: key)
        }
        if move {
            add("position.y", st.y, toY, "pf.glide.y")
            add("transform.scale", st.scale, toScale, "pf.glide.scale")
        }
        add("opacity", st.opacity, toOpacity, "pf.glide.opacity")
        glideCount += 1
    }

    // MARK: Sortie de ligne (1.1.0) : la ligne monte doucement, rétrécit un peu (0,92) et s'efface mot à mot (~40 ms de décalage, ~600 ms)

    static let leaveDuration = 0.6
    static let leaveStep = 0.040
    static let leaveScale = 0.92

    private func leave(_ l: SceneLine) {
        l.leaving = true
        leaveCount += 1
        let c = l.container
        let now = c.convertTime(CACurrentMediaTime(), from: nil)
        let startY = Double(c.presentation()?.position.y ?? c.position.y)
        let toY = startY + H * 0.05
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        func explicit(_ layer: CALayer, _ keyPath: String, _ from: Any, _ to: Any, duration: Double, delay: Double = 0, key: String) {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from; a.toValue = to; a.duration = duration; a.timingFunction = timing
            a.beginTime = now + delay; a.fillMode = .both
            layer.add(a, forKey: key)
        }
        let fromAccent = Double(l.accent.presentation()?.opacity ?? l.accent.opacity)
        let fromBase = Double(l.base.presentation()?.opacity ?? l.base.opacity)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        c.position = CGPoint(x: textCenterX, y: toY)
        c.transform = CATransform3DMakeScale(SceneView.leaveScale, SceneView.leaveScale, 1)
        c.opacity = 0
        l.soft.opacity = 0.7; l.base.opacity = 0.25; l.accent.opacity = 0.25
        CATransaction.commit()
        explicit(c, "position.y", startY, toY, duration: SceneView.leaveDuration, key: "pf.exit.rise")
        explicit(c, "transform.scale", 1.0, SceneView.leaveScale, duration: SceneView.leaveDuration, key: "pf.exit.scale")
        explicit(c, "opacity", 1.0, 0.0, duration: SceneView.leaveDuration * 0.5, delay: SceneView.leaveDuration * 0.5, key: "pf.exit.fade")
        explicit(l.soft, "opacity", 0.0, 0.7, duration: SceneView.leaveDuration, key: "pf.exit.blur")
        // net -> doux en douceur (sans saut de luminosité à l'instant du changement de ligne)
        explicit(l.accent, "opacity", fromAccent, 0.25, duration: SceneView.leaveDuration, key: "pf.exit.accent")
        explicit(l.base, "opacity", fromBase, 0.25, duration: SceneView.leaveDuration, key: "pf.exit.base")
        // mot à mot : un masque dont chaque rectangle de mot s'éteint à son tour (le flou est le fondu enchaîné net -> doux de toute la ligne)
        let rects = TextFragments.wordRects(text: l.text, style: l.style, bitmapHeight: c.bounds.height)
        let n = rects.count
        let step = n > 1 ? min(SceneView.leaveStep, 0.32 / Double(n - 1)) : 0
        let wordDur = max(0.3, SceneView.leaveDuration - Double(max(0, n - 1)) * step)
        let mask = CALayer(); mask.frame = c.bounds
        var wordKeys = 0
        for (k, r) in rects.enumerated() {
            let w = CALayer(); w.frame = r; w.backgroundColor = NSColor.black.cgColor
            CATransaction.begin(); CATransaction.setDisableActions(true); w.opacity = 0; CATransaction.commit()
            mask.addSublayer(w)
            explicit(w, "opacity", 1.0, 0.0, duration: wordDur, delay: Double(k) * step, key: "pf.exit.word")
            wordKeys += 1
        }
        if n > 0 { c.mask = mask }
        lastLeave = LeaveRecord(words: n, stepMs: step * 1000, wordMs: wordDur * 1000, totalMs: (Double(max(0, n - 1)) * step + wordDur) * 1000,
                                containerKeys: (c.animationKeys() ?? []).filter { $0.hasPrefix("pf.exit.") }.sorted(), wordKeys: wordKeys)
    }

    /// Remet une ligne qui partait (retour en arrière dans le titre) dans l'état d'une ligne normale.
    private func restore(_ l: SceneLine) {
        l.leaving = false
        l.container.mask = nil
        for k in ["pf.exit.rise", "pf.exit.scale", "pf.exit.fade"] { l.container.removeAnimation(forKey: k) }
        l.soft.removeAnimation(forKey: "pf.exit.blur")
        l.accent.removeAnimation(forKey: "pf.exit.accent"); l.base.removeAnimation(forKey: "pf.exit.base")
    }

    private struct Target { var y: Double; var scale: Double; var opacity: Double; var sharp: Double; var soft: Double }

    private func target(for l: SceneLine, offset: Int) -> Target {
        let idx = model.currentIndex
        let all = model.syncedLines
        func h(_ i: Int) -> Double { (lines[i]?.height ?? 0) }
        let yCur = H * 0.56
        let hCur = idx >= 0 ? h(idx) : H * 0.1
        switch offset {
        case 0: return Target(y: yCur, scale: 1, opacity: 1, sharp: fillEnabled ? 0.78 : 0, soft: 0)
        case 1:
            let sc = 0.5
            let y = yCur - hCur / 2 - H * 0.05 - h(l.index) * sc / 2
            return Target(y: y, scale: sc, opacity: 0.76, sharp: 1, soft: 0)
        case 2:
            let sc = 0.42
            let h1 = h(idx + 1) * 0.5
            let y = yCur - hCur / 2 - H * 0.05 - h1 - H * 0.035 - h(l.index) * sc / 2
            return Target(y: y, scale: sc, opacity: 0.72, sharp: 1, soft: 0)
        case -1: return Target(y: yCur + hCur / 2 + H * 0.13, scale: 0.82, opacity: 0, sharp: 0.2, soft: 0.7)
        default: _ = all; return Target(y: yCur - H * 0.4, scale: 0.4, opacity: 0, sharp: 1, soft: 0)
        }
    }

    private var fillEnabled: Bool { settings.karaokeFill && !reduceMotion }

    /// Remplissage progressif de la ligne courante (S5), de gauche à droite sur sa durée estimée.
    private func prepareFill(forceRestart: Bool) {
        for l in lines.values where l.index != model.currentIndex && l.fill != nil {
            l.fill = nil; l.accent.mask = nil
            l.accent.look = l.style; l.accent.setNeedsDisplay()
        }
        guard let cur = lines[model.currentIndex], fillEnabled, model.currentIndex >= 0 else { return }
        let times = lineTimes
        let d = SceneMath.fillDuration(lines: times, index: model.currentIndex)
        let pos = model.lyricPosition()
        let f0 = SceneMath.fillFraction(position: pos, start: times[model.currentIndex].time, duration: d)
        if cur.fill == nil {
            let rects = TextFragments.lineRects(text: cur.text, style: cur.style, bitmapHeight: cur.container.bounds.height)
            let mask = FillMask(rects: rects)
            mask.layer.frame = cur.container.bounds
            cur.accent.mask = mask.layer
            // le masque coupe net une lueur : pendant le remplissage la lettre est nette, sans lueur
            cur.accent.look = cur.style.withoutEffects; cur.accent.setNeedsDisplay()
            cur.fill = mask
        }
        let playing = model.isPlayingNow && !gapActive
        cur.fill?.set(fraction: f0, duration: d, playing: playing, animated: true)
        lastFillDuration = d
        if forceRestart { fillStarts += 1 }
    }

    private func syncFill() {
        guard let cur = lines[model.currentIndex], let mask = cur.fill else { return }
        let times = lineTimes
        guard model.currentIndex >= 0, model.currentIndex < times.count else { return }
        let d = SceneMath.fillDuration(lines: times, index: model.currentIndex)
        let f0 = SceneMath.fillFraction(position: model.lyricPosition(), start: times[model.currentIndex].time, duration: d)
        let playing = model.isPlayingNow && !gapActive
        if mask.playing != playing || abs(mask.expectedFraction() - f0) > 0.18 { prepareFill(forceRestart: false) }
    }
    var currentFill: FillMask? { lines[model.currentIndex]?.fill }

    // MARK: Passages sans paroles (S6)

    private func desiredGap() -> Bool {
        guard !cardActive || true else { return false }
        switch model.mode {
        case .synced:
            let times = lineTimes
            let key = "\(model.trackEpoch)|\(times.count)|\(model.track?.duration ?? 0)"
            if key != gapsKey {
                gapsKey = key
                gaps = SceneMath.gaps(lines: times, placeholder: SyncEngine.placeholder, duration: model.track?.duration)
            }
            guard model.isPlayingNow || model.isPaused else { return false }
            let pos = model.lyricPosition()
            guard let g = SceneMath.gap(at: pos, in: gaps) else { return false }
            return pos < g.fadeOutAt
        case .searching, .offline, .busy: return false
        default: return true                     // instrumental, non synchronisé, rien en lecture… : animation calme
        }
    }

    private func setGap(_ on: Bool, immediate: Bool) {
        guard on != gapActive || immediate else { return }
        gapActive = on
        if on { gapStarts += 1 } else { gapStops += 1 }
        let d = immediate || reduceMotion ? 0.05 : 1.0
        CATransaction.begin()
        CATransaction.setAnimationDuration(d)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        if !on {
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.gapActive else { return }
                    self.emitter.birthRate = 0
                    self.note.removeAnimation(forKey: "pf.breath")
                    self.gapAnimating = false
                }
            }
        }
        gapLayer.opacity = on ? 1 : 0
        CATransaction.commit()
        if on {
            emitter.birthRate = reduceMotion ? 0 : 1
            if !reduceMotion && note.animation(forKey: "pf.breath") == nil {
                let a = CABasicAnimation(keyPath: "transform.scale")
                a.fromValue = 0.92; a.toValue = 1.08
                let o = CABasicAnimation(keyPath: "opacity")
                o.fromValue = 0.55; o.toValue = 0.95
                let g = CAAnimationGroup()
                g.animations = [a, o]; g.duration = 3.6; g.autoreverses = true; g.repeatCount = .infinity
                g.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                note.add(g, forKey: "pf.breath")
            }
            let noteColor = model.accentColor(settings)
            note.foregroundColor = NSColor(srgbRed: noteColor.r, green: noteColor.g, blue: noteColor.b, alpha: 1).cgColor
            if let sec = model.palette?.secondary, let c = emitter.emitterCells?.first {
                c.color = NSColor(srgbRed: sec.r, green: sec.g, blue: sec.b, alpha: 0.55).cgColor
            }
            gapAnimating = true
        } else if immediate || reduceMotion {
            emitter.birthRate = 0; note.removeAnimation(forKey: "pf.breath"); gapAnimating = false
        }
    }
    var particleBudget: Double { Double((emitter.emitterCells?.first?.birthRate ?? 0)) * Double(emitter.emitterCells?.first?.lifetime ?? 0) }

    // MARK: Bloc d'information (états sans lignes)

    private func layoutInfo(_ s: Settings) {
        let ts = max(30, H * 0.06), ss = max(16, H * 0.03)
        infoTitle.fontSize = ts; infoSub.fontSize = ss
        infoTitle.font = FontResolver.resolve(s.font, size: ts, weight: s.fontWeight).nsFont
        infoSub.font = FontResolver.resolve(s.font, size: ss, weight: .regular).nsFont
        infoTitle.contentsScale = scale; infoSub.contentsScale = scale
        infoTitle.foregroundColor = NSColor.white.cgColor
        infoSub.foregroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        infoTitle.frame = CGRect(x: textCenterX - textWidth / 2, y: H * 0.40, width: textWidth, height: ts * 2.4)
        infoSub.frame = CGRect(x: textCenterX - textWidth / 2, y: H * 0.30, width: textWidth, height: ss * 2.6)
    }

    private func updateInfo() {
        let text = model.display.stateText
        let status: String
        switch model.mode {
        case .unsynced: status = "Paroles non synchronisées"
        case .instrumental: status = "Morceau instrumental"
        case .unavailable: status = "Paroles indisponibles"
        case .busy: status = "Service de paroles occupé"
        case .offline: status = "Hors connexion"
        case .nothing: status = text?.body ?? ""
        default: status = text?.title ?? ""
        }
        if let t = model.track {
            infoTitle.string = t.title
            infoSub.string = [t.artist, status].filter { !$0.isEmpty }.joined(separator: " · ")
        } else {
            infoTitle.string = text?.title ?? AppIdentity.displayName
            infoSub.string = text?.body ?? ""
        }
        layoutInfo(settings)
    }

    // MARK: Carte du titre (S14, S19)

    private func scheduleCard() {
        guard !withArtwork else { return }          // la pochette et le titre restent affichés à gauche : pas de carte en plus
        cardPending = true
        cardTask?.cancel()
        cardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))        // la pochette peut mettre un instant à arriver
            guard !Task.isCancelled else { return }
            if self?.cardPending == true { self?.startCard("delai") }
        }
    }
    private func cancelCard() { cardPending = false; cardTask?.cancel(); cardTask = nil }

    /// Entrée dans la Scène avec un titre en cours : la carte s'affiche aussi.
    func showCardNow() { if model.track != nil && !withArtwork { startCard("entree") } }

    private func startCard(_ why: String = "") {
        guard let track = model.track else { return }
        model.diag?(["event": "scene-card", "why": why, "epoch": model.trackEpoch, "pending": cardPending])
        cardPending = false
        cardTask?.cancel()
        cardActive = true; cardShownCount += 1; cardTitle = track.title
        buildCard(track: track)
        let rm = reduceMotion
        let inD = rm ? 0.3 : 0.9, hold = 1.5, outD = rm ? 0.3 : 0.9
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.opacity = 0
        card.transform = rm ? CATransform3DIdentity : CATransform3DMakeScale(0.94, 0.94, 1)
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(inD)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        card.opacity = 1
        card.transform = CATransform3DIdentity
        content.opacity = 0
        CATransaction.commit()
        cardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(inD + hold))
            guard !Task.isCancelled, let self else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(outD)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            self.card.opacity = 0
            if !rm { self.card.transform = CATransform3DMakeScale(1.03, 1.03, 1) }
            self.content.opacity = 1
            CATransaction.commit()
            try? await Task.sleep(for: .seconds(outD))
            guard !Task.isCancelled else { return }
            self.cardActive = false
            self.lastIndex = Int.min
            self.refresh(animated: false)
        }
    }

    private func buildCard(track: TrackInfo) {
        card.sublayers?.forEach { $0.removeFromSuperlayer() }
        let side = min(H * 0.40, W * 0.30)
        let artRect = CGRect(x: W / 2 - side / 2, y: H * 0.50, width: side, height: side)
        let art = CALayer()
        art.frame = artRect
        art.cornerRadius = side * 0.04
        art.masksToBounds = true
        art.borderWidth = 1; art.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        if let image = model.artworkImage {
            art.contents = image; art.contentsGravity = .resizeAspectFill
            card.addSublayer(art)
            // S19 : reflet sous la pochette, fondu doux, faible opacité (dans la carte seulement)
            let refl = CALayer()
            let rh = side * 0.28
            refl.frame = CGRect(x: artRect.minX, y: artRect.minY - rh - 2, width: side, height: rh)
            refl.contents = image; refl.contentsGravity = .resizeAspectFill
            refl.contentsRect = CGRect(x: 0, y: 0.72, width: 1, height: 0.28)       // bas de l'image
            refl.transform = CATransform3DMakeScale(1, -1, 1)
            refl.opacity = 0.26
            let mask = CAGradientLayer()
            mask.frame = refl.bounds
            mask.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
            mask.startPoint = CGPoint(x: 0.5, y: 0); mask.endPoint = CGPoint(x: 0.5, y: 1)
            refl.mask = mask
            refl.name = "reflection"
            card.addSublayer(refl)
        } else {
            art.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            card.addSublayer(art)
            let n = CATextLayer()
            n.string = "♪"; n.fontSize = side * 0.42; n.alignmentMode = .center; n.contentsScale = scale
            n.foregroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
            n.frame = CGRect(x: artRect.minX, y: artRect.midY - side * 0.30, width: side, height: side * 0.6)
            card.addSublayer(n)
        }
        let s = settings
        let ts = max(30, H * 0.058), ss = max(18, H * 0.031)
        func label(_ text: String, size: Double, weight: LyricWeight, alpha: Double, y: Double, lines: Double) -> CATextLayer {
            let t = CATextLayer()
            t.string = text; t.fontSize = size; t.alignmentMode = .center; t.truncationMode = .end; t.isWrapped = true
            t.font = FontResolver.resolve(s.font, size: size, weight: weight).nsFont
            t.foregroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
            t.contentsScale = scale
            t.frame = CGRect(x: W * 0.2, y: y, width: W * 0.6, height: size * 1.3 * lines)
            return t
        }
        card.addSublayer(label(track.title, size: ts, weight: .bold, alpha: 1, y: H * 0.50 - side * 0.30 - ts * 2.0, lines: 1))
        card.addSublayer(label(track.artist, size: ss, weight: .regular, alpha: 0.82, y: H * 0.50 - side * 0.30 - ts * 2.0 - ss * 1.6, lines: 1))
    }
    var reflectionPresent: Bool { card.sublayers?.contains { $0.name == "reflection" } ?? false }

    // MARK: Animations en pause (fenêtre masquée, écran en veille)

    func setAnimationsPaused(_ paused: Bool) {
        guard paused != animationsPaused else { return }
        animationsPaused = paused
        let l = stage
        if paused {
            let t = l.convertTime(CACurrentMediaTime(), from: nil)
            l.speed = 0; l.timeOffset = t
            tickTimer?.invalidate(); tickTimer = nil
        } else {
            let pausedTime = l.timeOffset
            l.speed = 1; l.timeOffset = 0; l.beginTime = 0
            l.beginTime = l.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(t, forMode: .common)
            tickTimer = t
            prepareFill(forceRestart: false)
        }
    }

    // MARK: Autotest

    var artOpacityNow: Double { Double(artLayer?.opacity ?? 0) }
    var accentOpacity: Double { Double(lines[model.currentIndex]?.accent.opacity ?? -1) }
    var layerSummary: String { "lignes=\(lines.count) artLayer=\(artLayer != nil) drift=\(driftActive)" }
    var lineCount: Int { lines.count }
    var shimmerActive: Bool { shimmer?.isShimmering ?? false }
    var shimmerPresent: Bool { shimmer != nil }
    var vignetteVisible: Bool { vignette.opacity > 0.5 }
    var grainVisible: Bool { grain.opacity > 0.5 }
    var viewWidth: Double { W }
    var barOpacityNow: Double { Double(bar.layer.presentation()?.opacity ?? bar.layer.opacity) }
    var exitAnimationKeys: [String] { (lines[model.currentIndex - 1]?.container.animationKeys() ?? []).sorted() }
    var contentOpacity: Double { Double(content.presentation()?.opacity ?? content.opacity) }
    var gradientHex: String {
        guard let c = gradient.colors?.first, let col = NSColor(cgColor: c as! CGColor)?.usingColorSpace(.sRGB) else { return "" }
        return RGB(Double(col.redComponent), Double(col.greenComponent), Double(col.blueComponent)).hex
    }
}

/// Élément d'accessibilité du contrôle de sortie (la Scène est faite de couches : aucune vue de bouton).
final class ExitAccessibilityElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}
