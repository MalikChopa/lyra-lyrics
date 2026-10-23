import AppKit

/// Présence d'un lecteur : aucun Apple event ne doit partir si le lecteur n'est pas lancé
/// (un `tell application` AppleScript le LANCERAIT).
@MainActor
public protocol PlayerPresence {
    func isRunning(_ player: PlayerID) -> Bool
}

@MainActor
public struct WorkspacePresence: PlayerPresence {
    public init() {}
    public func isRunning(_ player: PlayerID) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).contains { !$0.isTerminated }
    }
}
