#if DEBUG
import AppKit
import AppSupport

/// `--snapshot <dossier> --multiline-proof` (DEBUG seulement) : preuve en pixels du surlignage d'une ligne courante renvoyée à la ligne (1.1.0).
/// Chaque cas est rendu par le VRAI code (`TextBitmapLayer`, `FillMask`, `SceneLine`) sur un fond uni. Les pixels « pleins » des lettres
/// (couverture complète, relevés sur un rendu de référence en rouge) sont classés par ligne visuelle : « surlignés » (rouge) ou non (blanc terne).
/// Karaoké désactivé : 100 % des pixels pleins doivent être surlignés. Karaoké activé : le remplissage avance ligne visuelle par ligne visuelle.
/// Texte inventé.
@MainActor
enum MultilineProof {
    static let scale = 2.0
    nonisolated(unsafe) static var text = "Depuis l'époque des petits écoliers"
    nonisolated(unsafe) static var font = LyricFont.system
    nonisolated(unsafe) static var weight = LyricWeight.semibold
    nonisolated(unsafe) static var width = 460.0
    nonisolated(unsafe) static var verbose = true
    nonisolated(unsafe) static var fontSize = 34.0
    static let bg = (18, 18, 32)
    static let hi = RGB(1, 0.15, 0.15)

    struct Case { var name: String; var scene: Bool; var fractions: [Double?] }     // nil : karaoké désactivé

    static func run(directory: String) {
        if CommandLine.arguments.contains("--sweep") {
            let r = check(texts: texts, fonts: LyricFont.allCases, weights: LyricWeight.allCases, sizes: [18, 26, 34, 44], widths: [180, 240, 300, 380, 460], verbose: true)
            print("SWEEP fin : \(r.checked) cas, \(r.failed) en echec, pire part surlignee a 100 %% = \(String(format: "%.1f", r.worst)) %")
            return
        }
        let cases = [
            Case(name: "petite", scene: false, fractions: [nil, 0, 0.25, 0.5, 0.75, 1]),
            Case(name: "scene", scene: true, fractions: [nil, 0, 0.25, 0.5, 0.75, 1]),
        ]
        for c in cases {
            for f in c.fractions {
                let tag = f.map { "karaoke-\(Int($0 * 100))" } ?? "sans-karaoke"
                guard let img = render(c, fraction: f, reference: false), let ref = render(c, fraction: f, reference: true) else { print("MULTILINE \(c.name) \(tag) rendu impossible"); continue }
                SnapshotRunner.writePNG(img, to: directory + "/multiline-\(c.name)-\(tag).png")
                print(measure(c, tag: tag, img: img, ref: ref))
            }
        }
    }

    private static func render(_ c: Case, fraction: Double?, reference: Bool) -> CGImage? {
        let size = c.scene ? NSSize(width: 1000, height: 500) : NSSize(width: 560, height: 500)
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: size)
        root.backgroundColor = NSColor(srgbRed: Double(bg.0) / 255, green: Double(bg.1) / 255, blue: Double(bg.2) / 255, alpha: 1).cgColor
        let white = RGB(1, 1, 1)
        let hiColor = NSColor(srgbRed: hi.r, green: hi.g, blue: hi.b, alpha: 1)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let karaoke = fraction != nil && !reference
        if c.scene {
            let line = SceneLine(index: 0, text: text, font: font, weight: weight, size: 70, width: 560, textColor: reference ? hi : white, accentColor: hi, glow: false, scale: scale)
            line.container.position = CGPoint(x: size.width / 2, y: size.height / 2)
            line.accent.opacity = 1; line.soft.opacity = 0
            line.base.opacity = karaoke ? 0.55 : 0
            if reference { line.base.opacity = 0 }
            if karaoke, let f = fraction {
                let mask = FillMask(rects: TextFragments.lineRects(text: text, style: line.style, bitmapHeight: line.container.bounds.height))
                mask.layer.frame = line.container.bounds
                line.accent.mask = mask.layer
                mask.set(fraction: f, duration: 2, playing: false, animated: false)
                line.accent.look = line.style.withoutEffects
                line.fill = mask
            }
            root.addSublayer(line.container)
            line.container.setNeedsDisplay()
            for l in [line.base, line.accent, line.soft] { l.setNeedsDisplay() }
        } else {
            let style = LineStackStyle(font: font, weight: weight, size: fontSize, ratio: 1, color: reference ? hi : white, fillColor: hi, glow: false, clearShadow: false, width: width)
            let h = FontResolver.measureHeight(text, size: fontSize, width: width, font: font, weight: weight)
            let pad = TextBitmapLayer.padding
            let b = CGRect(x: 0, y: 0, width: width + 2 * pad, height: h + 2 * pad)
            func bitmap(_ tint: NSColor, opacity: Float, look: LineStackStyle) -> TextBitmapLayer {
                let l = TextBitmapLayer()
                l.contentsScale = scale; l.bounds = b; l.position = CGPoint(x: size.width / 2, y: size.height / 2)
                l.text = text; l.look = look; l.tint = tint; l.opacity = opacity
                l.setNeedsDisplay()
                return l
            }
            if karaoke, let f = fraction {
                root.addSublayer(bitmap(.white, opacity: 0.55, look: style))
                let sharp = bitmap(hiColor, opacity: 1, look: style.withoutEffects)
                let mask = FillMask(rects: TextFragments.lineRects(text: text, style: style, bitmapHeight: b.height))
                mask.layer.frame = sharp.bounds
                sharp.mask = mask.layer
                mask.set(fraction: f, duration: 2, playing: false, animated: false)
                root.addSublayer(sharp)
            } else {
                // état réel sans karaoké (`LineStackView.redraw`) : une seule couche, teinte = couleur du texte choisie (ici le surlignage)
                root.addSublayer(bitmap(reference ? hiColor : hiColor, opacity: 1, look: style))
            }
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

    /// Pour chaque ligne visuelle de la référence : (pixels pleins surlignés dans le rendu, pixels pleins de la référence).
    private static func lineCounts(img: CGImage, ref: CGImage) -> [(hi: Int, full: Int)]? {
        guard let a = pixels(img), let r = pixels(ref) else { return nil }
        // pixels pleins de la référence : rouge pur (écart au fond maximal) ; rangés par ligne visuelle (bandes de rangées sans pixel plein)
        func full(_ x: Int, _ y: Int) -> Bool { let o = y * r.bpr + x * 4; return Int(r.data[o]) >= 250 && Int(r.data[o + 1]) <= 45 }
        var rowHas = [Bool](repeating: false, count: r.h)
        for y in 0..<r.h { for x in 0..<r.w where full(x, y) { rowHas[y] = true; break } }
        var bands: [(Int, Int)] = []
        var y = 0
        while y < r.h {
            if rowHas[y] { var e = y; while e + 1 < r.h, rowHas[e + 1] { e += 1 }; bands.append((y, e)); y = e + 1 } else { y += 1 }
        }
        // fusionne les bandes séparées de moins de 6 pt (accents, points des i)
        var lines: [(Int, Int)] = []
        for b in bands { if let last = lines.last, b.0 - last.1 < Int(6 * scale) { lines[lines.count - 1].1 = b.1 } else { lines.append(b) } }
        return lines.map { band in
            var nFull = 0, nHi = 0
            for yy in band.0...band.1 { for x in 0..<r.w where full(x, yy) {
                nFull += 1
                let o = yy * a.bpr + x * 4
                if Int(a.data[o]) >= 230 && Int(a.data[o + 1]) <= 70 { nHi += 1 }       // rouge : surligné ; blanc terne (g > 100) : non
            } }
            return (nHi, nFull)
        }
    }

    private static func measure(_ c: Case, tag: String, img: CGImage, ref: CGImage) -> String {
        guard let lines = lineCounts(img: img, ref: ref) else { return "MULTILINE \(c.name) \(tag) pixels illisibles" }
        let parts = lines.enumerated().map { i, l in
            "ligne \(i + 1): \(l.hi)/\(l.full) (\(l.full > 0 ? String(format: "%.1f", Double(l.hi) * 100 / Double(l.full)) : "-") %)"
        }
        return "MULTILINE \(c.name) \(tag): \(lines.count) lignes visuelles ; pixels pleins surlignes " + parts.joined(separator: " ; ")
            + " ; total \(lines.reduce(0) { $0 + $1.hi })/\(lines.reduce(0) { $0 + $1.full })"
    }

    static let texts = ["Depuis l'époque des petits écoliers", "Depuis l’époque des petits écoliers", "Une phrase très longue qui doit passer sur plusieurs lignes éclairées"]

    /// Grille de contrôle (autotest `multiline`, option `--sweep`) : pour chaque police, graisse, corps, largeur et texte de la petite fenêtre,
    /// karaoké à 100 % : chaque pixel plein de chaque ligne visuelle doit être surligné (seuil : 99,5 %) ; à 0 %, 50 % : lignes dans l'ordre
    /// (celles d'avant la ligne en cours à 100 %, celles d'après à 0 %, une seule ligne partielle).
    static func check(texts: [String], fonts: [LyricFont], weights: [LyricWeight], sizes: [Double], widths: [Double], verbose: Bool = false) -> (checked: Int, failed: Int, worst: Double) {
        let saved = (text, font, weight, width, fontSize)
        defer { (text, font, weight, width, fontSize) = saved }
        var checked = 0, failed = 0, worst = 100.0
        let cs = Case(name: "petite", scene: false, fractions: [])
        for t in texts { for f in fonts { for w in weights { for sz in sizes { for wd in widths {
            text = t; font = f; weight = w; fontSize = sz; width = wd
            guard let ref = render(cs, fraction: 1, reference: true), let full = render(cs, fraction: 1, reference: false), let half = render(cs, fraction: 0.5, reference: false),
                  let lFull = lineCounts(img: full, ref: ref), let lHalf = lineCounts(img: half, ref: ref) else { failed += 1; checked += 1; continue }
            checked += 1
            let pct = lFull.map { $0.full > 0 ? Double($0.hi) * 100 / Double($0.full) : 100 }
            worst = min(worst, pct.min() ?? 100)
            var ok = pct.allSatisfy { $0 >= 99.5 }
            // ordre à 50 % : pourcentages décroissants, au plus une ligne strictement partielle
            let ph = lHalf.map { $0.full > 0 ? Double($0.hi) * 100 / Double($0.full) : 0 }
            let partial = ph.filter { $0 > 0.5 && $0 < 99.5 }.count
            if partial > 1 || zip(ph, ph.dropFirst()).contains(where: { $1 > $0 + 0.5 }) { ok = false }
            if !ok { failed += 1; if verbose { print("SWEEP", f, w, sz, wd, t, pct.map { String(format: "%.1f", $0) }, "a 50 % :", ph.map { String(format: "%.1f", $0) }) } }
        } } } } }
        return (checked, failed, worst)
    }
}
#endif
