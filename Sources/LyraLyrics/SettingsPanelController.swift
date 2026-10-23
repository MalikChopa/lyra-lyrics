import AppKit
import SwiftUI
import AppSupport

/// Panneau non activant : peut devenir « key » (Échap, enregistrement du raccourci) sans activer l'app.
class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape { onEscape() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }
}

/// Volet de réglages : fenêtre enfant `NSPanel` non activante, à droite de la fenêtre, à gauche près du bord droit (§7).
@MainActor
final class SettingsPanelController {
    enum Side: String { case right, left }

    static let gap = 12.0
    let panel: KeyablePanel
    private let host: PanelHostingView<SettingsView>
    private let parent: PanelController
    private let model: AppModel
    private(set) var side: Side = .right
    var isOpen: Bool { model.settingsOpen }
    /// Demandes de focus clavier à l'ouverture (autotest : Échap doit fonctionner sans clic préalable).
    private(set) var keyRequests = 0

    init(parent: PanelController, model: AppModel, store: SettingsStore, recorder: ShortcutRecorder, actions: SettingsActions) {
        self.parent = parent
        self.model = model
        host = PanelHostingView(rootView: SettingsView(model: model, store: store, recorder: recorder, actions: actions))
        host.sizingOptions = []           // la hauteur est fixée ici : min(contenu, zone visible − marges), le contenu défile au-delà
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 400),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        OverlayConfig.apply(to: panel)
        panel.hasShadow = true
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.close() }
        model.onSettingsContentHeight = { [weak self] in self?.resizeToFit() }
    }

    /// Marge (haut + bas) laissée dans la zone visible.
    static let margin = 12.0
    /// Zone visible simulée (autotest) : hauteur seulement, ancrée en haut de l'écran réel. Jamais posée en usage normal.
    var visibleHeightOverride: Double?

    /// Zone visible utilisée pour le volet (celle de l'écran, ou la zone simulée).
    var visibleFrame: NSRect {
        let v = parent.screen.visibleFrame
        guard let h = visibleHeightOverride else { return v }
        return NSRect(x: v.minX, y: v.maxY - h, width: v.width, height: h)
    }
    var maxHeight: Double { max(160, visibleFrame.height - 2 * Self.margin) }

    /// Hauteur de la fenêtre = min(contenu, maximum) ; appelée à l'ouverture et à chaque changement de hauteur du contenu.
    func resizeToFit() {
        model.settingsMaxHeight = maxHeight
        guard isOpen else { return }
        let content = model.settingsContentHeight
        let height = content > 0 ? min(content, maxHeight) : maxHeight
        if abs(panel.contentView!.frame.height - height) > 0.5 || panel.contentView!.frame.width != SettingsView.width {
            panel.setContentSize(NSSize(width: SettingsView.width, height: height))
        }
        place()
    }

    func open() {
        guard !isOpen else { return }
        model.settingsOpen = true
        model.onSettingsOpened?()
        model.settingsMaxHeight = maxHeight
        let content = model.settingsContentHeight
        panel.setContentSize(NSSize(width: SettingsView.width, height: content > 0 ? min(content, maxHeight) : maxHeight))
        host.layoutSubtreeIfNeeded()
        resizeToFit()
        parent.panel.addChildWindow(panel, ordered: .above)
        place()
        panel.orderFrontRegardless()
        keyRequests += 1
        panel.makeKey()                  // Échap ferme le volet dès l'ouverture (panneau non activant : l'app n'est pas activée)
    }

    func close() {
        guard isOpen else { return }
        model.settingsOpen = false
        parent.panel.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func toggle() { isOpen ? close() : open() }

    /// Calcul sur `screen.visibleFrame` (`flipIfNeeded` de la maquette) : droite, sinon gauche, sinon fenêtre décalée.
    func place() {
        guard isOpen else { return }
        let main = parent.panel.frame
        let v = visibleFrame
        let need = SettingsView.width + Self.gap
        let fitsRight = main.maxX + need <= v.maxX
        let fitsLeft = main.minX - need >= v.minX
        let m: NSRect
        if parent.isResizing {
            // Pendant un redimensionnement à la souris : le volet GARDE son côté (pas de bascule, pas de décalage de la fenêtre),
            // il suit seulement le bord de la fenêtre ; il est ramené dans la zone visible plus bas.
            m = parent.panel.frame
        } else {
            if !fitsRight && !fitsLeft {
                // ni à droite ni à gauche : on décale la fenêtre pour que le volet reste visible (maquette)
                parent.shift(dx: -(main.maxX + need - v.maxX))
            }
            m = parent.panel.frame
            side = (!fitsRight && fitsLeft) ? .left : .right
        }
        let size = panel.frame.size
        var origin = NSPoint(x: side == .right ? m.maxX + Self.gap : m.minX - Self.gap - size.width, y: m.maxY - size.height)
        origin.y = max(v.minY, min(origin.y, v.maxY - size.height))
        origin.x = max(v.minX, min(origin.x, v.maxX - size.width))
        let frame = NSRect(origin: origin, size: size)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }
}

/// « À propos et droits » : `NSPanel` non activant centré ; Échap ferme.
@MainActor
final class AboutPanelController {
    let panel: KeyablePanel
    private let host: PanelHostingView<AboutView>
    private let parent: PanelController
    var isOpen: Bool { panel.isVisible }

    init(parent: PanelController) {
        self.parent = parent
        var closer: (@MainActor () -> Void)?
        host = PanelHostingView(rootView: AboutView(close: { closer?() }))
        host.sizingOptions = [.intrinsicContentSize]
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        OverlayConfig.apply(to: panel)
        panel.hasShadow = true
        panel.contentView = host
        closer = { [weak self] in self?.close() }
        panel.onEscape = { [weak self] in self?.close() }
    }

    func open() {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        let v = parent.screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2))
        panel.orderFrontRegardless()
        panel.makeKey()                  // Échap : « key » sans activation de l'app
    }
    func close() { panel.orderOut(nil) }
}
