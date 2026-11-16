#if DEBUG
import AppKit
import CoreGraphics

/// Preuve en pixels (DEBUG, autotest `winshot`) : image RÉELLE de la fenêtre telle que le serveur de fenêtres la compose
/// (flou du verre, ombre de la fenêtre compris), puis mesure d'uniformité du fond le long de bandes sans texte.
/// `CGWindowListCreateImage` est obsolète dans le SDK : appelée par `dlsym`, sur NOTRE PROPRE fenêtre seulement (aucune permission).
@MainActor
enum WindowProof {
    private typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// `framing` : avec le cadre et l'ombre (image plus grande que la fenêtre) ; sinon exactement les pixels de la fenêtre.
    static func capture(_ window: NSWindow, framing: Bool) -> CGImage? {
        guard let s = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        let f = unsafeBitCast(s, to: Capture.self)
        // kCGWindowListOptionIncludingWindow = 8 ; kCGWindowImageBoundsIgnoreFraming = 1 (sans ombre) ; kCGWindowImageBestResolution = 8
        return f(.null, 8, UInt32(window.windowNumber), framing ? 8 : (1 | 8))?.takeRetainedValue()
    }

    static func savePNG(_ image: CGImage, to path: String) {
        guard path.hasPrefix("/tmp/") else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Couleur du TEXTE rendu : nombre de pixels (alpha 255) à moins de 12 niveaux de chacune des pastilles, sur toute l'image ; le texte net est
    /// dessiné en aplat de la couleur choisie, au cœur des lettres.
    static func swatchCounts(of image: CGImage, swatches: [(Int, Int, Int)]) -> [Int] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var counts = [Int](repeating: 0, count: swatches.count)
        var i = 0
        while i < w * h * 4 {
            if px[i + 3] == 255 {
                for (k, s) in swatches.enumerated() where abs(Int(px[i]) - s.0) <= 12 && abs(Int(px[i + 1]) - s.1) <= 12 && abs(Int(px[i + 2]) - s.2) <= 12 { counts[k] += 1 }
            }
            i += 4
        }
        return counts
    }

    /// Les 3 couleurs claires (luminance > 150) les plus fréquentes, en « RRGGBB:nombre » (diagnostic).
    static func topBright(of image: CGImage) -> String {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "" }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hist: [UInt32: Int] = [:]
        var i = 0
        while i < w * h * 4 {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            if px[i + 3] == 255, 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b) > 150 { hist[UInt32(r << 16 | g << 8 | b), default: 0] += 1 }
            i += 4
        }
        return hist.sorted { $0.value > $1.value }.prefix(3).map { String(format: "%06X:%d", $0.key, $0.value) }.joined(separator: " ")
    }

    struct Uniformity {
        var width = 0, height = 0
        /// Écart maximal (niveaux 0–255) entre une colonne et la médiane, alpha et luminance prémultipliée, sur x ∈ [marge, largeur − marge].
        var alphaDeviation = 0.0, lumaDeviation = 0.0
        /// Plus grand saut entre deux colonnes voisines (alpha, luminance).
        var alphaStep = 0.0, lumaStep = 0.0
        /// Moyennes du quart gauche et du quart droit (alpha) : doivent être égales.
        var leftAlpha = 0.0, rightAlpha = 0.0
        var leftLuma = 0.0, rightLuma = 0.0
    }

    /// Mesure sur deux bandes (haut : 5 à 9 pt sous le bord ; bas : 5 à 9 pt au-dessus), marge 40 pt aux coins (rayon des coins ≈ 22 pt).
    static func uniformity(of image: CGImage, scale: Double) -> Uniformity {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Uniformity() }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var u = Uniformity(); u.width = w; u.height = h
        let margin = Int(40 * scale)
        guard w > 2 * margin + 8 else { return u }
        func column(_ x: Int, rows: Range<Int>) -> (a: Double, l: Double) {
            var a = 0.0, l = 0.0
            for y in rows {
                let i = (y * w + x) * 4
                a += Double(px[i + 3]); l += 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
            }
            let n = Double(rows.count); return (a / n, l / n)
        }
        let top = Int(5 * scale)..<Int(9 * scale), bottom = (h - Int(9 * scale))..<(h - Int(5 * scale))
        for rows in [top, bottom] {
            let cols = (margin..<(w - margin)).map { column($0, rows: rows) }
            let medA = cols.map(\.a).sorted()[cols.count / 2], medL = cols.map(\.l).sorted()[cols.count / 2]
            u.alphaDeviation = max(u.alphaDeviation, cols.map { abs($0.a - medA) }.max() ?? 0)
            u.lumaDeviation = max(u.lumaDeviation, cols.map { abs($0.l - medL) }.max() ?? 0)
            for i in 1..<cols.count {
                u.alphaStep = max(u.alphaStep, abs(cols[i].a - cols[i - 1].a)); u.lumaStep = max(u.lumaStep, abs(cols[i].l - cols[i - 1].l))
            }
            let q = cols.count / 4
            if rows == top {
                u.leftAlpha = cols[..<q].map(\.a).reduce(0, +) / Double(q); u.rightAlpha = cols[(cols.count - q)...].map(\.a).reduce(0, +) / Double(q)
                u.leftLuma = cols[..<q].map(\.l).reduce(0, +) / Double(q); u.rightLuma = cols[(cols.count - q)...].map(\.l).reduce(0, +) / Double(q)
            }
        }
        return u
    }
}
#endif
