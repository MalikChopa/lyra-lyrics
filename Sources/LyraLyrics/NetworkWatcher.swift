import Foundation
import Network

/// `NWPathMonitor` (§3.5) : hors connexion → aucune requête ; reprise au retour du réseau. Jamais démarré quand le point
/// d'accès est le faux serveur local ou le transport en processus (DEBUG) : le bouclage n'a pas besoin du réseau.
@MainActor
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private(set) var isOnline = true
    var onChange: ((Bool) -> Void)?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "pf.network", qos: .utility))
    }

    func stop() { if started { monitor.cancel() } }

    private func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        onChange?(online)
    }
}
