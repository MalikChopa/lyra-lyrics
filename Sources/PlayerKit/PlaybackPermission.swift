import Foundation

/// Déroulé de l'autorisation Automatisation avant une commande de lecture (boutons ⏮ ⏯ ⏭, 1.0.1).
///
/// Le clic de l'utilisateur est le SEUL déclencheur : on lit l'état (sans invite) avec un délai de 4 s, puis
/// - accordée → la commande part ;
/// - refusée (−1743) → rien n'est demandé, l'app propose « Ouvrir les Réglages » ;
/// - lecteur fermé (−600) → rien ;
/// - non déterminée (−1744), ou lecture bloquée (cas J1) → `willAsk` (l'app écrit son explication dans la fenêtre), puis
///   `AEDeterminePermissionToAutomateTarget(ask: true)` HORS du fil principal, avec un délai de 180 s ; la réponse décide.
/// La sonde est injectée (tests : aucune invite, aucun Apple event).
public struct PlaybackPermissionFlow: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// `asked` : l'invite du système vient d'être acceptée (sinon l'autorisation existait déjà).
        case granted(asked: Bool)
        case refused
        case notRunning
        /// Pas de réponse dans le délai (invite ignorée ou appel bloqué).
        case noAnswer
    }

    /// (lecteur, demander ?) → état. `ask: true` peut bloquer jusqu'à la réponse à l'invite.
    public typealias Probe = @Sendable (PlayerID, Bool) -> AutomationStatus

    public static let statusTimeout = 4.0
    public static let askTimeout = 180.0

    private let probe: Probe
    private let statusTimeout: Double
    private let askTimeout: Double

    public init(probe: @escaping Probe = { PermissionProbe.status(for: $0, ask: $1) },
                statusTimeout: Double = PlaybackPermissionFlow.statusTimeout, askTimeout: Double = PlaybackPermissionFlow.askTimeout) {
        self.probe = probe; self.statusTimeout = statusTimeout; self.askTimeout = askTimeout
    }

    public func prepare(_ player: PlayerID, willAsk: @Sendable () async -> Void) async -> Outcome {
        let first = await Self.timed(statusTimeout) { probe(player, false) }
        switch first {
        case .granted?: return .granted(asked: false)
        case .denied?: return .refused
        case .notRunning?: return .notRunning
        default: break                                              // non déterminée, inconnue, ou lecture bloquée
        }
        await willAsk()
        let answer = await Self.timed(askTimeout) { probe(player, true) }
        switch answer {
        case .granted?: return .granted(asked: true)
        case .denied?: return .refused
        case .notRunning?: return .notRunning
        default: return .noAnswer
        }
    }

    /// Exécute `work` hors du fil appelant ; `nil` si rien n'est revenu en `seconds` (le thread bloqué est abandonné, jamais attendu).
    static func timed(_ seconds: Double, _ work: @escaping @Sendable () -> AutomationStatus) async -> AutomationStatus? {
        await withCheckedContinuation { (cont: CheckedContinuation<AutomationStatus?, Never>) in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                let status = work()
                if once.take() { cont.resume(returning: status) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if once.take() { cont.resume(returning: nil) }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var taken = false
        func take() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if taken { return false }
            taken = true
            return true
        }
    }
}
