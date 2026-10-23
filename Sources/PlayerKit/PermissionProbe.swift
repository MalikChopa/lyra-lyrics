import Foundation
import ApplicationServices

public enum AutomationStatus: Sendable, Equatable {
    case granted
    case denied             // −1743
    case notDetermined      // −1744 : une demande ferait apparaître l'invite
    case notRunning         // −600 : le lecteur doit être lancé pour connaître l'état
    case unknown(Int)
}

/// `AEDeterminePermissionToAutomateTarget`. Sans demander par défaut ; `ask: true` UNIQUEMENT sur un clic de l'utilisateur
/// (l'appel bloque jusqu'à la réponse à l'invite : l'appeler hors du fil principal).
public enum PermissionProbe {
    public static func status(for player: PlayerID, ask: Bool = false) -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.bundleID)
        guard let desc = target.aeDesc else { return .unknown(0) }
        let wildcard = AEEventClass(AppleEventClient.fourCC("****"))
        let status = AEDeterminePermissionToAutomateTarget(desc, wildcard, AEEventID(AppleEventClient.fourCC("****")), ask)
        return map(OSStatus: Int(status))
    }

    static func map(OSStatus code: Int) -> AutomationStatus {
        switch code {
        case 0: return .granted
        case -1743: return .denied
        case -1744: return .notDetermined
        case -600: return .notRunning
        default: return .unknown(code)
        }
    }
}
