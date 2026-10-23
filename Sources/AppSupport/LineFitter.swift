import Foundation

/// Constantes de mise en page de la maquette (`.lyrics`, `.line`, `.lines`).
public enum LyricsMetrics {
    public static let windowWidth = 460.0
    public static let paddingTop = 34.0
    public static let paddingBottom = 30.0
    public static let paddingSide = 28.0
    public static let textWidth = windowWidth - 2 * paddingSide      // 404
    public static let minHeight = 190.0
    /// Hauteur minimale selon le nombre de lignes visibles : une seule ligne tient dans une fenêtre plus basse.
    public static func minHeight(lineCount: Int) -> Double { lineCount <= 1 ? 120 : minHeight }
    public static let lineGap = 14.0
    public static let neighbourRatio = 0.66
    public static let lineHeightFactor = 1.22
    public static let cornerRadius = 24.0
    public static let minCurrentSize = 14.0                          // §4, plancher délégué
    public static let maxHeightFraction = 0.8                        // §4, 80 % de la hauteur visible
    // Redimensionnement à la souris (décision utilisateur du 2026-10-23)
    public static let minResizeWidth = 280.0
    public static let minResizeHeight = 110.0
    public static let maxResizeFraction = 0.9                        // 90 % de la zone visible, en largeur comme en hauteur
    public static let resizeGrip = 6.0                               // épaisseur de la zone de prise des bords
    /// Largeur du texte pour une largeur de fenêtre donnée.
    public static func textWidth(forWindowWidth w: Double) -> Double { max(120, w - 2 * paddingSide) }
    /// Taille de fenêtre imposée ramenée entre le minimum et 90 % de la zone visible (largeur, hauteur).
    public static func clampedSize(width: Double, height: Double, visible: (width: Double, height: Double)) -> (width: Double, height: Double) {
        (min(max(width, minResizeWidth), max(minResizeWidth, visible.width * maxResizeFraction)),
         min(max(height, minResizeHeight), max(minResizeHeight, visible.height * maxResizeFraction)))
    }
}

public struct LineFit: Equatable, Sendable {
    public var currentSize: Double
    public var neighbourSize: Double
    public var contentHeight: Double
    public var windowHeight: Double
    /// La police a dû diminuer sous la taille demandée.
    public var shrunk: Bool
    /// Même au plancher de police, la fenêtre dépasse 80 % de la hauteur visible (elle grandit jusqu'à la zone visible).
    public var exceedsMaxHeight: Bool

    public init(currentSize: Double, neighbourSize: Double, contentHeight: Double, windowHeight: Double, shrunk: Bool, exceedsMaxHeight: Bool) {
        self.currentSize = currentSize; self.neighbourSize = neighbourSize; self.contentHeight = contentHeight
        self.windowHeight = windowHeight; self.shrunk = shrunk; self.exceedsMaxHeight = exceedsMaxHeight
    }
}

/// Aspect d'une ligne selon son éloignement de la ligne courante (« défilement doux »). Toutes les lignes sont
/// dessinées à la même taille (celle de la courante, retour à la ligne identique) puis MISES À L'ÉCHELLE : une ligne qui devient
/// courante ne change donc ni de retour à la ligne ni de rendu, seulement d'échelle, d'opacité et de flou (animés par Core Animation).
public enum LineLook {
    public static func scale(offset: Int, ratio: Double) -> Double {
        switch abs(offset) { case 0: return 1; case 1: return ratio; default: return ratio * 0.88 }
    }
    public static func opacity(offset: Int) -> Double {
        switch abs(offset) { case 0: return 1; case 1: return 0.42; default: return 0.22 }
    }
    /// Rayon de flou gaussien (points) : léger.
    public static func blur(offset: Int) -> Double {
        switch abs(offset) { case 0: return 0; case 1: return 0.8; default: return 1.6 }
    }
}

/// §4 : la fenêtre grandit jusqu'à 80 % de la hauteur visible ; au-delà la police des lignes diminue (rapport conservé)
/// jusqu'à 14 pt pour la courante ; puis la fenêtre grandit encore jusqu'à la zone visible.
/// `measure(texte, taille, largeur)` renvoie la hauteur de texte (injectée : AppKit dans l'app, bouchon dans les tests).
/// La ligne du milieu (`lines.count / 2`) est la courante ; les autres sont mesurées à la même taille puis réduites par `LineLook.scale`.
public struct LineFitter: Sendable {
    public var measure: @Sendable (String, Double, Double) -> Double
    public init(measure: @escaping @Sendable (String, Double, Double) -> Double) { self.measure = measure }

    /// Hauteurs affichées (après échelle) de chaque ligne.
    public func displayedHeights(lines: [String], currentSize: Double, ratio: Double, width: Double = LyricsMetrics.textWidth) -> [Double] {
        let mid = lines.count / 2
        return lines.enumerated().map { i, text in
            measure(text.isEmpty ? " " : text, currentSize, width) * LineLook.scale(offset: i - mid, ratio: ratio)
        }
    }

    public func height(lines: [String], currentSize: Double, ratio: Double = LyricsMetrics.neighbourRatio,
                       width: Double = LyricsMetrics.textWidth) -> (content: Double, window: Double) {
        let content = LyricsMetrics.lineGap * Double(max(lines.count - 1, 0))
            + displayedHeights(lines: lines, currentSize: currentSize, ratio: ratio, width: width).reduce(0, +)
        let window = max(LyricsMetrics.minHeight(lineCount: lines.count), LyricsMetrics.paddingTop + content + LyricsMetrics.paddingBottom)
        return (content, window)
    }

    public func fit(lines: [String], baseSize: Double, visibleHeight: Double, ratio: Double = LyricsMetrics.neighbourRatio) -> LineFit {
        let maxHeight = visibleHeight * LyricsMetrics.maxHeightFraction
        var size = baseSize
        while true {
            let h = height(lines: lines, currentSize: size, ratio: ratio)
            if h.window <= maxHeight {
                return LineFit(currentSize: size, neighbourSize: size * ratio, contentHeight: h.content,
                               windowHeight: h.window, shrunk: size < baseSize, exceedsMaxHeight: false)
            }
            if size <= LyricsMetrics.minCurrentSize {
                return LineFit(currentSize: size, neighbourSize: size * ratio, contentHeight: h.content,
                               windowHeight: min(h.window, visibleHeight), shrunk: size < baseSize, exceedsMaxHeight: true)
            }
            size = max(size - 1, LyricsMetrics.minCurrentSize)
        }
    }

    /// Taille de fenêtre IMPOSÉE par l'utilisateur (redimensionnement à la souris) : AJUSTEMENT AUTOMATIQUE du texte. La taille de police
    /// effective est la plus grande, entre `floor` (14 pt) et `baseSize` (réglage « Taille max »), pour laquelle les `lines.count`
    /// lignes visibles tiennent dans la fenêtre en largeur ET en hauteur (voisines au rapport `ratio`) : agrandir la fenêtre agrandit
    /// le texte, la réduire le réduit. Le retour à la ligne n'intervient que si la ligne la plus longue ne tient pas en une seule
    /// ligne même au plancher (le contenu peut alors dépasser la hauteur : `exceedsMaxHeight`).
    public func fit(lines: [String], baseSize: Double, fixedWindowWidth: Double, fixedWindowHeight: Double, ratio: Double,
                    floor: Double = LyricsMetrics.minCurrentSize) -> LineFit {
        let width = LyricsMetrics.textWidth(forWindowWidth: fixedWindowWidth)
        let available = fixedWindowHeight - LyricsMetrics.paddingTop - LyricsMetrics.paddingBottom
        let texts = lines.filter { !$0.isEmpty }
        func singleLine(_ size: Double) -> Bool {
            let one = measure("M", size, width)
            return texts.allSatisfy { measure($0, size, width) <= one * 1.4 }
        }
        var size = max(baseSize, floor)
        while true {
            let content = height(lines: lines, currentSize: size, ratio: ratio, width: width).content
            if size <= floor || (content <= available && singleLine(size)) {
                return LineFit(currentSize: size, neighbourSize: size * ratio, contentHeight: content, windowHeight: fixedWindowHeight,
                               shrunk: size < baseSize, exceedsMaxHeight: content > available)
            }
            size = max(size - 1, floor)
        }
    }
}
