#if DEBUG
import AppKit
import AppSupport

/// `--snapshot <dossier> --glow-proof [--glow-old]` (DEBUG seulement) : preuve en pixels que la lueur et le remplissage karaoké ne dessinent
/// aucun rectangle de lumière. Chaque cas est rendu par le VRAI code (`TextBitmapLayer`, `FillMask`, `SceneLine`) sur un fond uni, puis comparé
/// à un rendu de référence des mêmes lettres, nettes, sans lueur ni ombre ni masque : la boîte des lettres est la zone où la référence diffère du fond
/// de plus de 40 niveaux ; on compte ensuite les pixels HORS de cette boîte agrandie de 6 pt qui diffèrent du fond. Texte inventé.
/// `--glow-old` remet les flous de l'ancienne lueur (16 et 5 pt) pour mesurer l'état d'avant la correction.
@MainActor
enum GlowProof {
    struct Case {
        var name: String
        var scene = false
        var glow = false
        var clearShadow = false
        var karaoke = false
        var soft = false
        var bg: (Int, Int, Int) = (18, 18, 32)
    }

    static let scale = 2.0
    static let text = "Phares sur la mer"

    static func run(directory: String) {
        if CommandLine.arguments.contains("--glow-old") { TextBitmapLayer.glowBlurs = [16, 5] }
        let cases: [Case] = [
            Case(name: "petite-defaut"),
            Case(name: "petite-defaut-karaoke", karaoke: true),
            Case(name: "petite-neon", glow: true),
            Case(name: "petite-neon-karaoke", glow: true, karaoke: true),
            Case(name: "petite-transparent", clearShadow: true, bg: (128, 128, 140)),
            Case(name: "petite-transparent-karaoke", clearShadow: true, karaoke: true, bg: (128, 128, 140)),
            Case(name: "scene-defaut", scene: true),
            Case(name: "scene-defaut-karaoke", scene: true, karaoke: true),
            Case(name: "scene-neon", scene: true, glow: true),
            Case(name: "scene-neon-karaoke", scene: true, glow: true, karaoke: true),
            Case(name: "scene-flou-voisine", scene: true, soft: true),
        ]
        for c in cases {
            guard let img = render(c, reference: false), let ref = render(c, reference: true) else { print("GLOWPROOF \(c.name) rendu impossible"); continue }
            SnapshotRunner.writePNG(img, to: directory + "/glow-" + c.name + ".png")
            print(measure(c, img: img, ref: ref))
        }
    }

    private static func render(_ c: Case, reference: Bool) -> CGImage? {
        let size = c.scene ? NSSize(width: 1000, height: 320) : NSSize(width: 560, height: 140)
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor(srgbRed: Double(c.bg.0) / 255, green: Double(c.bg.1) / 255, blue: Double(c.bg.2) / 255, alpha: 1).cgColor
        let glow = c.glow && !reference, shadow = c.clearShadow && !reference, karaoke = c.karaoke && !reference
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if c.scene {
            let line = SceneLine(index: 0, text: text, font: .rounded, weight: .bold, size: 70, width: 800, textColor: RGB(1, 0.89, 0.48), accentColor: RGB(1, 0.89, 0.48), glow: glow, scale: scale)
            line.container.position = CGPoint(x: size.width / 2, y: size.height / 2)
            if c.soft && !reference {
                line.soft.opacity = 0.7; line.accent.opacity = 0; line.base.opacity = 0
            } else {
                line.accent.opacity = 1; line.soft.opacity = 0
                line.base.opacity = karaoke ? 0.78 : 0
                if karaoke {
                    let mask = FillMask(rects: TextFragments.lineRects(text: text, style: line.style, bitmapHeight: line.container.bounds.height))
                    mask.layer.frame = line.container.bounds
                    line.accent.mask = mask.layer
                    mask.set(fraction: 0.55, duration: 2, playing: false, animated: false)
                    line.accent.look = line.style.withoutEffects
                    line.fill = mask
                }
            }
            root.addSublayer(line.container)
            line.container.setNeedsDisplay()
            for l in [line.base, line.accent, line.soft] { l.setNeedsDisplay() }
        } else {
            let style = LineStackStyle(font: .rounded, weight: .bold, size: 28, ratio: 1, color: RGB(1, 1, 1), glow: glow, clearShadow: shadow, width: 420)
            let h = FontResolver.measureHeight(text, size: 28, width: 420, font: .rounded, weight: .bold)
            let pad = TextBitmapLayer.padding
            let b = CGRect(x: 0, y: 0, width: 420 + 2 * pad, height: h + 2 * pad)
            func bitmap(_ tint: NSColor, opacity: Float, look: LineStackStyle? = nil) -> TextBitmapLayer {
                let l = TextBitmapLayer()
                l.contentsScale = scale; l.bounds = b; l.position = CGPoint(x: size.width / 2, y: size.height / 2)
                l.text = text; l.look = look ?? style; l.tint = tint; l.opacity = opacity
                l.setNeedsDisplay()
                return l
            }
            if karaoke {
                root.addSublayer(bitmap(.white, opacity: 0.55))     // réplique de `LineStackView.updateFill`
            }
            let sharp = bitmap(.white, opacity: 1, look: karaoke ? style.withoutEffects : style)
            if karaoke {
                let mask = FillMask(rects: TextFragments.lineRects(text: text, style: style, bitmapHeight: b.height))
                mask.layer.frame = sharp.bounds
                sharp.mask = mask.layer
                mask.set(fraction: 0.55, duration: 2, playing: false, animated: false)
            }
            root.addSublayer(sharp)
        }
        return SnapshotRunner.render(root, size: size, scale: scale)
    }

    private static func pixels(_ img: CGImage) -> (data: [UInt8], w: Int, h: Int, bpr: Int)? {
        guard let d = img.dataProvider?.data else { return nil }
        let n = CFDataGetLength(d)
        var bytes = [UInt8](repeating: 0, count: n)
        CFDataGetBytes(d, CFRange(location: 0, length: n), &bytes)
        return (bytes, img.width, img.height, img.bytesPerRow)
    }

    private static func measure(_ c: Case, img: CGImage, ref: CGImage) -> String {
        guard let a = pixels(img), let r = pixels(ref) else { return "GLOWPROOF \(c.name) pixels illisibles" }
        func diff(_ p: (data: [UInt8], w: Int, h: Int, bpr: Int), _ x: Int, _ y: Int) -> Int {
            let o = y * p.bpr + x * 4
            return max(abs(Int(p.data[o]) - c.bg.0), abs(Int(p.data[o + 1]) - c.bg.1), abs(Int(p.data[o + 2]) - c.bg.2))
        }
        var x0 = a.w, x1 = -1, y0 = a.h, y1 = -1
        for y in 0..<r.h { for x in 0..<r.w where diff(r, x, y) > 40 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        let m = Int(6 * scale)
        let bx0 = x0 - m, bx1 = x1 + m, by0 = y0 - m, by1 = y1 + m
        func outside(_ x: Int, _ y: Int) -> Bool { x < bx0 || x > bx1 || y < by0 || y > by1 }
        var n0 = 0, n2 = 0, n8 = 0, maxV = 0, maxStep = 0
        for y in 0..<a.h {
            for x in 0..<a.w where outside(x, y) {
                let d = diff(a, x, y)
                if d > 0 { n0 += 1 }; if d > 2 { n2 += 1 }; if d > 8 { n8 += 1 }
                maxV = max(maxV, d)
                if x + 1 < a.w, outside(x + 1, y) { maxStep = max(maxStep, abs(d - diff(a, x + 1, y))) }
                if y + 1 < a.h, outside(x, y + 1) { maxStep = max(maxStep, abs(d - diff(a, x, y + 1))) }
            }
        }
        // marge de lueur visible : plus grande distance (points) entre la boîte des lettres et un pixel qui diffère de plus de 2 niveaux
        var reach = 0
        for y in 0..<a.h { for x in 0..<a.w where diff(a, x, y) > 2 {
            let dx = max(x0 - x, 0, x - x1), dy = max(y0 - y, 0, y - y1)
            reach = max(reach, max(dx, dy))
        } }
        return "GLOWPROOF \(c.name): boite lettres \((x1 - x0 + 1) / Int(scale))x\((y1 - y0 + 1) / Int(scale)) pt, hors boite+6pt : pixels>0=\(n0) >2=\(n2) >8=\(n8) ecart max=\(maxV)/255 saut max entre voisins=\(maxStep) ; portee de la lueur (>2 niveaux)=\(Double(reach) / scale) pt"
    }
}
#endif
