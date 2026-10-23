import Foundation

/// Politique de la pochette. Règles, toutes testées :
/// - réglage « Couleurs de la pochette » désactivé : AUCUNE requête (ni Apple event, ni HTTP) ;
/// - une seule requête en vol : un changement de titre ANNULE la précédente (la tâche, donc la requête HTTP) ;
/// - Spotify : l'URL vient d'un Apple event (`artwork url`), puis UN SEUL GET HTTPS vers l'hôte autorisé (CDN d'images de
///   Spotify) ; session éphémère, sans cache, sans cookies ; octets gardés en mémoire seulement, jamais écrits sur le disque ;
/// - Apple Music : octets bruts de la pochette par Apple event, jamais d'HTTP.
public enum ArtworkPolicy {
    /// Hôte du CDN d'images de Spotify (valeur observée dans les URL `artwork url` ; NON vérifiée sur un vrai titre ici).
    public static let spotifyImageHost = "i.scdn.co"
    public static let allowedHosts: Set<String> = [spotifyImageHost]
    /// Taille maximale d'une pochette téléchargée.
    public static let maxDownloadBytes = 4 * 1024 * 1024

    /// URL acceptée seulement si https, hôte autorisé, sans identifiants ni port. `extraHosts` : bouclage de l'autotest (DEBUG).
    public static func validated(_ text: String, extraHosts: Set<String> = [], allowInsecureLoopback: Bool = false) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host?.lowercased() else { return nil }
        guard url.user == nil, url.password == nil else { return nil }
        if allowInsecureLoopback, url.scheme == "http", extraHosts.contains(host) { return url }
        guard url.scheme == "https", url.port == nil else { return nil }
        return (allowedHosts.union(extraHosts)).contains(host) ? url : nil
    }
}

public protocol ArtworkTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

/// GET éphémère : `URLSessionConfiguration.ephemeral`, ni cache d'URL, ni cookies, ni identifiants ; réponse en mémoire.
public final class URLSessionArtworkTransport: ArtworkTransport, @unchecked Sendable {
    public enum Failure: Error, Equatable { case badStatus(Int), notImage, tooLarge, redirectRefused }

    private let session: URLSession
    private let delegate: RedirectGuard

    public static func makeConfiguration(userAgent: String, protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 10
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "image/*"]
        if let protocolClasses { c.protocolClasses = protocolClasses }
        return c
    }

    public init(userAgent: String, extraHosts: Set<String> = [], protocolClasses: [AnyClass]? = nil) {
        delegate = RedirectGuard(extraHosts: extraHosts)
        session = URLSession(configuration: Self.makeConfiguration(userAgent: userAgent, protocolClasses: protocolClasses),
                             delegate: delegate, delegateQueue: nil)
    }

    public var configuration: URLSessionConfiguration { session.configuration }

    public func data(from url: URL) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw Failure.badStatus(http.statusCode) }
        if let type = http.value(forHTTPHeaderField: "Content-Type"), !type.lowercased().hasPrefix("image/") { throw Failure.notImage }
        if http.expectedContentLength > Int64(ArtworkPolicy.maxDownloadBytes) { throw Failure.tooLarge }
        var out = Data()
        for try await byte in bytes {
            out.append(byte)
            if out.count > ArtworkPolicy.maxDownloadBytes { throw Failure.tooLarge }
        }
        return out
    }

    /// Une redirection vers un hôte non autorisé est refusée.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let extraHosts: Set<String>
        init(extraHosts: Set<String>) { self.extraHosts = extraHosts }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            if let u = request.url, ArtworkPolicy.validated(u.absoluteString, extraHosts: extraHosts, allowInsecureLoopback: !extraHosts.isEmpty) != nil {
                completionHandler(request)
            } else {
                completionHandler(nil)
            }
        }
    }
}

public enum ArtworkSourceKind: Sendable, Equatable {
    /// Apple Music : octets de la pochette par Apple event.
    case appleMusic
    /// Spotify : URL par Apple event, puis GET.
    case spotify
}

public struct ArtworkProviders: Sendable {
    /// Apple Music : octets bruts de `artwork 1 of current track` (nil si absents ou en erreur).
    public var musicData: @Sendable () async -> Data?
    /// Spotify : `artwork url of current track` (nil si absent ou en erreur).
    public var spotifyURL: @Sendable () async -> String?
    public var transport: ArtworkTransport
    /// Hôtes supplémentaires et http autorisé SEULEMENT pour l'autotest (DEBUG, bouclage).
    public var extraHosts: Set<String>

    public init(musicData: @escaping @Sendable () async -> Data?, spotifyURL: @escaping @Sendable () async -> String?,
                transport: ArtworkTransport, extraHosts: Set<String> = []) {
        self.musicData = musicData; self.spotifyURL = spotifyURL; self.transport = transport; self.extraHosts = extraHosts
    }
}

@MainActor
public final class ArtworkService {
    private let enabled: @MainActor () -> Bool
    private let providers: ArtworkProviders
    private let deliver: @MainActor (String, ArtworkPalette?) -> Void
    private var task: Task<Void, Never>?
    private var currentIdentity: String?

    /// Compteurs (autotest et tests) : demandes acceptées, lectures par Apple event, GET HTTP lancés, tâches annulées, livraisons.
    public private(set) var started = 0
    public private(set) var playerReads = 0
    public private(set) var httpFetches = 0
    public private(set) var cancelled = 0
    public private(set) var delivered = 0
    public private(set) var skippedDisabled = 0
    public private(set) var rejectedURLs = 0

    public init(enabled: @escaping @MainActor () -> Bool, providers: ArtworkProviders,
                deliver: @escaping @MainActor (String, ArtworkPalette?) -> Void) {
        self.enabled = enabled; self.providers = providers; self.deliver = deliver
    }

    public var isBusy: Bool { task != nil }

    /// Nouveau titre : annule toute requête en cours, puis en lance une seule, si le réglage est activé ET que `permitted`
    /// (autorisation Automatisation du lecteur déjà accordée : jamais d'invite provoquée ici).
    public func trackChanged(identity: String, source: ArtworkSourceKind, permitted: Bool) {
        cancel()
        guard enabled() else { skippedDisabled += 1; return }
        guard permitted else { return }
        started += 1
        currentIdentity = identity
        let providers = self.providers
        task = Task { [weak self] in
            var palette: ArtworkPalette?
            switch source {
            case .appleMusic:
                self?.playerReads += 1
                if let data = await providers.musicData(), !Task.isCancelled { palette = await Self.decode(data) }
            case .spotify:
                self?.playerReads += 1
                if let text = await providers.spotifyURL(), !Task.isCancelled {
                    if let url = ArtworkPolicy.validated(text, extraHosts: providers.extraHosts, allowInsecureLoopback: !providers.extraHosts.isEmpty) {
                        self?.httpFetches += 1
                        if let data = try? await providers.transport.data(from: url), !Task.isCancelled { palette = await Self.decode(data) }
                    } else {
                        self?.rejectedURLs += 1
                    }
                }
            }
            guard !Task.isCancelled, let self, self.currentIdentity == identity else { return }
            self.task = nil
            self.delivered += 1
            self.deliver(identity, palette)
        }
    }

    /// Fin de lecture, réglage désactivé : annule sans rien livrer.
    public func cancel() {
        if let task { task.cancel(); cancelled += 1 }
        task = nil
        currentIdentity = nil
    }

    private nonisolated static func decode(_ data: Data) async -> ArtworkPalette? {
        await Task.detached(priority: .utility) { ArtworkDecoder.palette(from: data) }.value
    }
}
