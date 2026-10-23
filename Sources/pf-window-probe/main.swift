// pf-window-probe : sonde de fenêtres pour les tests automatiques (outil de développement).
//   list                : fenêtres à l'écran, de l'avant vers l'arrière (CGWindowListCopyWindowInfo, .optionOnScreenOnly)
//   fullscreen [secs]   : met SA PROPRE fenêtre en plein écran natif, imprime la liste une fois en plein écran,
//                         puis quitte seule (durée par défaut 8 s, plafond dur 15 s, quitte même en cas d'erreur).
import AppKit
import CoreGraphics

func listWindows(label: String) {
    let expected = CGWindowLevelForKey(.screenSaverWindow)
    print("# \(label)")
    print("# niveau attendu CGWindowLevelForKey(.screenSaverWindow) = \(expected)")
    let opts: CGWindowListOption = [.optionOnScreenOnly]
    guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        print("# erreur : CGWindowListCopyWindowInfo a renvoyé nil")
        return
    }
    var policies: [Int32: String] = [:]
    for (index, w) in infos.enumerated() {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
        let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
        let onscreen = (w[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        let number = (w[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1
        let name = w[kCGWindowName as String] as? String ?? ""
        var bounds = "?"
        if let b = w[kCGWindowBounds as String] as? [String: Any] {
            let f = { (k: String) -> Int in (b[k] as? NSNumber)?.intValue ?? 0 }
            bounds = "x=\(f("X")) y=\(f("Y")) w=\(f("Width")) h=\(f("Height"))"
        }
        if policies[pid] == nil {
            if let app = NSRunningApplication(processIdentifier: pid) {
                switch app.activationPolicy {
                case .regular: policies[pid] = "regular"
                case .accessory: policies[pid] = "accessory"
                case .prohibited: policies[pid] = "prohibited"
                @unknown default: policies[pid] = "inconnu"
                }
            } else {
                policies[pid] = "n/a"
            }
        }
        print("z=\(index) owner=\(owner) pid=\(pid) policy=\(policies[pid] ?? "n/a") layer=\(layer) onscreen=\(onscreen) id=\(number) \(bounds) name=\"\(name)\"")
    }
}

@MainActor
final class FullScreenProbe: NSObject, NSWindowDelegate {
    let window: NSWindow
    let holdSeconds: Double
    var finished = false

    init(holdSeconds: Double) {
        self.holdSeconds = holdSeconds
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 400),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "pf-window-probe plein écran"
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.7, alpha: 1)
    }

    func start() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        // Après l'animation d'entrée : imprimer la liste, puis quitter.
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) { [self] in finish() }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let isFull = self.window.styleMask.contains(.fullScreen)
            listWindows(label: "liste en plein écran (styleMask.fullScreen=\(isFull))")
            fflush(stdout)
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        // Laisser l'animation de sortie se terminer, puis quitter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
    }
}

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "list"

switch command {
case "list":
    listWindows(label: "liste des fenêtres à l'écran (avant -> arrière)")
case "fullscreen":
    let requested = arguments.count > 2 ? (Double(arguments[2]) ?? 8) : 8
    let hold = min(max(requested, 4), 10)
    // Plafond dur : quoi qu'il arrive (erreur, main bloqué), le processus s'arrête avant 15 s.
    Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 14.5)
        fputs("pf-window-probe : plafond dur atteint, sortie forcée\n", stderr)
        exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let probe = FullScreenProbe(holdSeconds: hold)
    app.delegate = nil
    DispatchQueue.main.async { probe.start() }
    app.run()
default:
    fputs("usage : pf-window-probe list | fullscreen [secondes]\n", stderr)
    exit(64)
}
