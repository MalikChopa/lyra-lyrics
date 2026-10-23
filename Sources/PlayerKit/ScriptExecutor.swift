import Foundation

/// Demande de relevé : « tout » (état, position, titre : 8 valeurs) ou la position seule (banc de la mesure 5).
public enum ReadRequest: Sendable, Equatable {
    case full(PlayerID)
    case positionOnly(PlayerID)

    public var player: PlayerID {
        switch self { case .full(let p), .positionOnly(let p): return p }
    }
}

/// Transport d'un relevé. Deux implémentations : `AppleEventBackend` (retenu, hors fil principal) et
/// `NSAppleScriptBackend` (repli, fil principal). Injectable pour les tests.
@MainActor
public protocol ScriptBackend {
    func execute(_ request: ReadRequest) async -> Result<[ScriptValue], ScriptError>
}

/// Repli : `NSAppleScript`, fil principal ; chaque source n'est compilée qu'une fois (cache). Bloque le fil principal
/// pendant tout l'appel (≈ 117 ms pour un relevé complet, mesure 4 de J1).
@MainActor
public final class NSAppleScriptBackend: ScriptBackend {
    private var compiled: [String: NSAppleScript] = [:]
    public init() {}

    public func execute(_ request: ReadRequest) async -> Result<[ScriptValue], ScriptError> {
        switch request {
        case .full(let p): return execute(source: PlayerScripts.readScript(for: p))
        case .positionOnly(let p): return execute(source: PlayerScripts.positionOnly(p))
        }
    }

    public func execute(source: String) -> Result<[ScriptValue], ScriptError> {
        let script: NSAppleScript
        if let known = compiled[source] {
            script = known
        } else {
            guard let fresh = NSAppleScript(source: source) else { return .failure(.invalidResult) }
            var compileError: NSDictionary?
            if !fresh.compileAndReturnError(&compileError) {
                let n = (compileError?[NSAppleScript.errorNumber] as? Int) ?? 0
                return .failure(ScriptError.from(code: n))
            }
            compiled[source] = fresh
            script = fresh
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let n = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            return .failure(ScriptError.from(code: n))
        }
        return .success(DescriptorConversion.values(of: result))
    }
}

/// Transport retenu à J1 : Apple events construits à la main, envoyés hors du fil principal (aucun gel de l'interface).
@MainActor
public final class AppleEventBackend: ScriptBackend {
    private let client: AppleEventClient
    public init(timeout: TimeInterval = 1) { client = AppleEventClient(timeout: timeout) }

    public func execute(_ request: ReadRequest) async -> Result<[ScriptValue], ScriptError> {
        let client = self.client
        return await Task.detached(priority: .userInitiated) { client.perform(request) }.value
    }
}

/// Exécuteur du §3.2 : un relevé en vol au plus (`busy` sinon), suspension 30 s après 3 délais dépassés de suite.
/// Le délai de 1 s est dans le transport (`with timeout of 1 second` / `AppleEventClient.timeout`).
@MainActor
public final class ScriptExecutor {
    public static let timeoutsBeforeSuspension = 3
    public static let suspensionDuration: Duration = .seconds(30)

    private let backend: ScriptBackend
    private let now: @MainActor () -> ContinuousClock.Instant
    private var inFlight = false
    private var consecutiveTimeouts = 0
    private var suspendedUntil: ContinuousClock.Instant?

    /// Nombre d'exécutions réellement envoyées au backend (des Apple events).
    public private(set) var sentCount = 0

    public init(backend: ScriptBackend, now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.backend = backend
        self.now = now
    }

    public var isSuspended: Bool {
        if let until = suspendedUntil, now() < until { return true }
        return false
    }

    public func run(_ request: ReadRequest) async -> Result<[ScriptValue], ScriptError> {
        if isSuspended { return .failure(.suspended) }
        if suspendedUntil != nil { suspendedUntil = nil; consecutiveTimeouts = 0 }
        if inFlight { return .failure(.busy) }
        inFlight = true
        sentCount += 1
        let result = await backend.execute(request)
        inFlight = false
        switch result {
        case .success:
            consecutiveTimeouts = 0
        case .failure(.timedOut):
            consecutiveTimeouts += 1
            if consecutiveTimeouts >= Self.timeoutsBeforeSuspension {
                suspendedUntil = now() + Self.suspensionDuration
            }
        case .failure:
            consecutiveTimeouts = 0
        }
        return result
    }
}

enum DescriptorConversion {
    static func values(of d: NSAppleEventDescriptor) -> [ScriptValue] {
        if d.descriptorType == typeAEList {
            guard d.numberOfItems > 0 else { return [] }
            return (1...d.numberOfItems).compactMap { d.atIndex($0) }.map(value(of:))
        }
        return [value(of: d)]
    }

    static func value(of d: NSAppleEventDescriptor) -> ScriptValue {
        switch d.descriptorType {
        case typeIEEE64BitFloatingPoint:
            return d.data.count == 8 ? .double(d.data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }) : .null
        case typeIEEE32BitFloatingPoint:
            return d.data.count == 4 ? .double(Double(d.data.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })) : .null
        case typeSInt32, typeSInt16, typeUInt32, typeSInt64:
            return .int(Int(d.int32Value))
        case typeEnumerated:
            switch d.enumCodeValue {
            case AppleEventClient.fourCC("kPSP"), AppleEventClient.fourCC("kPSF"), AppleEventClient.fourCC("kPSR"): return .string("playing")
            case AppleEventClient.fourCC("kPSp"): return .string("paused")
            case AppleEventClient.fourCC("kPSS"): return .string("stopped")
            default: return .null
            }
        case typeNull:
            return .null
        case typeData, AppleEventClient.fourCC("PNGf"), AppleEventClient.fourCC("JPEG"), AppleEventClient.fourCC("TIFF"),
             AppleEventClient.fourCC("GIFf"), AppleEventClient.fourCC("BMPf"), AppleEventClient.fourCC("PICT"):
            return d.data.isEmpty ? .null : .data(d.data)
        default:
            if let s = d.stringValue { return .string(s) }
            return .null
        }
    }
}
