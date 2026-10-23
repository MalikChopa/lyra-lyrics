import Foundation
import Observation

/// Réglages persistés dans `UserDefaults` (une clé JSON versionnée). `@MainActor @Observable` : les vues lisent `settings`.
@MainActor
@Observable
public final class SettingsStore {
    public static let defaultsKey = "pf.settings"

    public private(set) var settings: Settings
    public let loadOutcome: Settings.DecodeOutcome
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let (s, outcome) = Settings.decode(defaults.data(forKey: Self.defaultsKey))
        settings = s
        loadOutcome = outcome
    }

    /// Modifie, ramène dans les plages, sauvegarde.
    public func update(_ change: (inout Settings) -> Void) {
        var s = settings
        change(&s)
        s.clamp()
        s.version = Settings.currentVersion
        guard s != settings else { return }
        settings = s
        save()
    }

    public func reset() {
        settings = Settings()
        save()
    }

    private func save() {
        if let data = settings.encoded() { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
