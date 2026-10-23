import Foundation
import AppKit

/// Transport « à la main » : un Apple event `core/getd` construit sans AppleScript, avec délai.
/// Sans état, `Sendable` : utilisable hors du fil principal (c'est son intérêt, mesure 5 de J1).
/// `path` = suite de codes de propriétés de l'extérieur vers l'intérieur, ex. [pTrk, pnam] = « name of current track ».
public struct AppleEventClient: Sendable {
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 1) { self.timeout = timeout }

    public static func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(FourCharCode(0)) { ($0 << 8) | FourCharCode($1) }
    }

    public func read(player: PlayerID, path: [String]) -> Result<ScriptValue, ScriptError> {
        // Cible = PROCESSUS en cours (pas l'identifiant de bundle) : un Apple event adressé par identifiant de bundle peut RELANCER
        // le lecteur s'il vient de quitter entre la vérification de présence et l'envoi (J5, enquête « Musique »). Adressé par PID,
        // il échoue (-600) sans jamais lancer quoi que ce soit.
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).first(where: { !$0.isTerminated }) else {
            return .failure(.notRunning)
        }
        let target = NSAppleEventDescriptor(processIdentifier: running.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: Self.fourCC("core"), eventID: Self.fourCC("getd"), targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        var container = NSAppleEventDescriptor.null()
        for code in path {
            guard let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier) else { return .failure(.invalidResult) }
            if let hash = code.firstIndex(of: "#"), let n = Int32(code[code.index(after: hash)...]) {
                // « cArt#1 » = élément n° 1 de la classe cArt (« artwork 1 of … »), forme « indx ».
                spec.setDescriptor(NSAppleEventDescriptor(typeCode: Self.fourCC(String(code[..<hash]))), forKeyword: Self.fourCC("want"))
                spec.setDescriptor(container, forKeyword: Self.fourCC("from"))
                spec.setDescriptor(NSAppleEventDescriptor(enumCode: Self.fourCC("indx")), forKeyword: Self.fourCC("form"))
                spec.setDescriptor(NSAppleEventDescriptor(int32: n), forKeyword: Self.fourCC("seld"))
            } else {
                spec.setDescriptor(NSAppleEventDescriptor(typeCode: Self.fourCC("prop")), forKeyword: Self.fourCC("want"))
                spec.setDescriptor(container, forKeyword: Self.fourCC("from"))
                spec.setDescriptor(NSAppleEventDescriptor(enumCode: Self.fourCC("prop")), forKeyword: Self.fourCC("form"))
                spec.setDescriptor(NSAppleEventDescriptor(typeCode: Self.fourCC(code)), forKeyword: Self.fourCC("seld"))
            }
            container = spec
        }
        event.setParam(container, forKeyword: Self.fourCC("----"))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
            if let errn = reply.paramDescriptor(forKeyword: Self.fourCC("errn")), errn.int32Value != 0 {
                return .failure(ScriptError.from(code: Int(errn.int32Value)))
            }
            guard let direct = reply.paramDescriptor(forKeyword: Self.fourCC("----")) else { return .failure(.invalidResult) }
            return .success(DescriptorConversion.value(of: direct))
        } catch {
            return .failure(ScriptError.from(code: (error as NSError).code))
        }
    }

    /// Commande de lecture (précédent, lecture/pause, suivant) : un Apple event sans paramètre, hors du fil principal.
    /// N'est appelée que sur un clic de l'utilisateur ET si l'autorisation est déjà accordée (jamais d'invite provoquée ici).
    public func send(_ command: PlaybackCommand, to player: PlayerID) -> Result<Void, ScriptError> {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).first(where: { !$0.isTerminated }) else {
            return .failure(.notRunning)
        }
        let codes = command.eventCodes(for: player)
        let event = NSAppleEventDescriptor(
            eventClass: Self.fourCC(codes.eventClass), eventID: Self.fourCC(codes.eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: running.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
            if let errn = reply.paramDescriptor(forKeyword: Self.fourCC("errn")), errn.int32Value != 0 {
                return .failure(ScriptError.from(code: Int(errn.int32Value)))
            }
            return .success(())
        } catch {
            return .failure(ScriptError.from(code: (error as NSError).code))
        }
    }

    /// Pochette : Music = octets bruts de `artwork 1 of current track` ; Spotify = `artwork url of current track`.
    /// Une seule lecture par titre, déclenchée par `ArtworkService` seulement si le réglage est actif et l'autorisation accordée.
    public func readArtwork(player: PlayerID) -> Result<ScriptValue, ScriptError> {
        switch player {
        case .music: return read(player: .music, path: ["pTrk", "cArt#1", "pRaw"])
        case .spotify: return read(player: .spotify, path: ["pTrk", "aUrl"])
        }
    }

    /// Exécute une demande de relevé (même format de résultat que les scripts AppleScript : voir `PlayerScripts`).
    public func perform(_ request: ReadRequest) -> Result<[ScriptValue], ScriptError> {
        switch request {
        case .positionOnly(let p): return read(player: p, path: ["pPos"]).map { [$0] }
        case .full(let p): return readFull(p)
        }
    }

    /// Erreurs qui font échouer tout le relevé (comme dans les scripts : l'état est lu hors `try`) ; les autres, ex. −1728, sont notées.
    private static func isFatal(_ e: ScriptError) -> Bool {
        switch e {
        case .denied, .consentRequired, .notRunning, .timedOut: return true
        default: return false
        }
    }

    private func readFull(_ p: PlayerID) -> Result<[ScriptValue], ScriptError> {
        let state: ScriptValue
        switch read(player: p, path: ["pPlS"]) {
        case .failure(let e): return .failure(e)
        case .success(let v): state = v
        }
        var fatal: ScriptError?
        var trackError = 0
        func value(_ path: [String], isTrackProperty: Bool) -> ScriptValue {
            switch read(player: p, path: path) {
            case .success(let v): return v
            case .failure(let e):
                if Self.isFatal(e) { fatal = fatal ?? e } else if isTrackProperty { trackError = e.code }
                return .string("")
            }
        }
        let position = value(["pPos"], isTrackProperty: false)
        let name = value(["pTrk", "pnam"], isTrackProperty: true)
        let artist = value(["pTrk", "pArt"], isTrackProperty: true)
        let album = value(["pTrk", "pAlb"], isTrackProperty: true)
        let duration = value(["pTrk", "pDur"], isTrackProperty: true)
        let identifier = value(["pTrk", p == .spotify ? "ID  " : "pPIS"], isTrackProperty: true)
        if let fatal { return .failure(fatal) }
        return .success([state, position, name, artist, album, duration, identifier, .int(trackError)])
    }
}
