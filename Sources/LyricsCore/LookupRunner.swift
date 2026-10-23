import Foundation

/// Ce que le déroulé d'un titre rapporte pendant qu'il tourne (l'app en fait des états visibles).
public enum LookupEvent: Sendable, Equatable {
    case searching
    /// Fin d'une attente (429, disjoncteur, reprise espacée) : nouvel essai pour le titre courant.
    case retrying
    /// Attente avant un nouvel essai : « Service occupé », nouvel essai dans `retryIn` s (répété chaque seconde).
    case busy(retryIn: Double, reason: String)
    case offline
}

public enum LookupOutcome: Sendable, Equatable {
    case found(Lyrics)
    /// Aucune parole pour ce titre. `definitive` : toutes les requêtes ont abouti (404 ou liste sans candidat) → noté 24 h dans l'index.
    case notFound(reason: String, definitive: Bool)
    /// Erreurs passagères du service (5xx, délai dépassé, 429) qui durent après toutes les reprises automatiques : JAMAIS « indisponible »,
    /// l'écran reste « Service occupé » avec le bouton « Réessayer ».
    case stalled(reason: String)
    case cancelled
}

public enum LookupStep: Sendable, Equatable {
    case getByID(Int)
    case get
    case search(LRCLIBClient.SearchQuery, label: String)

    public var name: String {
        switch self {
        case .getByID: return "get/{id}"
        case .get: return "get"
        case .search(_, let label): return label
        }
    }
    var isGet: Bool { if case .search = self { return false } else { return true } }
}

/// Déroulé de recherche d'UN titre (1.0.1), pur : transport, horloge et attente injectés (testable avec un faux transport et une
/// horloge simulée). Ordre : `get/{id}` (index) si connu, `get` exact, puis `search` avec des requêtes de plus en plus larges :
/// (1) titre sans « feat. / remaster » + artiste tel que donné ; (2) premier artiste si la chaîne en contient plusieurs ;
/// (3) recherche combinée `q` (artiste sans « The ») ; (4) titre court (sans suffixe « - … » ni parenthèse finale).
///
/// Règles :
/// - une erreur du serveur (5xx), un délai dépassé ou une panne de transport sur une requête ne mène JAMAIS à « indisponible » :
///   on passe tout de suite à la requête suivante (espacement de 300 ms seul), puis on RETENTE les requêtes en échec après
///   `Retry-After` (sinon 2 s + aléa), trois fois au plus par tentative ; si cela dure, la tentative s'arrête et une reprise
///   automatique a lieu après 5, 10, 20, 40, 60, 60 s (« Service occupé », compte à rebours) ; ensuite `stalled` (bouton « Réessayer ») ;
/// - 429 : la porte se ferme pour toute l'app jusqu'à `Retry-After` (D8), jamais de repli sur une autre requête pendant ce temps ;
/// - au plus 6 requêtes dans la première tentative, 3 dans chacune des reprises ;
/// - arrêt dès qu'un résultat sûr existe : LRC dont la durée colle (≤ 5 s) ou durée inconnue, instrumental, ou (après un `search`)
///   LRC d'écart ≤ 15 s avec artiste concordant, ou texte seul du bon titre et du bon artiste ; sinon on cumule les candidats et on
///   choisit le meilleur à la fin.
public actor LookupRunner {
    public struct Config: Sendable {
        public var backoff: [Double] = [5, 10, 20, 40, 60, 60]
        public var retryLimit = 3
        public var deferredDefaultWait = RequestGate.defaultServerRetryWait
        public init() {}
    }

    private let client: LRCLIBClient
    private var gate: RequestGate
    private let config: Config
    private let clock: @Sendable () -> Double
    private let sleeper: @Sendable (Double) async -> Void
    private let log: @Sendable ([String: String]) -> Void
    private var onlineWaiters: [CheckedContinuation<Void, Never>] = []

    public init(client: LRCLIBClient, gate: RequestGate, config: Config = Config(),
                clock: @escaping @Sendable () -> Double, sleep: @escaping @Sendable (Double) async -> Void,
                log: @escaping @Sendable ([String: String]) -> Void = { _ in }) {
        self.client = client; self.gate = gate; self.config = config
        self.clock = clock; self.sleeper = sleep; self.log = log
    }

    public var isOffline: Bool { gate.isOffline }

    /// Hors connexion : aucune requête ; au retour, la recherche du titre courant reprend.
    public func setOnline(_ online: Bool) {
        gate.isOffline = !online
        if online {
            let waiters = onlineWaiters
            onlineWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    /// Requêtes prévues pour un titre, dans l'ordre (sans doublon).
    public static func plan(for track: TrackInfo) -> [LookupStep] {
        let title = TrackMatcher.queryTitle(track.title)
        let short = TrackMatcher.shortQueryTitle(track.title)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        var steps: [LookupStep] = [.get]
        if artist.isEmpty {
            steps.append(.search(.combined(title), label: "search (q)"))
            return steps
        }
        let primary = TrackMatcher.primaryArtist(artist)
        steps.append(.search(.fields(title: title, artist: artist), label: "search"))
        if primary != artist { steps.append(.search(.fields(title: title, artist: primary), label: "search (1er artiste)")) }
        steps.append(.search(.combined("\(title) \(TrackMatcher.withoutThe(primary))"), label: "search (q)"))
        if short != title { steps.append(.search(.fields(title: short, artist: primary), label: "search (titre court)")) }
        return steps
    }

    private struct Deferred { var step: LookupStep; var readyAt: Double }

    /// Candidats cumulés au fil des requêtes (par identifiant) et requête qui a livré chacun.
    private final class Collected: @unchecked Sendable {
        private var pool: [Int: LRCLIBRecord] = [:]
        private var via: [Int: String] = [:]
        var count: Int { pool.count }
        func add(_ records: [LRCLIBRecord], via name: String) {
            for r in records { pool[r.id] = r; if via[r.id] == nil { via[r.id] = name } }
        }
        func decision(for track: TrackInfo) -> TrackMatcher.Decision {
            let candidates = pool.values.sorted { $0.id < $1.id }.map { $0.candidate }
            return TrackMatcher.choose(for: track, among: candidates)
        }
        func lyrics(for d: TrackMatcher.Decision, track: TrackInfo) -> Lyrics? {
            guard let c = d.candidate, let record = pool[c.id] else { return nil }
            let origin = via[c.id] ?? "get"
            // `get` : une seule entrée, rien à départager ; `search` : identifiant et score du candidat retenu.
            return LRCLIBClient.lyrics(from: record, for: track, provenance: origin.hasPrefix("get") ? origin : "\(origin), id \(c.id), score \(Int(d.score))")
        }
    }

    public func run(track: TrackInfo, knownID: Int?, report: @escaping @Sendable (LookupEvent) -> Void) async -> LookupOutcome {
        gate.beginTitle(now: clock())
        var fresh: [LookupStep] = (knownID.map { [LookupStep.getByID($0)] } ?? []) + Self.plan(for: track)
        var deferred: [Deferred] = []
        let col = Collected()
        var rounds = 0
        var lastTransient = "service occupé"
        report(.searching)

        func decision() -> TrackMatcher.Decision { col.decision(for: track) }
        func lyrics(for d: TrackMatcher.Decision) -> Lyrics? { col.lyrics(for: d, track: track) }
        /// Résultat sûr : on s'arrête là sans autre requête.
        func isFinal(_ d: TrackMatcher.Decision, after step: LookupStep) -> Bool {
            guard let c = d.candidate else { return false }
            switch d.mode {
            case .instrumental: return true
            case .synced:
                switch TrackMatcher.durationVerdict(track: track.duration, candidate: c.duration) {
                case .unknown, .close: return true
                case .far: return !step.isGet                       // écart toléré (5 à 15 s) : accepté après une recherche seulement
                }
            case .plain:
                // Texte seul : après un `get`, une première recherche tente de trouver un LRC ; après une recherche, si le meilleur candidat
                // est bien le bon titre ET le bon artiste, il n'y a vraisemblablement pas de LRC : on s'arrête (pas 4 requêtes de plus).
                return !step.isGet && TrackMatcher.artistMatches(c.artist, track) && TrackMatcher.titleKey(c.title) == TrackMatcher.titleKey(track.title)
            case .none: return false
            }
        }
        func conclude() -> LookupOutcome {
            let d = decision()
            if let found = lyrics(for: d) {
                log(["lookup": "choix", "resultat": found.isSynced ? "synced" : (found.plainText != nil ? "plain" : "instrumental"),
                     "choix": d.reason, "candidats": "\(col.count)", "provenance": found.provenance])
                return .found(found)
            }
            return .notFound(reason: col.count == 0 ? "aucun candidat (\(d.reason))" : "aucun titre compatible (\(d.reason))", definitive: deferred.isEmpty)
        }

        while !Task.isCancelled {
            switch gate.admit(now: clock()) {
            case .offline:
                report(.offline)
                log(["lookup": "hors-connexion"])
                await waitForOnline()
                continue
            case .busy:
                await sleeper(0.05)
                continue
            case .wait(let seconds):
                await sleeper(seconds)
                continue
            case .closed(let until, let reason):
                await countdown(until: until, reason: reason.rawValue, report: report)
                if Task.isCancelled { return .cancelled }
                gate.beginAttempt(limit: config.retryLimit)
                report(.retrying)
                log(["lookup": "nouvel-essai", "raison": reason.rawValue])
                continue
            case .budgetExhausted, .attemptExhausted:
                if fresh.isEmpty, deferred.isEmpty || (lyrics(for: decision()) != nil && deferred.allSatisfy({ $0.step.isGet })) { return conclude() }
                if lastTransient == "service occupé" { lastTransient = "lenteur ou requêtes épuisées" }
                if let outcome = await endAttempt(&rounds, reason: lastTransient, report: report) { return outcome }
                continue
            case .proceed(let timeout):
                // Prochaine requête : d'abord les neuves, puis les reprises (après leur délai) tant qu'aucun résultat n'existe.
                var step: LookupStep
                if !fresh.isEmpty {
                    step = fresh.removeFirst()
                } else if !deferred.isEmpty {
                    if lyrics(for: decision()) != nil, deferred.allSatisfy({ $0.step.isGet }) { return conclude() }
                    let next = deferred.removeFirst()
                    let wait = next.readyAt - clock()
                    if wait > 0 { await sleeper(wait) }
                    step = next.step
                } else {
                    return conclude()
                }
                let started = clock()
                gate.requestStarted(now: started)
                log(["lookup": "requete", "etape": step.name, "timeout": String(format: "%.1f", timeout)])
                switch await perform(step, track: track, timeout: timeout) {
                case .records(let records):
                    _ = gate.requestFinished(now: clock(), outcome: records.isEmpty ? .notFound : .success)
                    col.add(records, via: step.name)
                    let d = decision()
                    log(["lookup": "reponse", "etape": step.name, "statut": "200", "ms": ms(since: started), "candidats": "\(records.count)", "choix": d.reason])
                    if isFinal(d, after: step) { return conclude() }
                case .notFound:
                    _ = gate.requestFinished(now: clock(), outcome: .notFound)
                    log(["lookup": "reponse", "etape": step.name, "statut": "404", "ms": ms(since: started)])
                case .rateLimited(let retryAfter):
                    let seconds = RequestGate.parseRetryAfter(retryAfter, now: Date())
                    let verdict = gate.requestFinished(now: clock(), outcome: .rateLimited(retryAfter: seconds))
                    log(["lookup": "reponse", "etape": step.name, "statut": "429", "ms": ms(since: started), "retryAfter": retryAfter ?? "", "verdict": describe(verdict)])
                    deferred.insert(Deferred(step: step, readyAt: clock()), at: 0)
                    lastTransient = "429 (service limité)"
                    if case .giveUp = verdict, let outcome = await endAttempt(&rounds, reason: lastTransient, report: report) { return outcome }
                case .server(let status, let retryAfter):
                    let seconds = RequestGate.parseRetryAfter(retryAfter, now: Date())
                    let verdict = gate.requestFinished(now: clock(), outcome: .serverError(status: status, retryAfter: seconds), fallbackAvailable: !fresh.isEmpty)
                    log(["lookup": "reponse", "etape": step.name, "statut": "\(status)", "ms": ms(since: started), "retryAfter": retryAfter ?? "", "verdict": describe(verdict)])
                    deferred.append(Deferred(step: step, readyAt: clock() + (seconds ?? config.deferredDefaultWait)))
                    lastTransient = "erreur \(status) du service"
                    if case .giveUp = verdict, let outcome = await endAttempt(&rounds, reason: lastTransient, report: report) { return outcome }
                case .timeout:
                    let cut = timeout < RequestGate.perRequestTimeout - 0.001
                    let verdict = gate.requestFinished(now: clock(), outcome: cut ? .budgetCut : .timeout, fallbackAvailable: !fresh.isEmpty && !cut)
                    log(["lookup": "reponse", "etape": step.name, "statut": cut ? "coupée par le budget" : "délai dépassé", "ms": ms(since: started), "verdict": describe(verdict)])
                    deferred.append(Deferred(step: step, readyAt: clock() + config.deferredDefaultWait))
                    lastTransient = "délai dépassé"
                    if case .giveUp = verdict, let outcome = await endAttempt(&rounds, reason: lastTransient, report: report) { return outcome }
                case .failure(let text):
                    if Task.isCancelled { _ = gate.requestFinished(now: clock(), outcome: .cancelled); return .cancelled }
                    let verdict = gate.requestFinished(now: clock(), outcome: .transportFailure, fallbackAvailable: !fresh.isEmpty)
                    log(["lookup": "reponse", "etape": step.name, "statut": "panne de transport", "ms": ms(since: started), "erreur": text, "verdict": describe(verdict)])
                    deferred.append(Deferred(step: step, readyAt: clock() + config.deferredDefaultWait))
                    lastTransient = "panne de transport"
                    if case .giveUp = verdict, let outcome = await endAttempt(&rounds, reason: lastTransient, report: report) { return outcome }
                case .invalid:
                    // JSON illisible : traité comme une réponse sans résultat (pas une panne passagère).
                    _ = gate.requestFinished(now: clock(), outcome: .notFound)
                    log(["lookup": "reponse", "etape": step.name, "statut": "200", "ms": ms(since: started), "resultat": "JSON illisible"])
                case .cancelled:
                    _ = gate.requestFinished(now: clock(), outcome: .cancelled)
                    return .cancelled
                }
            }
        }
        return .cancelled
    }

    // MARK: Détails

    private enum StepResult {
        case records([LRCLIBRecord]), notFound, rateLimited(String?), server(Int, String?), timeout, failure(String), invalid, cancelled
    }

    private func perform(_ step: LookupStep, track: TrackInfo, timeout: Double) async -> StepResult {
        do {
            switch step {
            case .getByID(let id): return .records([try await client.get(id: id, timeout: timeout)])
            case .get: return .records([try await client.get(track: track, timeout: timeout)])
            case .search(let query, _): return .records(try await client.search(query, timeout: timeout))
            }
        } catch LRCLIBError.notFound { return .notFound
        } catch LRCLIBError.rateLimited(let retryAfter) { return .rateLimited(retryAfter)
        } catch LRCLIBError.serverError(let status, let retryAfter) { return .server(status, retryAfter)
        } catch LRCLIBError.timeout { return .timeout
        } catch LRCLIBError.invalidJSON { return .invalid
        } catch LRCLIBError.cancelled { return .cancelled
        } catch is CancellationError { return .cancelled
        } catch {
            return Task.isCancelled ? .cancelled : .failure(String(describing: error).prefix(80).description)
        }
    }

    /// Fin d'une tentative sur une erreur passagère : attente (compte à rebours « Service occupé »), puis nouvelle tentative (`nil`).
    /// Rend un résultat si le déroulé doit s'arrêter : annulé, ou reprises épuisées → `stalled`.
    private func endAttempt(_ rounds: inout Int, reason: String, report: @escaping @Sendable (LookupEvent) -> Void) async -> LookupOutcome? {
        rounds += 1
        if rounds > config.backoff.count {
            log(["lookup": "reprises-epuisees", "raison": reason])
            return .stalled(reason: reason)
        }
        let wait = config.backoff[rounds - 1]
        log(["lookup": "reprise-espacee", "tentative": "\(rounds)", "secondes": String(format: "%.0f", wait)])
        await countdown(until: clock() + wait, reason: "reprise", report: report)
        if Task.isCancelled { return .cancelled }
        gate.beginAttempt(limit: config.retryLimit)
        report(.retrying)
        return nil
    }

    /// « Service occupé » : rapporte le temps restant chaque seconde jusqu'à `until`.
    private func countdown(until: Double, reason: String, report: @escaping @Sendable (LookupEvent) -> Void) async {
        log(["lookup": "porte-fermee", "raison": reason, "secondes": String(format: "%.1f", until - clock())])
        while !Task.isCancelled {
            let remaining = until - clock()
            if remaining <= 0.0005 { return }
            report(.busy(retryIn: remaining, reason: reason))
            await sleeper(min(1, remaining))
        }
    }

    private func waitForOnline() async {
        guard gate.isOffline else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in onlineWaiters.append(c) }
    }

    private func ms(since started: Double) -> String { String(Int(((clock() - started) * 1000).rounded())) }

    private func describe(_ v: RequestGate.Verdict) -> String {
        switch v {
        case .proceed: return "continuer"
        case .retry(let after): return String(format: "nouvel essai dans %.1f s", after)
        case .giveUp(let r): return "abandon (\(r.rawValue))"
        }
    }
}
