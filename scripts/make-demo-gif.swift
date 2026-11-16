// Assemble le GIF de démo du README à partir d'images PNG `f-NN-<durée ms>.png` (images produites par
// `LyraLyrics --snapshot <dossier> --scene-only`, titres, paroles et pochettes INVENTÉS ; aucune capture d'écran).
// Usage : swift scripts/make-demo-gif.swift <dossier des images> <sortie.gif>
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write(Data("usage : make-demo-gif.swift <dossier> <sortie.gif>\n".utf8)); exit(64) }
let dir = URL(fileURLWithPath: args[1])
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("f-") && $0.hasSuffix(".png") }.sorted()
guard !files.isEmpty,
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.gif.identifier as CFString, files.count, nil) else {
    FileHandle.standardError.write(Data("aucune image\n".utf8)); exit(65)
}
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
var total = 0.0
for f in files {
    let parts = f.dropLast(4).split(separator: "-")
    let ms = Double(parts.last ?? "300") ?? 300
    total += ms
    guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(f) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: ms / 1000]] as CFDictionary)
}
guard CGImageDestinationFinalize(dest) else { exit(66) }
print("GIF : \(files.count) images, \(total / 1000) s")
