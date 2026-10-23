import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controller: AppController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        controller = AppController(defaults: Diagnostics.userDefaults())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller?.start()
        if let controller { Diagnostics.applyLaunchArguments(controller) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clic sur l'icône du Dock (ou nouvel `open`) : montrer la fenêtre.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.handleReopen()
        return false
    }
}
