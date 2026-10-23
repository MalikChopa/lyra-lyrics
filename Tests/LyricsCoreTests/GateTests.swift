import Testing
import Foundation
@testable import LyricsCore

/// Chaque branche du §3.5, horloge simulée (`now` en secondes), aléa fixé à 0,5.
@Suite("RequestGate (§3.5)")
struct RequestGateTests {
    func gate() -> RequestGate { RequestGate(random: { 0.5 }) }

    @Test("une requête à la fois")
    func oneAtATime() {
        var g = gate()
        #expect(g.admit(now: 0) == .proceed(timeout: 8))
        g.requestStarted(now: 0)
        #expect(g.admit(now: 1) == .busy)
        #expect(g.requestFinished(now: 1, outcome: .success) == .proceed)
        #expect(g.admit(now: 1.3) == .proceed(timeout: 8))
    }

    @Test("espacement ≥ 300 ms entre deux requêtes")
    func spacing() {
        var g = gate()
        g.requestStarted(now: 10)
        _ = g.requestFinished(now: 10.5, outcome: .notFound)
        #expect(g.admit(now: 10.6) == .wait(0.2))
        #expect(g.admit(now: 10.8) == .proceed(timeout: 8))
    }

    @Test("8 s par requête ; budget de 15 s par titre consommé par la lenteur sans erreur seulement ; coupure → indisponible")
    func budget() {
        var g = gate()
        g.beginTitle()
        g.requestStarted(now: 0); _ = g.requestFinished(now: 7, outcome: .notFound)        // 7 s de lenteur
        #expect(g.admit(now: 7.3) == .proceed(timeout: 8))
        g.requestStarted(now: 7.3); _ = g.requestFinished(now: 14.3, outcome: .success)    // 14 s au total
        #expect(g.admit(now: 14.6) == .proceed(timeout: 1))                                 // min(8, 15 − 14)
        g.requestStarted(now: 14.6); _ = g.requestFinished(now: 15.6, outcome: .budgetCut)
        #expect(g.admit(now: 15.9) == .budgetExhausted)
        #expect(g.breakerTrips == 0)
        g.beginTitle()
        #expect(g.admit(now: 16.2) == .proceed(timeout: 8))
        // un délai dépassé n'est PAS de la lenteur sans erreur : le budget ne bouge pas
        g.requestStarted(now: 16.2); _ = g.requestFinished(now: 24.2, outcome: .timeout)
        #expect(g.budgetUsed == 0)
    }

    @Test("429 avec Retry-After en secondes : attente + aléa, porte fermée pour toute l'app, un seul nouvel essai par titre, budget suspendu")
    func rateLimitedSeconds() {
        var g = gate()
        g.beginTitle()
        g.requestStarted(now: 100)
        #expect(g.requestFinished(now: 107, outcome: .rateLimited(retryAfter: 3)) == .retry(after: 3.5))
        #expect(g.budgetUsed == 0)                                                           // horloge du budget arrêtée
        #expect(g.admit(now: 108) == .closed(until: 110.5, reason: .rateLimited))
        #expect(g.admit(now: 110.5) == .proceed(timeout: 8))
        g.requestStarted(now: 110.5)
        #expect(g.requestFinished(now: 111, outcome: .rateLimited(retryAfter: 2)) == .giveUp(.rateLimitedAgain))
        #expect(g.admit(now: 112) == .closed(until: 113.5, reason: .rateLimited))
        #expect(g.breakerTrips == 2)                                                         // compte dans le disjoncteur
    }

    @Test("429 sans en-tête : 30 s + aléa")
    func rateLimitedDefault() {
        var g = gate()
        g.requestStarted(now: 0)
        #expect(g.requestFinished(now: 1, outcome: .rateLimited(retryAfter: nil)) == .retry(after: 30.5))
        #expect(g.closedUntil == 31.5)
    }

    @Test("Retry-After en date HTTP (IMF-fixdate, RFC 850, asctime), passée → 0, illisible → nil")
    func retryAfterParsing() {
        let now = Date(timeIntervalSince1970: 1_445_412_470)              // 2015-10-21 07:27:50 GMT
        #expect(RequestGate.parseRetryAfter("Wed, 21 Oct 2015 07:28:00 GMT", now: now) == 10)
        #expect(RequestGate.parseRetryAfter("Wednesday, 21-Oct-15 07:28:00 GMT", now: now) == 10)
        #expect(RequestGate.parseRetryAfter("Wed Oct 21 07:28:00 2015", now: now) == 10)
        #expect(RequestGate.parseRetryAfter("Wed, 21 Oct 2015 07:00:00 GMT", now: now) == 0)
        #expect(RequestGate.parseRetryAfter("120", now: now) == 120)
        #expect(RequestGate.parseRetryAfter(" 2.5 ", now: now) == 2.5)
        #expect(RequestGate.parseRetryAfter("bientôt", now: now) == nil)
        #expect(RequestGate.parseRetryAfter(nil, now: now) == nil)
    }

    @Test("503 en série : nouvel essai après 2 s + aléa, puis disjoncteur 30, 60, 120, 240, 300, 300 s")
    func breakerSeries() {
        var g = gate()
        g.beginTitle()
        var now = 0.0
        g.requestStarted(now: now); now += 1
        #expect(g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: nil)) == .retry(after: 2.5))
        #expect(g.admit(now: now + 1) == .wait(1.5))
        now += 2.5
        g.requestStarted(now: now); now += 1
        #expect(g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: nil)) == .giveUp(.serverErrors))
        var pauses: [Double] = []
        if case .closed(let until, let reason) = g.admit(now: now) { pauses.append(until - now); #expect(reason == .breaker) }
        for _ in 0..<5 {
            now = g.closedUntil!
            g.beginAttempt()
            #expect(g.admit(now: now) == .proceed(timeout: 8))
            g.requestStarted(now: now); now += 1
            #expect(g.requestFinished(now: now, outcome: .serverError(status: 502, retryAfter: nil)) == .giveUp(.serverErrors))
            if case .closed(let until, _) = g.admit(now: now) { pauses.append(until - now) }
        }
        #expect(pauses == [30, 60, 120, 240, 300, 300])
    }

    @Test("5xx avec Retry-After : le nouvel essai attend cette valeur ; délai dépassé et panne de transport suivent le même chemin")
    func serverRetryAfter() {
        var g = gate()
        g.requestStarted(now: 0)
        #expect(g.requestFinished(now: 1, outcome: .serverError(status: 503, retryAfter: 1)) == .retry(after: 1))
        var t = gate()
        t.requestStarted(now: 0)
        #expect(t.requestFinished(now: 8, outcome: .timeout) == .retry(after: 2.5))
        t.requestStarted(now: 10.5)
        #expect(t.requestFinished(now: 18.5, outcome: .transportFailure) == .giveUp(.serverErrors))
        #expect(t.closedUntil == 48.5)
    }

    @Test("remise à zéro du disjoncteur au premier succès")
    func resetOnSuccess() {
        var g = gate()
        g.requestStarted(now: 0); _ = g.requestFinished(now: 1, outcome: .serverError(status: 503, retryAfter: nil))
        g.requestStarted(now: 4); _ = g.requestFinished(now: 5, outcome: .serverError(status: 503, retryAfter: nil))
        #expect(g.breakerTrips == 1)
        g.beginTitle()
        g.requestStarted(now: 40); _ = g.requestFinished(now: 41, outcome: .success)
        #expect(g.breakerTrips == 0 && g.closedUntil == nil)
        g.requestStarted(now: 50)
        #expect(g.requestFinished(now: 51, outcome: .serverError(status: 500, retryAfter: nil)) == .retry(after: 2.5))
    }

    @Test("un 429 compte dans le disjoncteur : le 5xx suivant saute directement à la pause de 60 s")
    func rateLimitCountsInBreaker() {
        var g = gate()
        g.beginTitle()
        g.requestStarted(now: 0); _ = g.requestFinished(now: 1, outcome: .rateLimited(retryAfter: 1))
        let reopen = g.closedUntil!
        g.beginAttempt()
        g.requestStarted(now: reopen); _ = g.requestFinished(now: reopen + 1, outcome: .serverError(status: 503, retryAfter: nil))
        #expect(g.closedUntil == reopen + 1 + 60)
    }

    @Test("hors connexion : aucune requête ; au plus 3 requêtes par tentative")
    func offlineAndCap() {
        var g = gate()
        g.isOffline = true
        #expect(g.admit(now: 0) == .offline)
        g.isOffline = false
        g.beginTitle()
        for i in 0..<3 {
            let now = Double(i)
            #expect(g.admit(now: now) == .proceed(timeout: 8))
            g.requestStarted(now: now); _ = g.requestFinished(now: now + 0.1, outcome: .notFound)
        }
        #expect(g.admit(now: 10) == .attemptExhausted)
        g.beginAttempt()
        #expect(g.admit(now: 10) == .proceed(timeout: 8))
    }

    @Test("J4 : avec titlesBeforeBreaker = 3, un titre en 5xx est abandonné après 3 essais sans fermer la porte ; le disjoncteur attend 3 titres différents")
    func breakerNeedsSeveralTitles() {
        var g = RequestGate(titlesBeforeBreaker: 3, random: { 0.5 })
        var now = 0.0
        for title in 1...3 {
            g.beginTitle()
            g.requestStarted(now: now); now += 1
            #expect(g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: 1)) == .retry(after: 1))
            now += 1
            g.requestStarted(now: now); now += 1
            #expect(g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: 1)) == .retry(after: 1))
            now += 1
            g.requestStarted(now: now); now += 1
            let verdict = g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: 1))
            #expect(verdict == .giveUp(.serverErrors))
            if title < 3 { #expect(g.closedUntil == nil); g.beginTitle(); #expect(g.admit(now: now + 1) == .proceed(timeout: 8)) }
            else { #expect(g.closedUntil == now + 30) }
        }
    }

    @Test("J4 : un succès ou un 404 entre deux titres en échec remet le compte de titres à zéro")
    func failedTitlesResetOnSuccess() {
        var g = RequestGate(titlesBeforeBreaker: 3, random: { 0.5 })
        var now = 0.0
        for _ in 0..<2 {
            g.beginTitle()
            for _ in 0..<3 { g.requestStarted(now: now); now += 1; _ = g.requestFinished(now: now, outcome: .serverError(status: 503, retryAfter: 1)); now += 1 }
        }
        #expect(g.failedTitlesInARow == 2)
        g.beginTitle(); g.requestStarted(now: now); now += 1; _ = g.requestFinished(now: now, outcome: .notFound)
        #expect(g.failedTitlesInARow == 0 && g.closedUntil == nil)
    }
}
