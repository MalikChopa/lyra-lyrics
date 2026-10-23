import Foundation

/// Porte des requêtes LRCLIB (§3.5, valeurs délégué). Machine à états pure (horloge injectée en secondes monotones) :
/// une requête à la fois ; ≥ 300 ms entre deux ; au plus 6 requêtes par tentative (1.0.1 ; 3 avant) ; 8 s par requête ; budget de 15 s par
/// titre pour la lenteur sans erreur seulement (son horloge s'arrête dès un 429/503) ; 429 → `Retry-After` (secondes ou
/// date HTTP) + aléa 0–1 s, sinon 30 s, porte fermée pour toute l'app, un seul nouvel essai par tentative, compte dans le
/// disjoncteur ; 503/5xx/délai → (1.0.1) si une autre voie existe (`get` → `search`) on y passe tout de suite (espacement seul),
/// sinon un nouvel essai après `Retry-After` (sinon 2 s + aléa), trois au plus par tentative, puis disjoncteur
/// [10, 20, 40, 60, 120, 120…] s (30 à 300 s avant 1.0.1) ; un nouveau titre ramène une pause de disjoncteur à 5 s au plus
/// (essai de reprise) ; remise à zéro au premier succès ; hors connexion → aucune requête.
public struct RequestGate: Sendable {
    public static let minSpacing = 0.3
    public static let perRequestTimeout = 8.0
    public static let titleBudget = 15.0
    public static let maxRequestsPerAttempt = 6
    /// Nouveaux essais d'une même requête après une erreur du serveur, par tentative.
    public static let maxServerAttempts = 3
    /// Un nouveau titre ramène une pause de disjoncteur à cette durée au plus (essai de reprise).
    public static let halfOpenAfter = 5.0
    public static let defaultRateLimitWait = 30.0
    public static let defaultServerRetryWait = 2.0
    public static let breakerPauses: [Double] = [10, 20, 40, 60, 120]

    public enum ClosedReason: String, Sendable, Equatable { case rateLimited, breaker }

    public enum Admission: Sendable, Equatable {
        case proceed(timeout: Double)
        /// Espacement ou nouvel essai : rappeler `admit` après ce délai.
        case wait(Double)
        /// Porte fermée pour toute l'app (429 ou disjoncteur) → « Service occupé, nouvel essai dans N s ».
        case closed(until: Double, reason: ClosedReason)
        case offline
        case busy
        /// 15 s de lenteur sans erreur → « Paroles indisponibles ».
        case budgetExhausted
        /// Le nombre de requêtes de cette tentative est atteint (6 la première fois).
        case attemptExhausted
    }

    public enum Outcome: Sendable, Equatable {
        case success
        case notFound
        /// Requête coupée par le budget de 15 s (lenteur sans erreur) : pas une panne, le budget est simplement épuisé.
        case budgetCut
        /// Requête annulée (changement de titre) : sans effet sur le budget et le disjoncteur.
        case cancelled
        case rateLimited(retryAfter: Double?)
        case serverError(status: Int, retryAfter: Double?)
        case timeout
        case transportFailure
    }

    public enum GiveUpReason: String, Sendable, Equatable { case rateLimitedAgain, serverErrors }

    public enum Verdict: Sendable, Equatable {
        /// Continuer la séquence (get → search…).
        case proceed
        /// Refaire la même requête après ce délai (la porte le fait aussi respecter par `admit`).
        case retry(after: Double)
        /// Abandonner ce titre pour cette tentative (la porte peut rester fermée : voir `closedUntil`).
        case giveUp(GiveUpReason)
    }

    /// Réglage mesuré à J4 sur le VRAI serveur : un 503 « The server is busy » (`Retry-After: 1`, ~1,1 s) est le plus souvent propre à UNE
    /// requête (le même titre repasse en 200 au 2e ou 3e essai, un autre titre répond en 0,1 s), pas une panne : avec une valeur > 1, un
    /// titre qui échoue 3 fois en 5xx est abandonné SANS fermer la porte, et le disjoncteur ne s'ouvre qu'après autant de titres DIFFÉRENTS
    /// en échec de suite. Valeur 1 = comportement initial du §3.5 (fermeture dès le 2e échec du même titre).
    public let titlesBeforeBreaker: Int
    /// Espacement minimal entre deux requêtes (300 ms par défaut ; la commande de contrôle `--lookup-check` impose 1,05 s).
    public let minSpacing: Double
    public private(set) var failedTitlesInARow = 0
    public var isOffline = false
    public private(set) var inFlight = false
    /// Prochain instant admissible (espacement de 300 ms, délai de nouvel essai).
    public private(set) var notBefore: Double = 0
    public private(set) var closedUntil: Double?
    public private(set) var closedReason: ClosedReason?
    /// Pauses du disjoncteur déclenchées depuis le dernier succès (un 429 compte aussi).
    public private(set) var breakerTrips = 0
    public private(set) var consecutiveFailures = 0
    // Par titre / par tentative
    public private(set) var attemptRequests = 0
    public private(set) var budgetUsed: Double = 0
    public private(set) var rateLimitRetries = 0
    public private(set) var serverRetries = 0
    /// Limite de requêtes de la tentative en cours (6 pour la première, moins pour les reprises espacées).
    public private(set) var requestLimit = RequestGate.maxRequestsPerAttempt
    /// Ce titre a déjà compté comme « titre en échec » pour le disjoncteur (une seule fois, même après plusieurs tentatives).
    private var titleFailureCounted = false
    private var requestStart: Double?
    private let random: @Sendable () -> Double

    /// `random` : aléa dans [0, 1) ajouté aux attentes (injectable pour les tests).
    public init(titlesBeforeBreaker: Int = 1, minSpacing: Double = RequestGate.minSpacing,
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.titlesBeforeBreaker = max(1, titlesBeforeBreaker)
        self.minSpacing = max(RequestGate.minSpacing, minSpacing)
        self.random = random
    }

    /// Nouveau titre : budget, compteurs d'essais et de requêtes remis à zéro (la fermeture de la porte, elle, reste).
    /// Avec `now` : une pause de disjoncteur en cours est ramenée à `halfOpenAfter` s au plus (essai de reprise pour ce titre ; un 429
    /// n'est jamais raccourci : `Retry-After` est respecté).
    public mutating func beginTitle(now: Double? = nil) {
        attemptRequests = 0; budgetUsed = 0; rateLimitRetries = 0; serverRetries = 0; requestStart = nil
        requestLimit = Self.maxRequestsPerAttempt; titleFailureCounted = false
        if let now, closedReason == .breaker, let until = closedUntil, until - now > Self.halfOpenAfter {
            closedUntil = now + Self.halfOpenAfter
            notBefore = min(notBefore, now + Self.halfOpenAfter)
        }
    }

    /// Nouvelle tentative pour le même titre (après une fermeture ou une attente espacée) : budget, compte de requêtes et d'essais
    /// serveur remis à zéro ; `limit` requêtes au plus.
    public mutating func beginAttempt(limit: Int = RequestGate.maxRequestsPerAttempt) {
        attemptRequests = 0; budgetUsed = 0; requestStart = nil; serverRetries = 0
        requestLimit = max(1, limit)
    }

    /// Arrondi au millième (les instants simulés ou réels en secondes accumulent des erreurs flottantes).
    public var remainingBudget: Double { max(0, ((Self.titleBudget - budgetUsed) * 1000).rounded() / 1000) }

    public mutating func admit(now: Double) -> Admission {
        if isOffline { return .offline }
        if inFlight { return .busy }
        if let until = closedUntil {
            if now < until { return .closed(until: until, reason: closedReason ?? .breaker) }
            closedUntil = nil; closedReason = nil
        }
        let remaining = remainingBudget
        if remaining <= 0.001 { return .budgetExhausted }
        if attemptRequests >= requestLimit { return .attemptExhausted }
        if notBefore - now > 0.0005 { return .wait(((notBefore - now) * 1000).rounded() / 1000) }
        return .proceed(timeout: min(Self.perRequestTimeout, remaining))
    }

    public mutating func requestStarted(now: Double) {
        inFlight = true
        requestStart = now
        attemptRequests += 1
    }

    /// `fallbackAvailable` : une autre voie existe pour ce titre (`get` en panne → `search`) ; une erreur du serveur n'attend alors
    /// pas `Retry-After` (seul l'espacement de 300 ms joue) et ne compte pas comme un essai de cette requête.
    public mutating func requestFinished(now: Double, outcome: Outcome, fallbackAvailable: Bool = false) -> Verdict {
        inFlight = false
        let duration = max(0, now - (requestStart ?? now))
        requestStart = nil
        notBefore = now + minSpacing
        switch outcome {
        case .success, .notFound:
            budgetUsed += duration                 // seule la lenteur sans erreur consomme le budget
            breakerTrips = 0; consecutiveFailures = 0; failedTitlesInARow = 0
            closedUntil = nil; closedReason = nil
            return .proceed
        case .budgetCut:
            budgetUsed = Self.titleBudget          // épuisé ; ni panne ni disjoncteur
            return .proceed
        case .cancelled:
            return .proceed                        // changement de titre : ni budget, ni panne
        case .rateLimited(let retryAfter):
            consecutiveFailures += 1
            breakerTrips += 1                      // compte dans le disjoncteur
            rateLimitRetries += 1
            let wait = (retryAfter ?? Self.defaultRateLimitWait) + random()
            closedUntil = now + wait; closedReason = .rateLimited; notBefore = now + wait
            return rateLimitRetries > 1 ? .giveUp(.rateLimitedAgain) : .retry(after: wait)
        case .serverError(_, let retryAfter):
            return serverFailure(now: now, retryAfter: retryAfter, fallbackAvailable: fallbackAvailable)
        case .timeout, .transportFailure:
            return serverFailure(now: now, retryAfter: nil, fallbackAvailable: fallbackAvailable)
        }
    }

    private mutating func serverFailure(now: Double, retryAfter: Double?, fallbackAvailable: Bool) -> Verdict {
        consecutiveFailures += 1
        if fallbackAvailable {
            notBefore = now + minSpacing
            return .proceed
        }
        serverRetries += 1
        if titlesBeforeBreaker > 1 {
            if serverRetries < Self.maxServerAttempts {             // 3 essais au plus par tentative
                let wait = retryAfter ?? (Self.defaultServerRetryWait + random())
                notBefore = now + wait
                return .retry(after: wait)
            }
            if !titleFailureCounted { failedTitlesInARow += 1; titleFailureCounted = true }
            if failedTitlesInARow < titlesBeforeBreaker { return .giveUp(.serverErrors) }   // la porte reste ouverte
        } else if breakerTrips == 0 && serverRetries == 1 {
            let wait = retryAfter ?? (Self.defaultServerRetryWait + random())
            notBefore = now + wait
            return .retry(after: wait)
        }
        let pause = Self.breakerPauses[min(breakerTrips, Self.breakerPauses.count - 1)]
        breakerTrips += 1
        closedUntil = now + pause; closedReason = .breaker; notBefore = now + pause
        return .giveUp(.serverErrors)
    }

    // MARK: Retry-After

    /// `Retry-After` en secondes (entier ou décimal) ou en date HTTP (IMF-fixdate, RFC 850, asctime) → secondes d'attente.
    public static func parseRetryAfter(_ value: String?, now: Date) -> Double? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if let seconds = Double(v) { return max(0, seconds) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            f.dateFormat = format
            if let date = f.date(from: v) { return max(0, date.timeIntervalSince(now)) }
        }
        return nil
    }
}
