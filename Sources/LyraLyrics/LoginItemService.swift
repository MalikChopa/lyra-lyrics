import Foundation
import ServiceManagement
import AppSupport
import LyricsCore

/// Lancement à l'ouverture de session (A2). Chemin 1 : `SMAppService.mainApp` (le moderne). Chemin 2 si le système le refuse
/// (app non signée par un développeur, signature locale) : un LaunchAgent écrit dans `~/Library/LaunchAgents` SEULEMENT quand
/// l'utilisateur coche la case, et supprimé quand il la décoche. Rien n'est écrit sans action de l'utilisateur.
@MainActor
final class LoginItemService {
    enum Path: String { case smAppService, launchAgent, none }

    struct Result: Equatable {
        var enabled: Bool
        var path: Path
        /// Phrase à montrer sous la case (nil : rien à dire).
        var message: String?
    }

    /// Autotest : dossier « maison » factice (le vrai `~/Library/LaunchAgents` n'est jamais touché) et SMAppService désactivé.
    var homeOverride: URL?
    var skipSMAppService = false
    private(set) var lastResult = Result(enabled: false, path: .none, message: nil)
    private(set) var lastSMError: String?

    private var label: String { Bundle.main.bundleIdentifier ?? "io.github.malikchopa.lyra-lyrics" }
    var agentURL: URL { homeOverride.map { LaunchAgent.url(label: label, home: $0) } ?? LaunchAgent.url(label: label) }
    var agentExists: Bool { FileManager.default.fileExists(atPath: agentURL.path) }

    var smStatus: SMAppService.Status { SMAppService.mainApp.status }

    /// État réel : enregistré auprès du système ou LaunchAgent présent.
    func isEnabled() -> Bool {
        (!skipSMAppService && SMAppService.mainApp.status == .enabled) || agentExists
    }

    @discardableResult
    func setEnabled(_ on: Bool) -> Result {
        if on {
            if !skipSMAppService {
                do {
                    try SMAppService.mainApp.register()
                    lastSMError = nil
                    switch SMAppService.mainApp.status {
                    case .enabled:
                        removeAgent()
                        return remember(Result(enabled: true, path: .smAppService, message: nil))
                    case .requiresApproval:
                        removeAgent()
                        return remember(Result(enabled: true, path: .smAppService, message: "À valider dans Réglages Système > Général > Éléments de connexion."))
                    default: break
                    }
                } catch {
                    lastSMError = String(describing: error).prefix(120).description
                }
                // Le système n'a pas accepté : repli LaunchAgent.
                try? SMAppService.mainApp.unregister()
            }
            return remember(writeAgent())
        }
        if !skipSMAppService { try? SMAppService.mainApp.unregister() }
        removeAgent()
        return remember(Result(enabled: false, path: .none, message: nil))
    }

    private func remember(_ r: Result) -> Result { lastResult = r; return r }

    private func writeAgent() -> Result {
        guard let data = LaunchAgent.plist(label: label, appPath: Bundle.main.bundlePath) else {
            return Result(enabled: false, path: .none, message: "Impossible de préparer le lancement automatique.")
        }
        do {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: agentURL, options: .atomic)
            return Result(enabled: true, path: .launchAgent, message: nil)
        } catch {
            return Result(enabled: false, path: .none, message: "Impossible d'écrire le lancement automatique.")
        }
    }

    private func removeAgent() { try? FileManager.default.removeItem(at: agentURL) }
}
