import AppKit
import SwiftUI
import AppSupport

/// Police des paroles : Système / New York / SF Mono / Avenir Next, repli sur la police système si elle manque (§7).
enum FontResolver {
    struct Resolved {
        let nsFont: NSFont
        /// Nom réellement obtenu (diagnostic) ; `fellBack` vrai si la police demandée est absente.
        let name: String
        let fellBack: Bool
    }

    static func nsWeight(_ w: LyricWeight) -> NSFont.Weight {
        switch w { case .light: return .light; case .regular: return .regular; case .semibold: return .semibold; case .bold: return .bold }
    }

    static func resolve(_ font: LyricFont, size: Double, weight: LyricWeight = .bold) -> Resolved {
        let w = nsWeight(weight)
        let system = NSFont.systemFont(ofSize: size, weight: w)
        switch font {
        case .system:
            return Resolved(nsFont: system, name: system.fontName, fellBack: false)
        case .newYork:
            if let d = system.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) {
                return Resolved(nsFont: f, name: f.fontName, fellBack: false)
            }
            return Resolved(nsFont: system, name: system.fontName, fellBack: true)
        case .rounded:
            if let d = system.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) {
                return Resolved(nsFont: f, name: f.fontName, fellBack: false)
            }
            return Resolved(nsFont: system, name: system.fontName, fellBack: true)
        case .sfMono:
            let f = NSFont.monospacedSystemFont(ofSize: size, weight: w)
            return Resolved(nsFont: f, name: f.fontName, fellBack: false)
        case .avenirNext:
            let name: String
            switch weight { case .light: name = "AvenirNext-Regular"; case .regular: name = "AvenirNext-Medium"; case .semibold: name = "AvenirNext-DemiBold"; case .bold: name = "AvenirNext-Bold" }
            if let f = NSFont(name: name, size: size) {
                return Resolved(nsFont: f, name: f.fontName, fellBack: false)
            }
            return Resolved(nsFont: system, name: system.fontName, fellBack: true)
        }
    }

    static func swiftUIFont(_ font: LyricFont, size: Double, weight: LyricWeight = .bold) -> Font {
        Font(resolve(font, size: size, weight: weight).nsFont as CTFont)
    }

    /// Espacement supplémentaire pour obtenir l'interligne de la maquette (1,22 × taille).
    static func extraLineSpacing(_ font: LyricFont, size: Double, weight: LyricWeight = .bold) -> Double {
        let f = resolve(font, size: size, weight: weight).nsFont
        let natural = f.ascender - f.descender + f.leading
        return max(0, LyricsMetrics.lineHeightFactor * size - natural)
    }

    /// Hauteur d'un texte centré dans `width`, à la taille donnée (même police, même interligne que la vue).
    nonisolated static func measureHeight(_ text: String, size: Double, width: Double, font: LyricFont, weight: LyricWeight = .bold) -> Double {
        let f = resolve(font, size: size, weight: weight).nsFont
        let natural = f.ascender - f.descender + f.leading
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        ps.lineBreakMode = .byWordWrapping
        ps.lineSpacing = max(0, LyricsMetrics.lineHeightFactor * size - natural)
        let attr = NSAttributedString(string: text, attributes: [.font: f, .paragraphStyle: ps, .kern: -0.01 * size])
        let r = attr.boundingRect(with: NSSize(width: width, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(max(r.height, LyricsMetrics.lineHeightFactor * size))
    }

    static func fitter(font: LyricFont, weight: LyricWeight = .bold) -> LineFitter {
        LineFitter { text, size, width in measureHeight(text, size: size, width: width, font: font, weight: weight) }
    }

    /// Attributs de dessin d'une ligne (même police, même interligne, même approche que `measureHeight`).
    static func attributes(font: LyricFont, weight: LyricWeight, size: Double, color: NSColor) -> [NSAttributedString.Key: Any] {
        let f = resolve(font, size: size, weight: weight).nsFont
        let natural = f.ascender - f.descender + f.leading
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        ps.lineBreakMode = .byWordWrapping
        ps.lineSpacing = max(0, LyricsMetrics.lineHeightFactor * size - natural)
        return [.font: f, .paragraphStyle: ps, .kern: -0.01 * size, .foregroundColor: color]
    }
}
