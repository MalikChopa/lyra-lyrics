import Foundation
import AppKit
import Testing
@testable import PlayerKit

// Toutes les valeurs ci-dessous sont INVENTÉES (D10). Les clés sont celles mesurées en J1 sur macOS 27.0.1.

@MainActor
final class CountingBackend: ScriptBackend {
    var calls = 0
    var results: [Result<[ScriptValue], ScriptError>] = []
    func execute(_ request: ReadRequest) async -> Result<[ScriptValue], ScriptError> {
        calls += 1
        return results.isEmpty ? .success([.string("playing")]) : results.removeFirst()
    }
}

@MainActor
struct FakePresence: PlayerPresence {
    var running: Bool
    func isRunning(_ player: PlayerID) -> Bool { running }
}

@Suite("PlayerKit J1")
struct PlayerKitTests {
    @Test("notification Spotify : clés mesurées, durée en ms convertie en s")
    func spotifyNotification() throws {
        let userInfo: [AnyHashable: Any] = [
            "Album": "Album inventé", "Album Artist": "Artiste inventé", "Artist": "Artiste inventé",
            "Disc Number": 1, "Duration": 200_000, "Has Artwork": true, "Name": "Titre inventé",
            "Play Count": 0, "Playback Position": 12.5, "Player State": "Playing", "Popularity": 50,
            "Track ID": "spotify:track:INVENTE0000000000000", "Track Number": 3,
        ]
        let reading = try #require(SpotifyNotificationParser.parse(userInfo: userInfo))
        #expect(reading.player == .spotify)
        #expect(reading.state == .playing)
        #expect(reading.positionSeconds == 12.5)
        #expect(reading.track?.durationSeconds == 200)
        #expect(reading.track?.name == "Titre inventé")
        #expect(reading.track?.trackID == "spotify:track:INVENTE0000000000000")
        #expect(SpotifyNotificationParser.parse(userInfo: ["Player State": "Paused"])?.track == nil)
        #expect(SpotifyNotificationParser.parse(userInfo: ["Player State": "???"]) == nil)
        #expect(SpotifyNotificationParser.parse(userInfo: [:]) == nil)
    }

    @Test("codes d'erreur Apple events du §3.2")
    func errorCodes() {
        #expect(ScriptError.from(code: -1743) == .denied)
        #expect(ScriptError.from(code: -1744) == .consentRequired)
        #expect(ScriptError.from(code: -600) == .notRunning)
        #expect(ScriptError.from(code: -609) == .notRunning)
        #expect(ScriptError.from(code: -1728) == .objectNotFound)
        #expect(ScriptError.from(code: -1712) == .timedOut)
        #expect(ScriptError.from(code: -50) == .other(-50))
        #expect(ScriptError.timedOut.code == -1712)
        #expect(PermissionProbe.map(OSStatus: 0) == .granted)
        #expect(PermissionProbe.map(OSStatus: -1743) == .denied)
        #expect(PermissionProbe.map(OSStatus: -1744) == .notDetermined)
        #expect(PermissionProbe.map(OSStatus: -600) == .notRunning)
    }

    @Test("relevé AppleScript : durée Spotify en ms, Music en s, titre illisible, durée facultative")
    func parseReadings() throws {
        let spotify: [ScriptValue] = [.string("playing"), .double(10.25), .string("N"), .string("A"), .string("Al"), .double(180_000), .string("spotify:track:X"), .int(0)]
        let s = try PlayerScripts.parseReading(player: .spotify, values: spotify).get()
        #expect(s.track?.durationSeconds == 180)
        #expect(s.positionSeconds == 10.25)
        #expect(!s.trackUnreadable)
        let music: [ScriptValue] = [.string("playing"), .double(5), .string("N"), .string("A"), .string("Al"), .double(215.5), .string("ABCD"), .int(0)]
        #expect(try PlayerScripts.parseReading(player: .music, values: music).get().track?.durationSeconds == 215.5)
        let streaming: [ScriptValue] = [.string("playing"), .double(5), .string(""), .string(""), .string(""), .string(""), .string(""), .int(-1728)]
        let u = try PlayerScripts.parseReading(player: .music, values: streaming).get()
        #expect(u.trackUnreadable)
        #expect(u.track == nil)
        let noDuration: [ScriptValue] = [.string("paused"), .double(1), .string("N"), .string("A"), .string(""), .string(""), .string("Z"), .int(0)]
        let n = try PlayerScripts.parseReading(player: .music, values: noDuration).get()
        #expect(n.track?.durationSeconds == nil)
        #expect(n.state == .paused)
        #expect(PlayerScripts.parseReading(player: .music, values: [.string("playing")]) == .failure(.invalidResult))
    }

    @MainActor
    @Test("aucun Apple event quand le lecteur n'est pas lancé")
    func noAppleEventWhenAbsent() async {
        let backend = CountingBackend()
        let executor = ScriptExecutor(backend: backend)
        let spotify = SpotifySource(executor: executor, presence: FakePresence(running: false), permission: { _ in .granted })
        let music = MusicSource(executor: executor, presence: FakePresence(running: false), permission: { _ in .granted })
        for _ in 0..<5 { await spotify.pollNow(); await music.pollNow() }
        #expect(backend.calls == 0)
        #expect(executor.sentCount == 0)
    }

    @MainActor
    @Test("lecteur présent mais autorisation non accordée : aucun relevé ; accordée : un relevé")
    func permissionGate() async {
        let backend = CountingBackend()
        let executor = ScriptExecutor(backend: backend)
        let denied = SpotifySource(executor: executor, presence: FakePresence(running: true), permission: { _ in .notDetermined })
        let deniedMusic = MusicSource(executor: executor, presence: FakePresence(running: true), permission: { _ in .denied })
        await denied.pollNow(); await deniedMusic.pollNow()
        #expect(backend.calls == 0)
        let granted = SpotifySource(executor: executor, presence: FakePresence(running: true), permission: { _ in .granted })
        await granted.pollNow()
        #expect(backend.calls == 1)
    }

    @MainActor
    @Test("trois délais dépassés de suite : relevés suspendus 30 s, puis reprise")
    func suspension() async {
        let backend = CountingBackend()
        backend.results = [.failure(.timedOut), .failure(.timedOut), .failure(.timedOut)]
        var clock = ContinuousClock.now
        let executor = ScriptExecutor(backend: backend, now: { clock })
        for _ in 0..<3 { let r = await executor.run(.full(.spotify)); #expect(r == .failure(.timedOut)) }
        #expect(backend.calls == 3)
        #expect(await executor.run(.full(.spotify)) == .failure(.suspended))
        #expect(backend.calls == 3)
        clock += .seconds(31)
        #expect(await executor.run(.full(.spotify)) == .success([.string("playing")]))
        #expect(backend.calls == 4)
    }

    @MainActor
    final class PresenceBox: PlayerPresence {
        var running = true
        func isRunning(_ player: PlayerID) -> Bool { running }
    }

    @MainActor
    @Test("lecteur quitté en cours de lecture : « stopped », puis plus aucun Apple event")
    func playerQuitWhilePlaying() async {
        let music: [ScriptValue] = [.string("playing"), .double(5), .string("Titre inventé"), .string("Artiste inventé"), .string("Album"), .double(200), .string("ID"), .int(0)]
        let backend = CountingBackend()
        backend.results = [.success(music), .success(music)]
        let executor = ScriptExecutor(backend: backend)
        let presence = PresenceBox()
        let source = MusicSource(executor: executor, presence: presence, permission: { _ in .granted })
        var iterator = source.events.makeAsyncIterator()
        await source.pollNow()
        guard case .trackChanged(let r)? = await iterator.next() else { Issue.record("trackChanged attendu"); return }
        #expect(r.state == .playing)
        #expect(backend.calls == 1)
        presence.running = false                          // l'utilisateur quitte Musique
        await source.pollNow()
        guard case .stopped(.music)? = await iterator.next() else { Issue.record("stopped attendu"); return }
        let callsAtQuit = backend.calls
        for _ in 0..<10 { await source.pollNow() }
        #expect(backend.calls == callsAtQuit)             // aucun Apple event après la sortie du lecteur
        #expect(executor.sentCount == callsAtQuit)
    }

    @MainActor
    @Test("Spotify quitté en cours de lecture (notification puis sortie) : « stopped » et aucun relevé")
    func spotifyQuitWhilePlaying() async {
        let backend = CountingBackend()
        let presence = PresenceBox()
        let source = SpotifySource(executor: ScriptExecutor(backend: backend), presence: presence, permission: { _ in .granted })
        var iterator = source.events.makeAsyncIterator()
        let reading = PlayerReading(player: .spotify, state: .playing, positionSeconds: 3,
                                    track: PlayerTrack(name: "Titre inventé", artist: "Artiste inventé", durationSeconds: 100, trackID: "id"))
        source.handleNotification(reading)
        guard case .trackChanged? = await iterator.next() else { Issue.record("trackChanged attendu"); return }
        presence.running = false
        for _ in 0..<5 { await source.pollNow() }
        guard case .stopped(.spotify)? = await iterator.next() else { Issue.record("stopped attendu"); return }
        #expect(backend.calls == 0)
    }
}

@Suite("Fonctions 1.0 : commandes de lecture")
struct PlaybackCommandTests {
    @Test("codes d'événements relus dans les .sdef : Music hook + Prev/PlPs/Next, Spotify spfy + Prev/PlPs/Next")
    func codes() {
        #expect(PlaybackCommand.previous.eventCodes(for: .music) == ("hook", "Prev"))
        #expect(PlaybackCommand.playPause.eventCodes(for: .music) == ("hook", "PlPs"))
        #expect(PlaybackCommand.next.eventCodes(for: .music) == ("hook", "Next"))
        #expect(PlaybackCommand.previous.eventCodes(for: .spotify) == ("spfy", "Prev"))
        #expect(PlaybackCommand.playPause.eventCodes(for: .spotify) == ("spfy", "PlPs"))
        #expect(PlaybackCommand.next.eventCodes(for: .spotify) == ("spfy", "Next"))
        for c in PlaybackCommand.allCases { for p in PlayerID.allCases { let k = c.eventCodes(for: p); #expect(k.eventClass.utf8.count == 4 && k.eventID.utf8.count == 4) } }
    }
    @Test("noms AppleScript et libellés VoiceOver")
    func names() {
        #expect(PlaybackCommand.allCases.map(\.scriptName) == ["previous track", "playpause", "next track"])
        #expect(PlaybackCommand.allCases.allSatisfy { !$0.accessibilityLabel.isEmpty })
    }
    @Test("lecteur non lancé : l'envoi échoue sans rien lancer (adressage par processus)")
    func notRunning() {
        // Aucun Apple event vers un vrai lecteur dans les tests : si le lecteur n'est pas lancé, `send` répond .notRunning sans envoi.
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: PlayerID.music.bundleID).isEmpty
        if !running {
            if case .failure(let e) = AppleEventClient().send(.playPause, to: .music) { #expect(e == .notRunning) } else { Issue.record("envoi inattendu") }
        }
    }
}
