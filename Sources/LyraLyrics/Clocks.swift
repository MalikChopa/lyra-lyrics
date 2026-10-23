import Foundation

/// Horloge monotone du processus, en secondes depuis le démarrage : la même pour le modèle, l'estimateur, le faux lecteur
/// et le journal de diagnostic (les instants comparés par la mesure 3 du §5 viennent tous d'ici).
enum ProcessClock {
    static let origin = ContinuousClock.now

    static func seconds(_ instant: ContinuousClock.Instant = .now) -> Double {
        let d = instant - origin
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}
