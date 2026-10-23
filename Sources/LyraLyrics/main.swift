import AppKit

// Point d'entrée. La politique d'activation (.regular = icône dans le Dock, .accessory = sans) dépend du seul réglage
// `showsDockIcon` et est appliquée par AppController (décision utilisateur du 2026-10-22). Pas de LSUIElement dans Info.plist.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
