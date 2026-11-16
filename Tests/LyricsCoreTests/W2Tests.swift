import Testing
import Foundation
@testable import LyricsCore

/// Drapeau posé par une tâche, lu par le test (pour attendre avec une limite de temps au lieu de rester bloqué).
final class DoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var isSet: Bool { lock.withLock { flag } }
}

@Suite("W2 : correctifs du cœur Swift")
struct W2Tests {
    /// Constat 21 : `waitForOnline` n'était pas annulable : après un changement de titre hors connexion, l'ancienne tâche annulée restait
    /// suspendue jusqu'au retour du réseau (fuite).
    @Test("hors connexion : une recherche annulée se termine tout de suite en « cancelled », sans attendre le retour du réseau")
    func waitForOnlineIsCancellable() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport(clock: clock) { _, _ in Wire.ok(Wire.record(id: 1, title: "Phares sur la mer", artist: "Artiste fictif")) }
        let client = LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: transport, userAgent: "Test/0 (test)")
        let runner = LookupRunner(client: client, gate: RequestGate(titlesBeforeBreaker: 3, random: { 0.5 }),
                                  clock: { clock.now }, sleep: { s in clock.advance(s); await Task.yield() })
        await runner.setOnline(false)
        let track = TrackInfo(title: "Phares sur la mer", artist: "Artiste fictif", album: nil, duration: 200, player: "fake")
        let done = DoneFlag()
        let task = Task { () -> LookupOutcome in
            let o = await runner.run(track: track, knownID: nil) { _ in }
            done.set()
            return o
        }
        try? await Task.sleep(for: .milliseconds(100))      // la recherche est maintenant suspendue, hors connexion
        #expect(!done.isSet)
        task.cancel()
        for _ in 0..<100 where !done.isSet { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(done.isSet, "la tâche annulée est restée suspendue hors connexion")
        guard done.isSet else { await runner.setOnline(true); return }      // libère la tâche si le correctif manque
        #expect(await task.value == .cancelled)
        #expect(transport.calls.isEmpty)
    }

    @Test("hors connexion : le retour du réseau reprend toujours la recherche (le correctif ne casse pas la reprise)")
    func waitForOnlineStillResumes() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport(clock: clock) { _, _ in Wire.ok(Wire.record(id: 1, title: "Phares sur la mer", artist: "Artiste fictif")) }
        let client = LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: transport, userAgent: "Test/0 (test)")
        let runner = LookupRunner(client: client, gate: RequestGate(titlesBeforeBreaker: 3, random: { 0.5 }),
                                  clock: { clock.now }, sleep: { s in clock.advance(s); await Task.yield() })
        await runner.setOnline(false)
        let track = TrackInfo(title: "Phares sur la mer", artist: "Artiste fictif", album: nil, duration: 200, player: "fake")
        let a = Task { await runner.run(track: track, knownID: nil) { _ in } }
        let b = Task { await runner.run(track: track, knownID: nil) { _ in } }
        try? await Task.sleep(for: .milliseconds(100))
        await runner.setOnline(true)
        let (oa, ob) = (await a.value, await b.value)
        for o in [oa, ob] { if case .found = o {} else { Issue.record("attendu found, obtenu \(o)") } }
    }
}
