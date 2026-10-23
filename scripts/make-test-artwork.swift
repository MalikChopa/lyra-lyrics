// Génère des pochettes INVENTÉES (dégradés et formes, aucune œuvre) pour tester les couleurs de pochette :
//   swift scripts/make-test-artwork.swift Fixtures/artwork
// 96 x 96 px, PNG. Aucune dépendance.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Fixtures/artwork"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1])!
}

func make(_ name: String, top: UInt32, bottom: UInt32, shape: UInt32, shapeRect: CGRect) {
    let size = 96
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])
    ctx.setFillColor(color(shape))
    ctx.fillEllipse(in: shapeRect)
    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { print("échec \(name)"); exit(1) }
    print("écrit \(url.path)")
}

make("rouge", top: 0xE8452C, bottom: 0x7A1230, shape: 0xFFC857, shapeRect: CGRect(x: 52, y: 14, width: 32, height: 32))
make("bleu", top: 0x2B6CB0, bottom: 0x0B2A5B, shape: 0x7FDBDA, shapeRect: CGRect(x: 12, y: 40, width: 44, height: 44))
make("vert", top: 0x3FAE5A, bottom: 0x0F4D2E, shape: 0xF2E394, shapeRect: CGRect(x: 30, y: 30, width: 36, height: 36))
make("jaune", top: 0xFFF3A8, bottom: 0xF2D55A, shape: 0xFFFFFF, shapeRect: CGRect(x: 20, y: 20, width: 56, height: 56))
make("sombre", top: 0x15151A, bottom: 0x050507, shape: 0x2A2A33, shapeRect: CGRect(x: 30, y: 30, width: 36, height: 36))
make("gris", top: 0x8A8A8F, bottom: 0x55555A, shape: 0xB5B5BA, shapeRect: CGRect(x: 28, y: 28, width: 40, height: 40))
make("violet", top: 0x8E44AD, bottom: 0x3B1A5A, shape: 0xFF8FB8, shapeRect: CGRect(x: 40, y: 12, width: 40, height: 40))
