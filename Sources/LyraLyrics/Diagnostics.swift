import AppKit
import AppSupport
import LyricsCore

/// Drapeaux de diagnostic : présents UNIQUEMENT dans les builds DEBUG (absents de la version publiée, D12).
#if DEBUG
@MainActor var probeMode: ProbeMode?
@MainActor var selftestRunner: SelftestRunner?
@MainActor var snapshotRunner: SnapshotRunner?
@MainActor var e2eMeasure: E2EMeasure?
#endif

enum Diagnostics {
    #if DEBUG
    static func value(of flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    #endif

    /// Les vrais lecteurs sont branchés, sauf en DEBUG quand un faux lecteur, une sonde, des aperçus ou `--no-players` les remplacent.
    static var usesRealPlayers: Bool {
        #if DEBUG
        let args = CommandLine.arguments
        return !args.contains("--fake-player") && !args.contains("--probe-players") && !args.contains("--snapshot") && !args.contains("--no-players")
        #else
        return true
        #endif
    }

    /// `UserDefaults.standard` ; en DEBUG, `--defaults-suite <nom>` isole les essais des préférences de l'utilisateur.
    @MainActor
    static func userDefaults() -> UserDefaults {
        #if DEBUG
        if CommandLine.arguments.contains("--snapshot") { SnapshotFlags.skipBlur = true }
        var suiteName = value(of: "--defaults-suite")
        // Les captures partent toujours d'un jeu de préférences neuf, jamais de celles de l'utilisateur.
        if suiteName == nil, CommandLine.arguments.contains("--snapshot") { suiteName = "pf.j2.snapshot" }
        if let suite = suiteName, let d = UserDefaults(suiteName: suite) {
            if CommandLine.arguments.contains("--snapshot") { d.removePersistentDomain(forName: suite) }
            if CommandLine.arguments.contains("--reset-defaults") { d.removePersistentDomain(forName: suite) }
            return d
        }
        #endif
        return .standard
    }

    /// Service des paroles. Version publiée : `URLSession` éphémère vers lrclib.net, et rien d'autre. DEBUG seulement :
    /// `--lyrics-endpoint http://127.0.0.1:<port>` (bouclage obligatoire) = faux serveur ; `--fake-player` sans endpoint =
    /// transport en processus (catalogue de fixtures, aucun réseau).
    @MainActor
    static func makeLyricsService(defaults: UserDefaults) -> (service: LyricsService, usesNetwork: Bool) {
        let hasher = LyricsService.saltedHasher(defaults: defaults)
        let indexURL = LyricsService.defaultIndexURL()
        let agent = LyricsService.userAgent
        #if DEBUG
        let log: @Sendable ([String: String]) -> Void = { record in
            DiagLog.shared.write(record)
            var r: [String: Any] = ["ev": "service"]
            r.merge(record) { a, _ in a }
            E2ESink.shared.write(r)           // no-op hors `--measure-e2e` ; étapes, statuts et durées seulement, jamais de paroles
        }
        if let endpoint = value(of: "--lyrics-endpoint") {
            guard let url = URL(string: endpoint), url.host == "127.0.0.1" || url.host == "localhost" else {
                FileHandle.standardError.write(Data("--lyrics-endpoint : seul http://127.0.0.1:<port> est accepté\n".utf8))
                exit(64)
            }
            let client = LRCLIBClient(baseURL: url, transport: URLSessionTransport(userAgent: agent), userAgent: agent)
            return (LyricsService(client: client, indexURL: indexURL, hasher: hasher, log: log), false)
        }
        if CommandLine.arguments.contains("--fake-player"), let transport = InProcessFakeTransport.fromCatalog() {
            let client = LRCLIBClient(baseURL: URL(string: "http://127.0.0.1:0")!, transport: transport, userAgent: agent)
            return (LyricsService(client: client, indexURL: indexURL, hasher: hasher, log: log), false)
        }
        #else
        let log: @Sendable ([String: String]) -> Void = { _ in }
        #endif
        let client = LRCLIBClient(transport: URLSessionTransport(userAgent: agent), userAgent: agent)
        // Vrai serveur : le disjoncteur ne s'ouvre qu'après 3 titres différents en échec de suite (mesure J4, voir RequestGate).
        return (LyricsService(client: client, indexURL: indexURL, hasher: hasher, titlesBeforeBreaker: 3, log: log), true)
    }

    @MainActor
    static func applyLaunchArguments(_ controller: AppController) {
        #if DEBUG
        let args = CommandLine.arguments
        if let probe = ProbeMode(args: args) {
            probeMode = probe
            probe.run()
        }
        if let i = args.firstIndex(of: "--exit-after"), i + 1 < args.count, let seconds = Double(args[i + 1]), seconds >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                NSApp.terminate(nil)
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("pf.debug.quit"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        DiagLog.shared.open(path: value(of: "--diagnostics"))
        controller.model.diag = { DiagLog.shared.write($0) }
        // Faux lecteur, autotest, aperçus : l'app n'ouvre JAMAIS les Réglages Système (l'ouverture demandée est seulement notée).
        if args.contains("--fake-player") || args.contains("--selftest") || args.contains("--snapshot") {
            controller.urlOpener = { url in DiagLog.shared.write(["event": "open-url", "url": url.absoluteString, "ouverte": false]) }
        }
        if let name = value(of: "--fake-player") {
            if let scenario = FakeScenario.load(name) {
                let source = FakePlayerSource(scenario: scenario)
                controller.fakePlayer = source
                controller.model.usesFakePlayer = true
                controller.model.diagMayLogTitles = true          // titres inventés seulement (§3.2)
                let stream = source.events
                Task { @MainActor in for await event in stream { controller.model.ingest(event) } }
                source.start()
                DiagLog.shared.write(["event": "fake-player", "scenario": scenario.name, "tracks": scenario.tracks.count,
                                      "endpoint": value(of: "--lyrics-endpoint") ?? "en processus"])
            } else {
                DiagLog.shared.write(["event": "fake-player-introuvable", "scenario": name])
            }
        }
        if let measure = E2EMeasure(args: args, controller: controller) {
            e2eMeasure = measure
            measure.start()
        }
        if let script = value(of: "--selftest") {
            let runner = SelftestRunner(controller: controller)
            selftestRunner = runner
            runner.run(scriptPath: script)
        } else if let dir = value(of: "--snapshot") {
            let runner = SnapshotRunner(controller: controller)
            snapshotRunner = runner
            runner.run(directory: dir)
        }
        #endif
    }
}
