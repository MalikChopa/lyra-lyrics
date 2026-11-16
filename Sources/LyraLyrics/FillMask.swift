import AppKit
import QuartzCore
import AppSupport

/// Rectangles occupés par chaque ligne rendue d'un texte renvoyé à la ligne (coordonnées de la couche `TextBitmapLayer` :
/// origine en bas, texte posé dans le cadre inscrit de `pad`, comme `draw(in:)`).
enum TextFragments {
    static func lineRects(text: String, style: LineStackStyle, bitmapHeight: Double) -> [CGRect] {
        let pad = TextBitmapLayer.padding
        let attrs = FontResolver.attributes(font: style.font, weight: style.weight, size: style.size, color: .white)
        let storage = NSTextStorage(attributedString: NSAttributedString(string: text, attributes: attrs))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: style.width, height: 100_000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var rects: [CGRect] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, used, _, _, _ in
            // `used` : origine en haut (NSLayoutManager) -> origine en bas de la couche.
            let y = bitmapHeight - pad - used.maxY
            rects.append(CGRect(x: pad + used.minX - 6, y: y - 4, width: used.width + 12, height: used.height + 8))
        }
        return rects.isEmpty ? [CGRect(x: pad, y: pad, width: style.width, height: max(1, bitmapHeight - 2 * pad))] : rects
    }
}

extension TextFragments {
    /// Un rectangle par MOT (mêmes repères que `lineRects`) : sortie de ligne mot à mot de la Scène.
    static func wordRects(text: String, style: LineStackStyle, bitmapHeight: Double) -> [CGRect] {
        let pad = TextBitmapLayer.padding
        let attrs = FontResolver.attributes(font: style.font, weight: style.weight, size: style.size, color: .white)
        let storage = NSTextStorage(attributedString: NSAttributedString(string: text, attributes: attrs))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: style.width, height: 100_000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var rects: [CGRect] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords]) { _, range, _, _ in
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // un mot coupé sur deux lignes donne un rectangle par fragment
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { r, _ in
                rects.append(CGRect(x: pad + r.minX - 5, y: bitmapHeight - pad - r.maxY - 4, width: r.width + 10, height: r.height + 8))
            }
        }
        return rects
    }
}

/// Masque de remplissage progressif de gauche à droite (S5 / S24) : un rectangle par ligne rendue, chacun révélé par une animation
/// linéaire `transform.scale.x` de couche (aucun redessin) ; les lignes suivantes attendent la fin des précédentes, en proportion de leur largeur.
@MainActor
final class FillMask {
    let layer = CALayer()
    private var pieces: [CALayer] = []
    private var cumulative: [Double] = [0]
    /// Dernier réglage (autotest et resynchronisation).
    private(set) var startFraction = 0.0
    private(set) var duration = 0.0
    private(set) var playing = false
    private(set) var startedAt = 0.0
    private(set) var animationCount = 0
    private(set) var isAnimating = false

    init(rects: [CGRect]) {
        layer.anchorPoint = .zero
        let total = max(1, rects.reduce(0) { $0 + $1.width })
        var acc = 0.0
        for r in rects {
            let p = CALayer()
            p.backgroundColor = NSColor.white.cgColor
            p.anchorPoint = CGPoint(x: 0, y: 0.5)
            p.bounds = CGRect(x: 0, y: 0, width: r.width, height: r.height)
            p.position = CGPoint(x: r.minX, y: r.midY)
            layer.addSublayer(p)
            pieces.append(p)
            acc += r.width / total
            cumulative.append(min(1, acc))
        }
        cumulative[cumulative.count - 1] = 1
    }

    /// Part réellement affichée (couches PRÉSENTÉES, pondérées par la largeur de chaque morceau) : autotest.
    func presentedFraction() -> Double {
        var filled = 0.0, total = 0.0
        for (i, p) in pieces.enumerated() {
            let w = Double(p.bounds.width)
            let sx = Double(((p.presentation() ?? p).value(forKeyPath: "transform.scale.x") as? NSNumber)?.doubleValue ?? 1)
            filled += w * min(1, max(0, sx)); total += w
            _ = i
        }
        return total > 0 ? filled / total : 0
    }

    /// Part remplie attendue maintenant, d'après le dernier réglage.
    func expectedFraction(now: Double = ProcessClock.seconds()) -> Double {
        guard duration > 0 else { return startFraction }
        return playing ? min(1, startFraction + (now - startedAt) / duration) : startFraction
    }

    /// `fraction` : part déjà remplie ; `duration` : durée totale de la ligne ; `playing` faux = figé à `fraction` ; `animated` faux = sans mouvement
    /// (« Réduire les animations » : pas de remplissage animé, la ligne est mise en valeur d'un coup, voir l'appelant).
    func set(fraction f0: Double, duration d: Double, playing: Bool, animated: Bool) {
        startFraction = min(1, max(0, f0)); duration = d; self.playing = playing; startedAt = ProcessClock.seconds()
        isAnimating = false
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, p) in pieces.enumerated() {
            p.removeAllAnimations()
            let c0 = cumulative[i], c1 = cumulative[i + 1]
            let v = c1 > c0 ? min(1, max(0, (startFraction - c0) / (c1 - c0))) : 1
            if animated && playing && v < 1 && d > 0 {
                p.transform = CATransform3DIdentity
                let a = CABasicAnimation(keyPath: "transform.scale.x")
                a.fromValue = v; a.toValue = 1
                a.duration = max(0.05, (c1 - max(c0, startFraction)) * d)
                a.beginTime = now + max(0, c0 - startFraction) * d
                a.timingFunction = CAMediaTimingFunction(name: .linear)
                a.fillMode = .both
                a.isRemovedOnCompletion = false
                p.add(a, forKey: "pf.fill")
                p.transform = CATransform3DIdentity
                animationCount += 1; isAnimating = true
            } else {
                p.transform = CATransform3DMakeScale(max(0.0001, v), 1, 1)
            }
        }
        CATransaction.commit()
    }
}
