import Foundation
import AppSupport
import LyricsCore

/// « Nouvelle version disponible » (E1). UNE requête GET par jour au plus, au lancement, vers l'API publique de GitHub : session
/// éphémère (ni cache, ni cookies), User-Agent de l'app, rien d'autre n'est envoyé. Désactivable (« Vérifier les mises à jour »).
@MainActor
final class UpdateService {
    /// Point d'accès (remplaçable par un faux serveur local en DEBUG seulement).
    var endpoint = UpdateCheck.endpoint
    private(set) var requestCount = 0
    private(set) var lastOutcome: UpdateCheck.Outcome?
    private let session: URLSession

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.waitsForConnectivity = false
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 12
        c.httpAdditionalHeaders = ["User-Agent": AppIdentity.userAgent, "Accept": "application/vnd.github+json"]
        session = URLSession(configuration: c)
    }

    func check(localVersion: String = AppIdentity.version) async -> UpdateCheck.Outcome {
        requestCount += 1
        var outcome = UpdateCheck.Outcome.failed
        do {
            let (data, response) = try await session.data(from: endpoint)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 200_000 {
                outcome = UpdateCheck.outcome(data: data, localVersion: localVersion)
            }
        } catch {
            outcome = .failed
        }
        lastOutcome = outcome
        return outcome
    }
}
