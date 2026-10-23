import Foundation

/// Estimateur de position (§3.2) : `(p0, t0, état)` ; `estimate(now) = p0 + (now − t0)` en lecture, `p0` figé en pause.
/// Nouveau relevé : écart > 0,75 s → recalage franc (seek) ; sinon recalage silencieux (le `SyncEngine` évite alors tout
/// retour à une ligne précédente : hystérésis, délégué). Instant d'un relevé = milieu de l'aller-retour (fourni par l'appelant).
public struct PositionEstimator: Sendable, Equatable {
    public static let seekThreshold = 0.75

    public enum Recalibration: String, Sendable, Equatable {
        case initial      // premier relevé après une remise à zéro
        case seek         // écart > 0,75 s : recalage franc
        case silent       // écart ≤ 0,75 s : recalage silencieux
    }

    public private(set) var p0: Double = 0
    public private(set) var t0: Double = 0
    public private(set) var state: PlaybackReading.State = .stopped
    public private(set) var primed = false
    public private(set) var lastRecalibration: Recalibration = .initial

    public init() {}

    public var isPlaying: Bool { primed && state == .playing }

    /// Position estimée à l'instant `now` (jamais négative).
    public func estimate(at now: Double) -> Double {
        guard primed else { return 0 }
        switch state {
        case .playing: return max(0, p0 + (now - t0))
        case .paused, .stopped: return p0
        }
    }

    /// Applique un relevé et dit s'il s'agit d'un recalage franc (seek) ou silencieux.
    @discardableResult
    public mutating func apply(_ reading: PlaybackReading) -> Recalibration {
        let kind: Recalibration
        if !primed {
            kind = .initial
        } else {
            let predicted = estimate(at: reading.at)
            kind = abs(reading.position - predicted) > Self.seekThreshold ? .seek : .silent
        }
        p0 = max(0, reading.position)
        t0 = reading.at
        state = reading.state
        primed = true
        lastRecalibration = kind
        return kind
    }

    /// Changement de titre : tout oublier.
    public mutating func reset() {
        p0 = 0; t0 = 0; state = .stopped; primed = false; lastRecalibration = .initial
    }
}
