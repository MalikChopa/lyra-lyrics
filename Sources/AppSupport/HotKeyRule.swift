import Foundation

/// Raccourci global (décision du 2026-11-17) : il BASCULE le clic-à-travers dans les deux sens ; si la fenêtre est cachée,
/// il la montre (l'appui ne semble jamais ne rien faire) ; il ne la cache jamais. Cacher / montrer la fenêtre passe par le menu.
/// Règle pure, même fixture que le cœur C# : `Fixtures/golden/hotkey.json`.
public enum HotKeyRule {
    public struct Outcome: Equatable, Sendable {
        public let clickThrough: Bool
        public let showWindow: Bool
        public init(clickThrough: Bool, showWindow: Bool) { self.clickThrough = clickThrough; self.showWindow = showWindow }
    }

    public static func decide(windowShown: Bool, clickThrough: Bool) -> Outcome {
        Outcome(clickThrough: !clickThrough, showWindow: !windowShown)
    }
}
