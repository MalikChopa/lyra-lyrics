import Foundation

@MainActor
public protocol PlayerSource: AnyObject {
    var events: AsyncStream<PlayerEvent> { get }
    func start()
    func stop()
}

/// Logique commune aux sources : suivi du dernier titre et émission `trackChanged` / `reading` / `stopped`.
@MainActor
final class EventEmitter {
    let player: PlayerID
    let stream: AsyncStream<PlayerEvent>
    private let continuation: AsyncStream<PlayerEvent>.Continuation
    private(set) var lastReading: PlayerReading?
    private var lastIdentity: String?
    private var lastStoppedEmitted = false

    init(player: PlayerID) {
        self.player = player
        (stream, continuation) = AsyncStream.makeStream(of: PlayerEvent.self, bufferingPolicy: .unbounded)
    }

    func emit(_ event: PlayerEvent) { continuation.yield(event) }
    func finish() { continuation.finish() }

    func ingest(_ reading: PlayerReading) {
        lastReading = reading
        if reading.state == .stopped {
            if !lastStoppedEmitted { continuation.yield(.stopped(player)) }
            lastStoppedEmitted = true
            lastIdentity = nil
            return
        }
        lastStoppedEmitted = false
        let identity = reading.track?.identity
        if identity != lastIdentity {
            lastIdentity = identity
            continuation.yield(.trackChanged(reading))
        } else {
            continuation.yield(.reading(reading))
        }
    }

    func playerQuit() {
        if lastReading != nil || !lastStoppedEmitted { continuation.yield(.stopped(player)) }
        lastStoppedEmitted = true
        lastReading = nil
        lastIdentity = nil
    }
}
