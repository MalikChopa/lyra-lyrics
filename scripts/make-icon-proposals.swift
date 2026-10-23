// Propositions d'icône (1024×1024 PNG), dessinées en CoreGraphics, aucun visuel copié ni téléchargé.
// Usage : swift scripts/make-icon-proposals.swift /tmp/ll-icones     (sortie hors du projet)
//   A « bulle »  : bulle de dialogue flottante, trois lignes de texte, la courante en accent
//   B « onde »   : une onde sonore qui se transforme en lignes de texte
//   C « vitre »  : une vitre en verre qui flotte au-dessus d'un décor coloré, une ligne surlignée
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, a])! }
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) })!
}
func pill(_ ctx: CGContext, _ r: CGRect, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
    ctx.setFillColor(color); ctx.fillPath()
}

/// Corps commun : carré arrondi de style macOS (824 pt dans 1024), ombre douce ; `draw` dessine dedans (clippé).
func icon(_ draw: (CGContext, CGRect) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(path); ctx.setFillColor(rgb(20, 20, 30)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    draw(ctx, body)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(rgb(255, 255, 255, 0.22)); ctx.setLineWidth(3); ctx.strokePath()
    return ctx.makeImage()!
}

// A : bulle
let a = icon { ctx, body in
    ctx.drawLinearGradient(gradient([rgb(94, 92, 230), rgb(10, 132, 255)]), start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.28), rgb(255, 255, 255, 0)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 520), options: [])
    // bulle blanche + queue
    let bubble = CGRect(x: 222, y: 330, width: 580, height: 400)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: rgb(10, 20, 80, 0.45))
    let p = CGMutablePath()
    p.addRoundedRect(in: bubble, cornerWidth: 120, cornerHeight: 120)
    p.move(to: CGPoint(x: 330, y: 345)); p.addLine(to: CGPoint(x: 290, y: 235)); p.addLine(to: CGPoint(x: 440, y: 335)); p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(rgb(255, 255, 255, 0.97)); ctx.fillPath()
    ctx.restoreGState()
    // trois lignes : voisines grises, courante accent
    pill(ctx, CGRect(x: 312, y: 622, width: 330, height: 34), rgb(150, 156, 180, 0.7))
    pill(ctx, CGRect(x: 312, y: 506, width: 400, height: 56), rgb(10, 132, 255))
    pill(ctx, CGRect(x: 312, y: 410, width: 250, height: 34), rgb(150, 156, 180, 0.7))
}

// B : onde → lignes
let b = icon { ctx, body in
    ctx.drawLinearGradient(gradient([rgb(18, 52, 70), rgb(8, 14, 28)]), start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    let heights: [CGFloat] = [120, 220, 340, 250, 150]
    for (i, h) in heights.enumerated() {
        let x = 190 + CGFloat(i) * 62
        pill(ctx, CGRect(x: x, y: 512 - h / 2, width: 34, height: h), rgb(64, 224, 208, 0.55 + 0.09 * CGFloat(i)))
    }
    // flèche discrète, puis lignes de texte
    ctx.setStrokeColor(rgb(255, 255, 255, 0.5)); ctx.setLineWidth(10); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 520, y: 512)); ctx.addLine(to: CGPoint(x: 566, y: 512)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 548, y: 534)); ctx.addLine(to: CGPoint(x: 570, y: 512)); ctx.addLine(to: CGPoint(x: 548, y: 490)); ctx.strokePath()
    pill(ctx, CGRect(x: 610, y: 610, width: 200, height: 32), rgb(255, 255, 255, 0.42))
    pill(ctx, CGRect(x: 610, y: 496, width: 230, height: 50), rgb(255, 255, 255))
    pill(ctx, CGRect(x: 610, y: 400, width: 160, height: 32), rgb(255, 255, 255, 0.42))
}

// C : vitre en verre
let c = icon { ctx, body in
    ctx.drawLinearGradient(gradient([rgb(255, 140, 90), rgb(214, 70, 150), rgb(80, 70, 220)]), start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    // décor : deux disques lumineux derrière la vitre
    ctx.setFillColor(rgb(255, 226, 122, 0.85)); ctx.fillEllipse(in: CGRect(x: 170, y: 640, width: 220, height: 220))
    ctx.setFillColor(rgb(143, 211, 255, 0.8)); ctx.fillEllipse(in: CGRect(x: 650, y: 190, width: 190, height: 190))
    // vitre
    let pane = CGRect(x: 190, y: 290, width: 644, height: 444)
    let panePath = CGPath(roundedRect: pane, cornerWidth: 78, cornerHeight: 78, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: rgb(30, 0, 60, 0.5))
    ctx.addPath(panePath); ctx.setFillColor(rgb(255, 255, 255, 0.30)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(panePath); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.45), rgb(255, 255, 255, 0.06)]), start: CGPoint(x: 190, y: 734), end: CGPoint(x: 834, y: 290), options: [])
    ctx.restoreGState()
    ctx.addPath(panePath); ctx.setStrokeColor(rgb(255, 255, 255, 0.7)); ctx.setLineWidth(5); ctx.strokePath()
    // lignes : voisines pâles, courante surlignée
    pill(ctx, CGRect(x: 290, y: 622, width: 300, height: 30), rgb(255, 255, 255, 0.55))
    pill(ctx, CGRect(x: 262, y: 492, width: 500, height: 86), rgb(255, 255, 255, 0.35))
    pill(ctx, CGRect(x: 300, y: 510, width: 424, height: 50), rgb(255, 255, 255))
    pill(ctx, CGRect(x: 330, y: 408, width: 250, height: 30), rgb(255, 255, 255, 0.55))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/ll-icones"
guard dir.hasPrefix("/tmp/") else { FileHandle.standardError.write(Data("sortie sous /tmp/ seulement\n".utf8)); exit(64) }
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, image) in [("A-bulle", a), ("B-onde", b), ("C-vitre", c)] {
    let url = URL(fileURLWithPath: "\(dir)/icone-\(name).png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    print(CGImageDestinationFinalize(dest) ? "ok \(url)" : "ERREUR \(name)")
}
