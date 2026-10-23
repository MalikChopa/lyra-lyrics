import AppKit
import AppSupport
import LyricsCore

struct MenuActions {
    var toggleVisibility: @MainActor () -> Void
    var toggleClickThrough: @MainActor () -> Void
    var setStyle: @MainActor (BackgroundStyle) -> Void
    var openSettings: @MainActor () -> Void
    var openAbout: @MainActor () -> Void
    var quit: @MainActor () -> Void
    /// (fenêtre visible, clic-à-travers, style choisi)
    var state: @MainActor () -> (Bool, Bool, BackgroundStyle)
    /// Raccourci « Cacher / montrer » tel qu'affiché (⌃⌥⌘L) : en clic-à-travers, c'est la sortie.
    var hotKeyDisplay: @MainActor () -> String
}

/// Icône de barre de menus et son menu : Afficher/Cacher, Clic-à-travers, Style, Réglages…, À propos et droits, Quitter.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    fileprivate let statusItem: NSStatusItem
    private let actions: MenuActions
    private let visibilityItem = NSMenuItem()
    private let clickThroughItem = NSMenuItem()
    private var styleItems: [BackgroundStyle: NSMenuItem] = [:]

    init(actions: MenuActions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: AppIdentity.displayName)
            image?.isTemplate = true
            button.image = image
        }
        statusItem.menu = buildMenu()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        visibilityItem.title = "Cacher les paroles"; visibilityItem.action = #selector(toggleVisibility); visibilityItem.target = self
        clickThroughItem.title = "Clic-à-travers"; clickThroughItem.action = #selector(toggleClickThrough); clickThroughItem.target = self
        menu.addItem(visibilityItem)
        menu.addItem(clickThroughItem)
        let styleMenu = NSMenu()
        for style in BackgroundStyle.allCases {
            let i = item(style.label, #selector(pickStyle(_:)))
            i.representedObject = style.rawValue
            styleItems[style] = i
            styleMenu.addItem(i)
        }
        let styleParent = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleParent.submenu = styleMenu
        menu.addItem(styleParent)
        menu.addItem(.separator())
        menu.addItem(item("Réglages…", #selector(openSettings), key: ","))
        menu.addItem(item("À propos et droits", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(item(AppIdentity.quitMenuTitle, #selector(quit), key: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    func refresh() {
        let (visible, clickThrough, style) = actions.state()
        visibilityItem.title = visible ? "Cacher les paroles" : "Afficher les paroles"
        clickThroughItem.title = "Clic-à-travers (sortie : \(actions.hotKeyDisplay()))"
        clickThroughItem.state = clickThrough ? .on : .off
        for (s, i) in styleItems { i.state = s == style ? .on : .off }
    }

    @objc private func toggleVisibility() { actions.toggleVisibility() }
    @objc private func toggleClickThrough() { actions.toggleClickThrough() }
    @objc private func pickStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let s = BackgroundStyle(rawValue: raw) { actions.setStyle(s) }
    }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func openAbout() { actions.openAbout() }
    @objc private func quit() { actions.quit() }

    /// Titres des entrées (autotest).
    var menuTitles: [String] { statusItem.menu?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? [] }
}

#if DEBUG
extension StatusItemController {
    /// Autotest : déclenche une entrée du menu comme un clic (par son titre).
    func perform(title: String) {
        guard let menu = statusItem.menu, let i = menu.items.firstIndex(where: { $0.title.hasPrefix(title) }) else { return }
        menu.performActionForItem(at: i)
    }
    func performStyle(label: String) {
        guard let menu = statusItem.menu, let sub = menu.items.first(where: { $0.title == "Style" })?.submenu,
              let i = sub.items.firstIndex(where: { $0.title == label }) else { return }
        sub.performActionForItem(at: i)
    }
}
#endif
