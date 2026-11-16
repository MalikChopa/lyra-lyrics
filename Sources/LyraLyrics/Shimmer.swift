import AppKit
import SwiftUI
import QuartzCore

/// Attente élégante pendant la recherche des paroles (S22) : quelques barres fantômes, traversées lentement par un reflet doux.
/// N'apparaît qu'après `delay` s (une recherche rapide ne montre rien). « Réduire les animations » : barres fixes, sans reflet.
@MainActor
final class ShimmerLayer: CALayer {
    private(set) var isShimmering = false
    #if DEBUG
    nonisolated(unsafe) static var created = 0, animated = 0
    #endif

    init(size: CGSize, barFractions: [Double], barHeight: Double, spacing: Double, animated: Bool, delay: Double, fadeDuration: Double = 0.6) {
        super.init()
        #if DEBUG
        Self.created += 1; if animated { Self.animated += 1 }
        #endif
        bounds = CGRect(origin: .zero, size: size)
        opacity = 0
        let bars = CALayer()
        bars.frame = bounds
        var y = size.height / 2 + (Double(barFractions.count) * (barHeight + spacing) - spacing) / 2 - barHeight
        for f in barFractions {
            let bar = CALayer()
            let w = size.width * f
            bar.frame = CGRect(x: (size.width - w) / 2, y: y, width: w, height: barHeight)
            bar.cornerRadius = barHeight / 2
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.11).cgColor
            bars.addSublayer(bar)
            y -= barHeight + spacing
        }
        addSublayer(bars)
        if animated {
            let sweep = CAGradientLayer()
            sweep.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.24).cgColor, NSColor.clear.cgColor]
            sweep.startPoint = CGPoint(x: 0, y: 0.5); sweep.endPoint = CGPoint(x: 1, y: 0.5)
            let band = size.width * 0.45
            sweep.frame = CGRect(x: -band, y: 0, width: band, height: size.height)
            let clip = CALayer()
            clip.frame = bounds
            // le reflet n'est visible que sur les barres (masque = copie des barres)
            let maskBars = CALayer(); maskBars.frame = bounds
            for s in bars.sublayers ?? [] {
                let m = CALayer(); m.frame = s.frame; m.cornerRadius = s.cornerRadius; m.backgroundColor = NSColor.white.cgColor
                maskBars.addSublayer(m)
            }
            clip.mask = maskBars
            clip.addSublayer(sweep)
            addSublayer(clip)
            let a = CABasicAnimation(keyPath: "position.x")
            a.fromValue = -band / 2; a.toValue = size.width + band / 2
            a.duration = 1.9
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.repeatCount = .infinity
            sweep.add(a, forKey: "pf.shimmer")
            isShimmering = true
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = fadeDuration; fade.beginTime = CACurrentMediaTime() + delay
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); fade.fillMode = .both
        opacity = 1
        add(fade, forKey: "pf.shimmer-in")
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }
}

/// Pont SwiftUI pour la petite fenêtre.
struct ShimmerHost: NSViewRepresentable {
    var width: Double
    var height: Double
    var animated: Bool
    final class Host: NSView {
        var shimmer: ShimmerLayer?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Host {
        let v = Host(frame: NSRect(x: 0, y: 0, width: width, height: height))
        v.wantsLayer = true
        let s = ShimmerLayer(size: CGSize(width: width, height: height), barFractions: [0.78, 0.92, 0.6], barHeight: 11, spacing: 12, animated: animated, delay: 0.45)
        s.position = CGPoint(x: width / 2, y: height / 2)
        v.layer?.addSublayer(s)
        v.shimmer = s
        return v
    }
    func updateNSView(_ v: Host, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Host, context: Context) -> CGSize? { CGSize(width: width, height: height) }
}
