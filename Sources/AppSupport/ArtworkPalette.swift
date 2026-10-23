import Foundation
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// Couleur sRGB 0…1. Foundation seule (le calcul est testable sans interface).
public struct RGB: Equatable, Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public var hex: String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }

    /// Luminance relative WCAG 2.x.
    public var luminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Rapport de contraste WCAG entre deux couleurs opaques (1…21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    // HSB
    public var hsb: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
    public init(h: Double, s: Double, v: Double) {
        let hh = (h - floor(h)) * 6, c = v * s, x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(hh) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(r + m, g + m, b + m)
    }
    fileprivate func distance(to o: RGB) -> Double { sqrt((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)) }
}

/// Couleurs tirées de la pochette : dominante, secondaire, teinte de fond (sombre) et accent de la
/// ligne courante, dont le contraste WCAG contre la teinte est d'au moins 4,5 : 1.
public struct ArtworkPalette: Equatable, Sendable {
    public static let minContrast = 4.5

    public var dominant: RGB
    public var secondary: RGB
    /// Teinte du fond (Uni et Verre) : la dominante assombrie, jamais plus claire que `maxTintValue`.
    public var tint: RGB
    /// Couleur de la ligne courante, lisible sur `tint`.
    public var accent: RGB

    public static let maxTintValue = 0.30

    public var accentContrast: Double { RGB.contrast(accent, tint) }

    /// Palette depuis des pixels RGBA 8 bits (alpha ignoré sauf pixels quasi transparents, écartés). `nil` si l'image est vide.
    public static func from(rgba: [UInt8], width: Int, height: Int) -> ArtworkPalette? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        // Histogramme à 4 bits par canal (4096 cases) : effectif, nombre de pixels et somme des canaux.
        var count = [Double](repeating: 0, count: 4096)
        var sum = [(Double, Double, Double)](repeating: (0, 0, 0), count: 4096)
        var total = 0.0
        for i in 0..<(width * height) {
            let a = rgba[i * 4 + 3]
            if a < 32 { continue }
            let r = Double(rgba[i * 4]) / 255, g = Double(rgba[i * 4 + 1]) / 255, b = Double(rgba[i * 4 + 2]) / 255
            let bin = (Int(rgba[i * 4]) >> 4) << 8 | (Int(rgba[i * 4 + 1]) >> 4) << 4 | (Int(rgba[i * 4 + 2]) >> 4)
            count[bin] += 1; total += 1
            sum[bin].0 += r; sum[bin].1 += g; sum[bin].2 += b
        }
        guard total > 0 else { return nil }
        // Score : fréquence, favorisant les couleurs saturées et écartant le presque noir / presque blanc.
        struct Candidate { var color: RGB; var score: Double }
        var candidates: [Candidate] = []
        for bin in 0..<4096 where count[bin] > 0 {
            let n = count[bin]
            let c = RGB(sum[bin].0 / n, sum[bin].1 / n, sum[bin].2 / n)
            let (_, s, v) = c.hsb
            var weight = 0.25 + 1.75 * s
            if v < 0.12 { weight *= 0.2 }
            if v > 0.92 && s < 0.12 { weight *= 0.35 }
            candidates.append(Candidate(color: c, score: n / total * weight))
        }
        candidates.sort { $0.score > $1.score }
        // Regroupe les cases voisines (distance < 0,12) dans la première retenue : la dominante est celle d'un groupe, pas d'une case.
        var groups: [Candidate] = []
        for c in candidates {
            if let k = groups.firstIndex(where: { $0.color.distance(to: c.color) < 0.12 }) { groups[k].score += c.score }
            else { groups.append(c) }
        }
        groups.sort { $0.score > $1.score }
        guard let first = groups.first else { return nil }
        let dominant = first.color
        let secondary = groups.dropFirst().first { $0.color.distance(to: dominant) > 0.25 }?.color
            ?? { let (h, s, v) = dominant.hsb; return RGB(h: h + 0.08, s: min(1, s * 0.9), v: min(1, max(v, 0.6))) }()
        return ArtworkPalette(dominant: dominant, secondary: secondary)
    }

    /// Calcule teinte et accent (contraste vérifié) à partir de la dominante et de la secondaire.
    public init(dominant: RGB, secondary: RGB) {
        self.dominant = dominant; self.secondary = secondary
        let (h, s, v) = dominant.hsb
        // Teinte de fond : sombre, un peu désaturée si très vive.
        let tintV = min(max(v * 0.5, 0.14), Self.maxTintValue)
        let tint = RGB(h: h, s: min(s, 0.75), v: tintV)
        self.tint = tint
        // Accent : teinte de la secondaire si elle est colorée, sinon de la dominante ; clair et pastel, puis poussé vers le blanc
        // jusqu'à 4,5 : 1 (le blanc passe toujours sur une teinte de valeur ≤ 0,30).
        let base = secondary.hsb.s >= 0.15 ? secondary : dominant
        let (bh, bs, _) = base.hsb
        var accent = RGB(h: bh, s: min(bs, 0.55), v: 0.97)
        var step = 0
        while RGB.contrast(accent, tint) < Self.minContrast && step < 20 {
            accent = accent.mixed(with: RGB(1, 1, 1), 0.15)
            step += 1
        }
        if RGB.contrast(accent, tint) < Self.minContrast { accent = RGB(1, 1, 1) }
        self.accent = accent
    }
}

#if canImport(ImageIO)
public enum ArtworkDecoder {
    /// 8 Mo au plus : une pochette ne dépasse jamais cela ; au-delà, on ignore (mémoire seulement, jamais écrit).
    public static let maxBytes = 8 * 1024 * 1024
    public static let thumbnailSide = 48

    /// Décode (en mémoire, sans cache disque) une pochette PNG/JPEG/TIFF en vignette 48 px et en tire la palette.
    public static func palette(from data: Data) -> ArtworkPalette? {
        guard data.count > 0, data.count <= maxBytes else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSide, kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // Pré-multiplié -> direct (alpha 255 pour une pochette opaque : sans effet).
        for i in 0..<(w * h) {
            let a = Int(pixels[i * 4 + 3])
            if a > 0 && a < 255 {
                for k in 0..<3 { pixels[i * 4 + k] = UInt8(min(255, Int(pixels[i * 4 + k]) * 255 / a)) }
            }
        }
        return ArtworkPalette.from(rgba: pixels, width: w, height: h)
    }
}
#endif
