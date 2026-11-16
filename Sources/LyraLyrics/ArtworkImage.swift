import Foundation
import ImageIO
import CoreGraphics

struct ArtworkImageBox: @unchecked Sendable { var image: CGImage? }

/// Décodage d'une pochette en image réduite (mémoire seulement, jamais écrite sur le disque).
enum ArtworkImage {
    static func downscaled(_ data: Data, maxPixel: Int) -> CGImage? {
        guard data.count > 0, data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCache: false]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
