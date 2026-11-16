import AppKit
import CoreImage
import QuartzCore
import AppSupport

struct BlurResult: @unchecked Sendable {
    var image: CGImage
    /// Luminance relative maximale (WCAG) de l'image floutée : sert à régler le voile qui garde le texte à ≥ 4,5 : 1.
    var maxLuminance: Double
}

/// Pochette floutée UNE fois par titre (petite image, flou gaussien) : affichée ensuite agrandie par le processeur graphique, sans
/// aucun filtre recalculé à chaque image. Fournit aussi le bruit du grain.
enum SceneArtwork {
    static func blurred(_ source: CGImage) -> BlurResult? {
        let side = 160
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // remplissage « aspect fill » carré
        let w = Double(source.width), h = Double(source.height), s = max(Double(side) / w, Double(side) / h)
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: (Double(side) - w * s) / 2, y: (Double(side) - h * s) / 2, width: w * s, height: h * s))
        guard let small = ctx.makeImage() else { return nil }
        let input = CIImage(cgImage: small)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(14.0, forKey: kCIInputRadiusKey)
        guard let out = filter.outputImage?.cropped(to: input.extent) else { return nil }
        let ci = CIContext(options: [.useSoftwareRenderer: false])
        guard let blurred = ci.createCGImage(out, from: input.extent, format: .RGBA8, colorSpace: space) else { return nil }
        return BlurResult(image: blurred, maxLuminance: maxLuminance(of: blurred))
    }

    /// Luminance relative maximale sur une grille 12 × 12 (cases moyennées) de l'image.
    static func maxLuminance(of image: CGImage) -> Double {
        let n = 12
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return 1 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        let px = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var best = 0.0
        for i in 0..<(n * n) {
            let c = RGB(Double(px[i * 4]) / 255, Double(px[i * 4 + 1]) / 255, Double(px[i * 4 + 2]) / 255)
            best = max(best, c.luminance)
        }
        return best
    }

    /// Dalle de bruit (grain de film très léger) : gris aléatoires à faible opacité.
    static func grainTile(side: Int = 256) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var g = SystemRandomNumberGenerator()
        for i in 0..<(side * side) {
            let light = Bool.random(using: &g)
            let a = UInt8.random(in: 0...10, using: &g)                 // alpha 0…4 % : très léger
            let v: UInt8 = light ? 255 : 0
            px[i * 4] = UInt8(Int(v) * Int(a) / 255); px[i * 4 + 1] = px[i * 4]; px[i * 4 + 2] = px[i * 4]; px[i * 4 + 3] = a
        }
        return ctx.makeImage()
    }

    /// Petit disque doux (particules).
    static func softDot(side: Int = 32) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        guard let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return nil }
        let c = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: Double(side) / 2, options: [])
        return ctx.makeImage()
    }
}
