import AppKit
import QuartzCore
import AppSupport

/// Une ligne à afficher dans la pile. `key` identifie la ligne d'un état à l'autre : la même ligne de paroles garde
/// SA couche quand elle monte d'un cran (la couche glisse, change d'échelle et d'opacité ; elle n'est ni redessinée ni recréée).
struct LineItem: Equatable {
    var key: String
    /// Rang absolu dans les paroles (sert au sens du défilement : nouvelles lignes par le bas ou par le haut).
    var order: Int
    /// Écart à la ligne courante : 0 = courante, ±1, ±2 = voisines.
    var offset: Int
    var text: String
    /// Texte secondaire (« Recherche des paroles… ») : blanc à 62 %.
    var dim: Bool = false
}

struct LineStackStyle: Equatable {
    var font: LyricFont
    var weight: LyricWeight
    /// Taille de la ligne courante ; TOUTES les lignes sont dessinées à cette taille puis mises à l'échelle (`LineLook`).
    var size: Double
    var ratio: Double
    var color: RGB
    var glow: Bool
    var clearShadow: Bool
    /// Largeur de retour à la ligne (fenêtre moins marges).
    var width: Double = LyricsMetrics.textWidth
}

enum LineMotion: String {
    /// Défilement doux : les lignes montent (ou descendent), échelle / opacité / flou animés par Core Animation.
    case glide
    /// Fondu simple (Réduire les animations, changement de titre) : `CATransition`.
    case fade
    /// Aucun mouvement (premier affichage, fenêtre cachée).
    case none
}

/// Bitmap d'un texte, une seule fois par changement de contenu ou de style (`draw(in:)` n'est PAS rappelée pendant une animation :
/// les animations de transformation et d'opacité sont exécutées par le serveur de rendu, sans image dessinée par l'app).
/// `soft` = même texte flouté (ombre du texte seule) : le « léger flou » des voisines est un fondu enchaîné net/flou, sans filtre
/// Core Image (donc visible aussi dans les captures `--snapshot` et sans coût de filtre à chaque image).
final class TextBitmapLayer: CALayer {
    static let padding = 22.0
    var text = ""
    var look: LineStackStyle?
    var soft = false
    var softRadius = 1.6
    var tint: NSColor = .white

    #if DEBUG
    nonisolated(unsafe) static var drawSeconds = [0.0, 0.0]      // [net, flou] : temps cumulé passé dans draw(in:)
    nonisolated(unsafe) static var drawCounts = [0, 0]
    #endif

    override func draw(in ctx: CGContext) {
        guard let style = look, !text.isEmpty else { return }
        #if DEBUG
        let started = ContinuousClock.now
        defer {
            let d = ContinuousClock.now - started
            let i = soft ? 1 : 0
            Self.drawSeconds[i] += Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            Self.drawCounts[i] += 1
        }
        #endif
        let pad = Self.padding
        let scale = max(contentsScale, 1)
        let attrs = FontResolver.attributes(font: style.font, weight: style.weight, size: style.size, color: tint)
        let string = NSAttributedString(string: text, attributes: attrs)
        let rect = CGRect(x: pad, y: pad, width: bounds.width - 2 * pad, height: bounds.height - 2 * pad)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        defer { NSGraphicsContext.restoreGraphicsState() }
        func paint() { string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading]) }
        if soft {
            // Texte hors de la zone, son ombre (floue) tombe dedans : on ne garde que la silhouette floutée.
            let far = 4000.0
            ctx.saveGState()
            ctx.translateBy(x: -far, y: 0)
            ctx.setShadow(offset: CGSize(width: far * scale, height: 0), blur: softRadius * 2 * scale, color: tint.cgColor)
            paint()
            ctx.restoreGState()
            return
        }
        if style.clearShadow {
            // Style Transparent : deux ombres comme avant (0 / 2 pt rayon 7 à 65 %, rayon 1 à 55 %).
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 7 * scale, color: NSColor.black.withAlphaComponent(0.65).cgColor)
            paint()
            ctx.setShadow(offset: .zero, blur: 1 * scale, color: NSColor.black.withAlphaComponent(0.55).cgColor)
            paint()
            ctx.restoreGState()
        }
        if style.glow {
            // Thème Néon : halo de la couleur du texte.
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 16 * scale, color: tint.withAlphaComponent(0.85).cgColor)
            paint()
            ctx.setShadow(offset: .zero, blur: 5 * scale, color: tint.withAlphaComponent(0.9).cgColor)
            paint()
            ctx.restoreGState()
        }
        paint()
    }
}

/// Une ligne = une couche de transformation (position, échelle, opacité) portant deux bitmaps (net et flou).
final class LineLayer: CALayer {
    let sharp = TextBitmapLayer()
    let softLayer = TextBitmapLayer()
    var item: LineItem
    /// Hauteur du texte à la taille de la courante (sans marge) et largeur de retour à la ligne.
    var textHeight: Double = 0
    var textSize: Double = 0
    var contentSignature = ""
    var onScreenTarget = LineLayerTarget(y: 0, scale: 1, opacity: 1, sharpWeight: 1, softWeight: 0)

    init(item: LineItem) {
        self.item = item
        super.init()
        sharp.soft = false
        softLayer.soft = true
        addSublayer(softLayer)
        addSublayer(sharp)
        isGeometryFlipped = false
    }
    override init(layer: Any) {
        let other = layer as? LineLayer
        item = other?.item ?? LineItem(key: "", order: 0, offset: 0, text: "")
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }
}

struct LineLayerTarget: Equatable {
    var y: Double
    var scale: Double
    var opacity: Double
    var sharpWeight: Double
    var softWeight: Double
}

/// Pile de lignes : défilement doux façon Apple Music, tout en couches Core Animation.
/// Aucune image n'est redessinée par l'app pendant l'animation : seules la création d'une ligne et un changement de style
/// déclenchent `draw(in:)`. Mesure de CPU : voir le journal.
@MainActor
final class LineStackView: NSView {
    static let glideDuration = 0.6
    static let fadeDuration = 0.3
    static let travel = 36.0
    static let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)

    private let container = CALayer()
    private var layers: [String: LineLayer] = [:]
    private var leaving: [LineLayer] = []
    private var items: [LineItem] = []
    private var style: LineStackStyle?
    private var epoch = -1
    private var accessibilityLines: [NSAccessibilityElement] = []
    private(set) var contentHeight = 0.0

    /// Dernier mouvement appliqué et animations posées (autotest : preuve que ce sont des animations de couches).
    private(set) var lastMotion: LineMotion = .none
    private(set) var lastAnimationKeys: [String] = []
    private(set) var lastAnimationDurations: [Double] = []
    private(set) var lastTransitionDuration: Double?
    private(set) var trackFades = 0
    private(set) var glides = 0
    private(set) var fades = 0
    private(set) var bitmapDraws = 0
    var onLayout: ((Double) -> Void)?
    #if DEBUG
    nonisolated(unsafe) static var snapshotMode = false
    #endif

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()           // d'abord la couche, puis wantsLayer : vue « hébergeant » sa couche (AppKit n'y touche plus)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(container)
        container.bounds = .zero
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        for l in layers.values { l.sharp.contentsScale = s; l.softLayer.contentsScale = s; l.contentsScale = s; redraw(l) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let s = window?.backingScaleFactor ?? 2
        for l in layers.values where l.sharp.contentsScale != s { l.sharp.contentsScale = s; l.softLayer.contentsScale = s; redraw(l) }
    }

    #if DEBUG
    /// Captures `--snapshot` : `cacheDisplay` ne passe pas par les couches ajoutées à la main ; on les rend à la demande.
    override func draw(_ dirtyRect: NSRect) {
        guard Self.snapshotMode, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        container.render(in: ctx)
        ctx.restoreGState()
    }
    #endif

    // MARK: Mise en page

    /// Hauteur de texte à la taille de la courante, largeur `textWidth`.
    private func measure(_ text: String, style: LineStackStyle) -> Double {
        FontResolver.measureHeight(text.isEmpty ? " " : text, size: style.size, width: style.width, font: style.font, weight: style.weight)
    }

    private func target(for item: LineItem, height: Double, style: LineStackStyle) -> LineLayerTarget {
        let scale = LineLook.scale(offset: item.offset, ratio: style.ratio)
        let base = LineLook.opacity(offset: item.offset) * (item.dim ? 0.62 : 1)
        let blur = min(1, LineLook.blur(offset: item.offset) / 1.6)       // 0 = net, 1 = flou maximal
        // Fondu enchaîné net / flou : la somme des deux poids reste proche de 1 (pas de ligne qui s'éteint en route).
        return LineLayerTarget(y: 0, scale: scale, opacity: base, sharpWeight: 1 - 0.6 * blur, softWeight: 0.75 * blur)
    }

    private func redraw(_ l: LineLayer) {
        guard let style else { return }
        bitmapDraws += 1
        let color: NSColor = l.item.dim ? NSColor.white : NSColor(srgbRed: style.color.r, green: style.color.g, blue: style.color.b, alpha: 1)
        let pad = TextBitmapLayer.padding
        let bounds = CGRect(x: 0, y: 0, width: style.width + 2 * pad, height: l.textHeight + 2 * pad)
        let scale = window?.backingScaleFactor ?? 2
        for (bitmap, soft) in [(l.sharp, false), (l.softLayer, true)] {
            bitmap.contentsScale = scale
            bitmap.bounds = bounds
            bitmap.position = CGPoint(x: bounds.midX, y: bounds.midY)
            bitmap.text = l.item.text
            bitmap.look = style
            bitmap.tint = color
            bitmap.softRadius = max(LineLook.blur(offset: 2), 1.2) * (style.size / 26)
            bitmap.soft = soft
            bitmap.setNeedsDisplay()
        }
        l.contentsScale = scale
        l.bounds = bounds
    }

    private func presentationValues(of l: LineLayer) -> LineLayerTarget {
        let p = l.presentation() ?? l
        return LineLayerTarget(y: Double(p.position.y), scale: (p.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1,
                               opacity: Double(p.opacity),
                               sharpWeight: Double((l.sharp.presentation() ?? l.sharp).opacity),
                               softWeight: Double((l.softLayer.presentation() ?? l.softLayer).opacity))
    }

    // MARK: Application

    /// Applique une nouvelle liste de lignes. `epoch` change à chaque nouveau titre (la pile est alors remplacée par un fondu).
    func apply(items newItems: [LineItem], style newStyle: LineStackStyle, epoch newEpoch: Int, motion requested: LineMotion) {
        let styleChanged = style != newStyle
        if !styleChanged && items == newItems && epoch == newEpoch { return }
        let newTrack = newEpoch != epoch && epoch != -1
        style = newStyle
        let oldItems = items
        items = newItems
        epoch = newEpoch
        var motion = requested
        if newTrack && motion == .glide { motion = .fade; trackFades += 1 }
        if window?.isVisible != true { motion = .none }

        // 1. Valeurs de départ des couches qui existent déjà (avant tout changement de modèle).
        var from: [String: LineLayerTarget] = [:]
        if motion == .glide { for (k, l) in layers { from[k] = presentationValues(of: l) } }

        // 2. Couches : créées, mises à jour ou retirées.
        let incomingKeys = Set(newItems.map(\.key))
        var removed: [LineLayer] = []
        for (k, l) in layers where !incomingKeys.contains(k) { removed.append(l) }
        for l in removed { layers[l.item.key] = nil }
        var created = Set<String>()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for item in newItems {
            let height = measure(item.text, style: newStyle)
            if let l = layers[item.key] {
                let signature = "\(item.text)|\(item.dim)"
                let needsBitmap = styleChanged || l.contentSignature != signature || abs(l.textHeight - height) > 0.5
                l.item = item
                l.textHeight = height
                if needsBitmap { l.contentSignature = signature; redraw(l) }
            } else {
                let l = LineLayer(item: item)
                l.textHeight = height
                l.contentSignature = "\(item.text)|\(item.dim)"
                l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layers[item.key] = l
                container.addSublayer(l)
                redraw(l)
                created.insert(item.key)
            }
        }

        // 3. Cibles : positions centrées sur le milieu de la pile.
        var targets: [String: LineLayerTarget] = [:]
        let displayed = newItems.map { measure($0.text, style: newStyle) * LineLook.scale(offset: $0.offset, ratio: newStyle.ratio) }
        let total = displayed.reduce(0, +) + LyricsMetrics.lineGap * Double(max(newItems.count - 1, 0))
        contentHeight = total
        var top = total / 2
        for (i, item) in newItems.enumerated() {
            var t = target(for: item, height: displayed[i], style: newStyle)
            t.y = top - displayed[i] / 2
            top -= displayed[i] + LyricsMetrics.lineGap
            targets[item.key] = t
        }

        // 4. Sens du défilement : les nouvelles lignes arrivent par le bas si elles suivent les lignes conservées.
        let kept = newItems.filter { !created.contains($0.key) }.map(\.order)
        let enteringBelow = (newItems.filter { created.contains($0.key) }.map(\.order).max() ?? 0) >= (kept.max() ?? Int.min)
        let direction: Double = enteringBelow ? 1 : -1     // +1 : le contenu monte

        // 5. Valeurs du modèle = valeurs d'arrivée.
        for item in newItems {
            guard let l = layers[item.key], let t = targets[item.key] else { continue }
            l.position = CGPoint(x: 0, y: t.y)
            l.transform = CATransform3DMakeScale(t.scale, t.scale, 1)
            l.opacity = Float(t.opacity)
            l.sharp.opacity = Float(t.sharpWeight)
            l.softLayer.opacity = Float(t.softWeight)
            l.onScreenTarget = t
        }
        CATransaction.commit()

        // 6. Mouvement.
        lastMotion = motion
        lastAnimationKeys = []
        lastAnimationDurations = []
        lastTransitionDuration = nil
        for l in removed { l.removeAllAnimations() }
        switch motion {
        case .none:
            for l in removed { l.removeFromSuperlayer() }
        case .fade:
            for l in removed { l.removeFromSuperlayer() }
            let t = CATransition()
            t.type = .fade
            t.duration = Self.fadeDuration
            t.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(t, forKey: "pf.fade")
            lastAnimationKeys = ["pf.fade(CATransition)"]
            lastAnimationDurations = [Self.fadeDuration]
            lastTransitionDuration = Self.fadeDuration
            fades += 1
        case .glide:
            glides += 1
            CATransaction.begin()
            for item in newItems {
                guard let l = layers[item.key], let to = targets[item.key] else { continue }
                var start = from[item.key]
                if start == nil {
                    // Ligne qui entre : par le bas (ou le haut), invisible, déjà à son échelle.
                    start = LineLayerTarget(y: to.y - direction * Self.travel, scale: to.scale, opacity: 0, sharpWeight: to.sharpWeight, softWeight: to.softWeight)
                }
                addAnimations(to: l, from: start!, to: to, delay: 0)
            }
            // Lignes qui sortent : continuent dans le sens du défilement en s'éteignant, puis disparaissent.
            for l in removed {
                let cur = presentationOrModel(l)
                var out = cur
                out.y = cur.y + direction * Self.travel
                out.opacity = 0
                leaving.append(l)
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.position = CGPoint(x: 0, y: out.y); l.opacity = 0
                CATransaction.commit()
                addAnimations(to: l, from: cur, to: out, delay: 0)
            }
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for l in self.leaving where l.animation(forKey: "pf.opacity") == nil { l.removeFromSuperlayer() }
                    self.leaving.removeAll { $0.superlayer == nil }
                }
            }
            CATransaction.commit()
        }
        rebuildAccessibility()
        onLayout?(contentHeight)
    }

    private func presentationOrModel(_ l: LineLayer) -> LineLayerTarget { presentationValues(of: l) }

    private func addAnimations(to l: LineLayer, from: LineLayerTarget, to: LineLayerTarget, delay: Double) {
        func basic(_ keyPath: String, _ f: Double, _ t: Double) -> CABasicAnimation? {
            guard abs(f - t) > 0.0005 else { return nil }
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = f; a.toValue = t
            a.duration = Self.glideDuration
            a.timingFunction = Self.timing
            a.fillMode = .backwards
            return a
        }
        func add(_ layer: CALayer, _ name: String, _ a: CABasicAnimation?) {
            guard let a else { return }
            layer.add(a, forKey: name)
            lastAnimationKeys.append("\(layer === l ? "ligne" : (layer === l.sharp ? "net" : "flou")).\(name)(\(a.keyPath ?? ""))")
            lastAnimationDurations.append(a.duration)
        }
        add(l, "pf.y", basic("position.y", from.y, to.y))
        add(l, "pf.scale", basic("transform.scale", from.scale, to.scale))
        add(l, "pf.opacity", basic("opacity", from.opacity, to.opacity))
        add(l.sharp, "pf.sharp", basic("opacity", from.sharpWeight, to.sharpWeight))
        add(l.softLayer, "pf.soft", basic("opacity", from.softWeight, to.softWeight))
    }

    // MARK: Autotest

    /// Valeurs de la couche de la ligne courante à l'écran (présentation) : position, échelle, opacité.
    func currentLinePresentation() -> (y: Double, scale: Double, opacity: Double)? {
        guard let key = items.first(where: { $0.offset == 0 })?.key, let l = layers[key] else { return nil }
        let v = presentationValues(of: l)
        return (v.y, v.scale, v.opacity)
    }
    var layerCount: Int { layers.count }
    var animatedLayerCount: Int { layers.values.filter { $0.animationKeys()?.isEmpty == false }.count }
    var currentLineKeys: [String] { items.map(\.key) }
    func layerSnapshot() -> [(key: String, offset: Int, y: Double, scale: Double, opacity: Double, animations: [String])] {
        items.compactMap { item in
            guard let l = layers[item.key] else { return nil }
            let m = l.onScreenTarget
            return (item.key, item.offset, m.y, m.scale, m.opacity, l.animationKeys() ?? [])
        }
    }

    // MARK: Accessibilité (VoiceOver)

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Paroles" }
    override func accessibilityChildren() -> [Any]? { accessibilityLines }

    private func rebuildAccessibility() {
        let n = items.count
        let mid = n / 2
        var elements: [NSAccessibilityElement] = []
        for (i, item) in items.enumerated() {
            let e = NSAccessibilityElement()
            let offset = i - mid
            e.setAccessibilityRole(.staticText)
            e.setAccessibilityLabel(Self.accessibilityName(offset: offset))
            e.setAccessibilityValue(item.text)
            e.setAccessibilityParent(self)
            e.setAccessibilityEnabled(!item.text.isEmpty)
            e.setAccessibilityHidden(item.text.isEmpty)
            e.setAccessibilityFrameInParentSpace(NSRect(x: 0, y: bounds.midY - 10 + Double(offset) * -20, width: bounds.width, height: 18))
            elements.append(e)
        }
        accessibilityLines = elements
    }

    static func accessibilityName(offset: Int) -> String {
        switch offset {
        case 0: return "Ligne courante"
        case -1: return "Ligne précédente"
        case 1: return "Ligne suivante"
        case ..<(-1): return "Ligne précédente, \(-offset)"
        default: return "Ligne suivante, \(offset)"
        }
    }
}
