import Foundation

/// Fenêtre affichée : (précédente, courante, suivante).
public struct LineWindow: Sendable, Equatable {
    public var index: Int
    public var previous: String?
    public var current: String
    public var next: String?
    public init(index: Int, previous: String?, current: String, next: String?) {
        self.index = index; self.previous = previous; self.current = current; self.next = next
    }
}

/// Moteur de synchro (§3.2) : recherche dichotomique de la ligne pour `position + avance (0,15 s) + décalage manuel` ;
/// avant la 1re ligne : « ♪ ». Décalage manuel borné à ± 5 s par pas de 0,1 s (décision utilisateur du 2026-10-22).
public struct SyncEngine: Sendable, Equatable {
    public static let lead = 0.15
    public static let offsetRange: ClosedRange<Double> = -5.0...5.0
    public static let offsetStep = 0.1
    public static let placeholder = LRCParser.placeholder

    public private(set) var lines: [LyricLine]
    public var manualOffset: Double {
        didSet { manualOffset = Self.snappedOffset(manualOffset) }
    }

    public init(lines: [LyricLine] = [], manualOffset: Double = 0) {
        self.lines = lines.sorted { $0.time < $1.time }
        self.manualOffset = Self.snappedOffset(manualOffset)
    }

    /// Borne à ± 5 s et arrondit au dixième.
    public static func snappedOffset(_ value: Double) -> Double {
        let clamped = min(max(value, offsetRange.lowerBound), offsetRange.upperBound)
        return (clamped * 10).rounded() / 10
    }

    public func effectivePosition(_ position: Double) -> Double { position + Self.lead + manualOffset }

    /// Indice de la dernière ligne dont l'horodatage ≤ position effective ; −1 avant la première ligne.
    public func index(at position: Double) -> Int {
        let target = effectivePosition(position)
        var low = 0, high = lines.count          // premier indice dont time > target
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= target { low = mid + 1 } else { high = mid }
        }
        return low - 1
    }

    /// Avec hystérésis : après un recalage silencieux (< 0,75 s) on ne revient jamais à une ligne précédente ;
    /// `allowBackward` vrai après un seek, un changement de décalage ou une pause.
    public func index(at position: Double, previous: Int, allowBackward: Bool) -> Int {
        let i = index(at: position)
        if !allowBackward, previous >= 0, i < previous { return previous }
        return i
    }

    public func window(index: Int) -> LineWindow {
        func text(_ i: Int) -> String? { i >= 0 && i < lines.count ? lines[i].text : nil }
        if index < 0 {
            return LineWindow(index: -1, previous: nil, current: Self.placeholder, next: text(0))
        }
        let i = min(index, lines.count - 1)
        return LineWindow(index: i, previous: text(i - 1), current: text(i) ?? Self.placeholder, next: text(i + 1))
    }

    public func window(position: Double) -> LineWindow { window(index: index(at: position)) }
}
