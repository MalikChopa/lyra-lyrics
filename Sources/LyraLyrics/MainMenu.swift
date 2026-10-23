import AppKit
import LyricsCore

/// Menu principal minimal pour la politique `.regular` (icône dans le Dock) : menu de l'app avec À propos, Réglages, Quitter.
@MainActor
final class MainMenuHandler: NSObject {
    var openAbout: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}
    @objc func about() { openAbout() }
    @objc func settings() { openSettings() }

    func install() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu(title: AppIdentity.displayName)
        let about = NSMenuItem(title: "À propos et droits", action: #selector(about), keyEquivalent: "")
        about.target = self
        let settings = NSMenuItem(title: "Réglages…", action: #selector(settings), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: AppIdentity.quitMenuTitle, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        app.addItem(about); app.addItem(settings); app.addItem(.separator()); app.addItem(quit)
        appItem.submenu = app
        NSApp.mainMenu = main
    }
}
