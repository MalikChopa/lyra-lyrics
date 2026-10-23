import AppKit
import SwiftUI
import AppSupport
import LyricsCore

/// Niveau et comportement communs au panneau principal, au volet de réglages et à À propos (§3.2, §7) :
/// un panneau non activant au niveau « écran de veille » reste visible au-dessus d'une app en plein écran.
enum OverlayConfig {
    static let level: NSWindow.Level = .screenSaver
    static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    @MainActor static func apply(to panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = level
        panel.collectionBehavior = collectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
    }
}

/// Panneau flottant, toujours au-dessus (non activant, niveau écran de veille).
final class LyricsPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LyricsMetrics.windowWidth, height: LyricsMetrics.minHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        OverlayConfig.apply(to: self)
        hasShadow = true
        isMovableByWindowBackground = true
        title = AppIdentity.displayName
    }

    // Menu Police plus tard (§3.2) ; clics sur la barre acceptés sans activer l'app.
    override var canBecomeKey: Bool { true }
}

/// Vue d'hébergement : premier clic accepté (barre au survol), survol par `NSTrackingArea .activeAlways`
/// (le repli prévu au §3.2 est utilisé d'emblée : `onHover` de SwiftUI n'est pas fiable dans un panneau non activant).
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

enum ScreenInfo {
    static func uuid(of screen: NSScreen) -> String? {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }
    static func screen(withUUID uuid: String?) -> NSScreen? {
        guard let uuid else { return nil }
        return NSScreen.screens.first { Self.uuid(of: $0) == uuid }
    }
}
