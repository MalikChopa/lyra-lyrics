import AppKit
import SwiftUI
import QuartzCore
import AppSupport

/// Bloc « non synchronisées » (D1, 1.1.0) : le texte est dessiné UNE fois dans une couche ; le défilement est UNE animation linéaire de
/// `position.y` exécutée par le serveur de rendu, de la position courante à la fin du texte. Plus aucune mise à jour SwiftUI par image
/// (avant : minuteur 10 Hz + `offset` animé, environ 2 % de processeur). Le point de départ est recalé seulement à la lecture, à la pause,
/// au saut et au changement de titre (`AppModel.refreshUnsyncedScroll`).
@MainActor
final class UnsyncedScrollLayerView: NSView {
    static let viewport = 100.0
    private let clip = CALayer()
    private let content = TextBitmapLayer()
    private var contentHeight = 0.0
    private var signature = ""
    private var lastStamp = -1
    private(set) var animationCount = 0
    private(set) var isAnimating = false
    private(set) var lastDuration = 0.0
    private(set) var travel = 0.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = true
        clip.masksToBounds = false
        layer?.addSublayer(clip)
        clip.addSublayer(content)
        content.anchorPoint = CGPoint(x: 0.5, y: 1)
        let mask = CAGradientLayer()
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, 0.12, 0.88, 1]
        mask.startPoint = CGPoint(x: 0.5, y: 1); mask.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.mask = mask
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.mask?.frame = bounds
    }

    /// Vrai si la position de départ visible est `progress` (autotest).
    var presentationY: Double { Double((content.presentation() ?? content).position.y) }

    func apply(text: String, style: LineStackStyle, scroll: AppModel.UnsyncedScroll, animated: Bool) {
        let sig = "\(text.hashValue)|\(style.font.rawValue)|\(style.weight.rawValue)|\(style.size)|\(style.color.hex)|\(style.width)|\(style.glow)|\(style.clearShadow)"
        let pad = TextBitmapLayer.padding
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if sig != signature {
            signature = sig
            let h = FontResolver.measureHeight(text, size: style.size, width: style.width, font: style.font, weight: style.weight)
            contentHeight = h
            content.contentsScale = scale
            content.bounds = CGRect(x: 0, y: 0, width: style.width + 2 * pad, height: h + 2 * pad)
            content.text = text
            content.look = style
            content.tint = NSColor(srgbRed: style.color.r, green: style.color.g, blue: style.color.b, alpha: 1)
            content.setNeedsDisplay()
            lastStamp = -1
        }
        clip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.viewport)
        travel = max(0, contentHeight - Self.viewport)
        CATransaction.commit()
        guard scroll.stamp != lastStamp else { return }
        lastStamp = scroll.stamp
        restart(scroll: scroll, animated: animated)
    }

    /// Ordonnée du haut du contenu (origine en bas, le haut de la fenêtre vaut `viewport`) pour un avancement donné.
    private func top(progress: Double) -> Double { Self.viewport + travel * min(1, max(0, progress)) + TextBitmapLayer.padding * 0 }

    private func restart(scroll: AppModel.UnsyncedScroll, animated: Bool) {
        let pad = TextBitmapLayer.padding
        content.removeAnimation(forKey: "pf.scroll")
        let from = top(progress: scroll.progress) + pad, to = top(progress: 1) + pad
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.position = CGPoint(x: bounds.midX, y: animated && scroll.remaining > 0 ? to : from)
        CATransaction.commit()
        isAnimating = false
        guard animated, scroll.remaining > 0, travel > 0, to > from else { return }
        let a = CABasicAnimation(keyPath: "position.y")
        a.fromValue = from; a.toValue = to
        a.duration = scroll.remaining
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        a.fillMode = .both
        content.add(a, forKey: "pf.scroll")
        animationCount += 1; lastDuration = scroll.remaining; isAnimating = true
    }
}

struct UnsyncedScrollHost: NSViewRepresentable {
    var text: String
    var style: LineStackStyle
    var scroll: AppModel.UnsyncedScroll
    var animated: Bool
    var width: Double
    var register: (UnsyncedScrollLayerView) -> Void

    func makeNSView(context: Context) -> UnsyncedScrollLayerView {
        let v = UnsyncedScrollLayerView(frame: NSRect(x: 0, y: 0, width: width, height: UnsyncedScrollLayerView.viewport))
        register(v)
        return v
    }
    func updateNSView(_ v: UnsyncedScrollLayerView, context: Context) { v.apply(text: text, style: style, scroll: scroll, animated: animated) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: UnsyncedScrollLayerView, context: Context) -> CGSize? {
        CGSize(width: width, height: UnsyncedScrollLayerView.viewport)
    }
}
