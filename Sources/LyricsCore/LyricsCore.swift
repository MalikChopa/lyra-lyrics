import Foundation

/// Cœur logique portable (Foundation seule). Stub J0 : l'implémentation arrive à J1.
public enum LyricsCore {
    public static let version = "0.0.0-j0"

    /// Fonction triviale testée à J0 : formate une position en secondes en « mm:ss ».
    public static func formatPosition(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
