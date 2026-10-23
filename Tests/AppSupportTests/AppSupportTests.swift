import Testing
import Foundation
@testable import AppSupport

/// UserDefaults jetable : suite unique, supprimée à la fin (n'écrit jamais dans les préférences de l'utilisateur).
@MainActor
private func freshDefaults() -> (UserDefaults, String) {
    // Domaine = CHEMIN absolu sous le dossier temporaire : le plist est écrit là (jamais dans ~/Library/Preferences, où cfprefsd
    // le recréait après la fin du test, défaut de J2 à J4).
    let name = NSTemporaryDirectory() + "pf-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    return (d, name)         // pas de removePersistentDomain ici : il créerait un plist vide
}

/// Supprime la suite (domaine ET fichier plist) : aucun `pf.*` ne doit rester dans ~/Library/Preferences (défaut de J2 corrigé à J5).
private func cleanDefaults(_ d: UserDefaults, _ name: String) {
    d.removePersistentDomain(forName: name)
    d.synchronize()
    let plist = URL(fileURLWithPath: name + ".plist")
    try? FileManager.default.removeItem(at: plist)
    // cfprefsd écrit parfois le fichier APRÈS la suppression du domaine : second passage après un court délai.
    Thread.sleep(forTimeInterval: 0.2)
    try? FileManager.default.removeItem(at: plist)
}

@Suite("SettingsStore")
@MainActor
struct SettingsStoreTests {
    @Test("valeurs par défaut = maquette")
    func defaults() {
        let (d, name) = freshDefaults(); defer { cleanDefaults(d, name) }
        let s = SettingsStore(defaults: d)
        #expect(s.loadOutcome == .missing)
        #expect(s.settings.style == .glass)
        #expect(s.settings.size == 26)
        #expect(s.settings.backgroundOpacity == 38)
        #expect(s.settings.font == .system)
        #expect(s.settings.colorHex == "#ffffff")
        #expect(s.settings.clickThrough == false)
        #expect(s.settings.hotKey == defaultHotKey)
        #expect(s.settings.showsDockIcon == false)
        #expect(s.settings.position == nil)
        #expect(Settings.swatches == ["#ffffff", "#ffe27a", "#8fd3ff", "#ffb3d1", "#a8f0b4"])
    }

    @Test("bornage taille 18–44, opacité 0–85, couleur 0–4")
    func clamping() {
        let (d, name) = freshDefaults(); defer { cleanDefaults(d, name) }
        let s = SettingsStore(defaults: d)
        s.update { $0.size = 5; $0.backgroundOpacity = -10; $0.colorIndex = -3 }
        #expect(s.settings.size == 18); #expect(s.settings.backgroundOpacity == 0); #expect(s.settings.colorIndex == 0)
        s.update { $0.size = 99; $0.backgroundOpacity = 200; $0.colorIndex = 12 }
        #expect(s.settings.size == 44); #expect(s.settings.backgroundOpacity == 85); #expect(s.settings.colorIndex == 4)
        s.update { $0.size = 30; $0.backgroundOpacity = 50 }
        #expect(s.settings.size == 30); #expect(s.settings.backgroundOpacity == 50)
    }

    @Test("aller-retour dans UserDefaults (second magasin = redémarrage)")
    func roundTrip() {
        let (d, name) = freshDefaults(); defer { cleanDefaults(d, name) }
        let a = SettingsStore(defaults: d)
        let combo = HotKeyCombo(keyCode: 40, modifiers: HotKeyCombo.carbonCommand | HotKeyCombo.carbonShift, label: "k")
        a.update {
            $0.style = .clear; $0.size = 33; $0.backgroundOpacity = 71; $0.font = .sfMono; $0.colorIndex = 3
            $0.clickThrough = true; $0.hotKey = combo; $0.showsDockIcon = true
            $0.position = WindowPosition(screenUUID: "ABC", centerX: 100.5, centerY: 200.25)
        }
        let b = SettingsStore(defaults: d)
        #expect(b.loadOutcome == .ok)
        #expect(b.settings == a.settings)
        #expect(b.settings.style == .clear); #expect(b.settings.font == .sfMono)
        #expect(b.settings.hotKey == combo); #expect(b.settings.showsDockIcon == true)
        #expect(b.settings.position?.centerY == 200.25)
    }

    @Test("décodage versionné : champs absents, valeurs hors plage, version future, données corrompues")
    func versionedDecode() {
        // v1 minimal : seuls style et taille ; le reste vient des défauts.
        let (s1, o1) = Settings.decode(Data(#"{"version":1,"style":"solid","size":40}"#.utf8))
        #expect(o1 == .ok); #expect(s1.style == .solid); #expect(s1.size == 40); #expect(s1.backgroundOpacity == 38); #expect(s1.hotKey == defaultHotKey)
        // hors plage et champs inconnus
        let (s2, _) = Settings.decode(Data(#"{"version":1,"size":500,"backgroundOpacity":-4,"inconnu":true,"colorIndex":99}"#.utf8))
        #expect(s2.size == 44); #expect(s2.backgroundOpacity == 0); #expect(s2.colorIndex == 4)
        // enum inconnu → défaut (pas d'échec global)
        let (s3, o3) = Settings.decode(Data(#"{"version":1,"style":"hologramme","size":22}"#.utf8))
        #expect(o3 == .ok); #expect(s3.style == .glass); #expect(s3.size == 22)
        // raccourci sans modificateur dans les données → défaut
        let (s4, _) = Settings.decode(Data(#"{"version":1,"hotKey":{"keyCode":37,"modifiers":0,"label":"L"}}"#.utf8))
        #expect(s4.hotKey == defaultHotKey)
        // icône Dock : clé absente → faux (nouveau défaut) ; « true » déjà stocké (réglage J2) → reste vrai
        #expect(Settings.decode(Data(#"{"version":1}"#.utf8)).0.showsDockIcon == false)
        #expect(Settings.decode(Data(#"{"version":1,"showsDockIcon":true}"#.utf8)).0.showsDockIcon == true)
        // version future → défauts, sans planter
        let (s5, o5) = Settings.decode(Data(#"{"version":9,"style":"solid","size":40}"#.utf8))
        #expect(o5 == .newerVersion(9)); #expect(s5 == Settings())
        // corrompu / absent
        #expect(Settings.decode(Data("pas du json".utf8)).1 == .corrupt)
        #expect(Settings.decode(nil).1 == .missing)
    }

    @Test("reset rétablit les défauts")
    func reset() {
        let (d, name) = freshDefaults(); defer { cleanDefaults(d, name) }
        let s = SettingsStore(defaults: d)
        s.update { $0.size = 40; $0.style = .solid }
        s.reset()
        #expect(s.settings == Settings())
        #expect(SettingsStore(defaults: d).settings == Settings())
    }
}

@Suite("Raccourci")
struct HotKeyTests {
    @Test("refuse l'absence de modificateur, ⇧ seul et l'absence de touche")
    func rejects() {
        #expect(HotKeyCombo.validated(keyCode: 37, modifiers: 0, label: "L") == .failure(.needsModifier))
        #expect(HotKeyCombo.validated(keyCode: 37, modifiers: HotKeyCombo.carbonShift, label: "L") == .failure(.needsModifier))
        #expect(HotKeyCombo.validated(keyCode: 37, modifiers: HotKeyCombo.carbonCommand, label: " ") == .failure(.emptyKey))
    }
    @Test("accepte ⌘, ⌥ ou ⌃ (seuls ou combinés)")
    func accepts() {
        for m in [HotKeyCombo.carbonCommand, HotKeyCombo.carbonOption, HotKeyCombo.carbonControl,
                  HotKeyCombo.carbonOption | HotKeyCombo.carbonShift] {
            #expect((try? HotKeyCombo.validated(keyCode: 40, modifiers: m, label: "K").get()) != nil)
        }
    }
    @Test("défaut valide ; affichage ordonné ⌃⌥⇧⌘")
    func defaultAndDisplay() {
        #expect(defaultHotKey.isValid)
        #expect(defaultHotKey.display == "⌃⌥⌘L")
        let c = HotKeyCombo(keyCode: 1, modifiers: HotKeyCombo.allModifiers, label: "s")
        #expect(c.display == "⌃⌥⇧⌘S")
    }
    @Test("les bits hors modificateurs sont ignorés")
    func masks() {
        #expect(HotKeyCombo(keyCode: 1, modifiers: 0xFFFF_FFFF, label: "a").modifiers == HotKeyCombo.allModifiers)
    }
}

@Suite("LineFitter")
struct LineFitterTests {
    // Bouchon : 0,5 × taille de largeur par caractère, hauteur de ligne 1,22 × taille.
    static let fitter = LineFitter { text, size, width in
        let perLine = max(1, Int(width / (size * 0.5)))
        let n = max(1, (text.count + perLine - 1) / perLine)
        return Double(n) * size * 1.22
    }

    @Test("lignes courtes : taille demandée, hauteur minimale 190")
    func short() {
        let f = Self.fitter.fit(lines: ["a", "b", "c"], baseSize: 26, visibleHeight: 1000)
        #expect(f.currentSize == 26); #expect(f.windowHeight == 190); #expect(!f.shrunk); #expect(!f.exceedsMaxHeight)
    }
    @Test("lignes longues sous 80 % : la fenêtre grandit, la police ne bouge pas")
    func growsFirst() {
        let long = String(repeating: "x", count: 80)
        let f = Self.fitter.fit(lines: [long, long, long], baseSize: 44, visibleHeight: 1000)
        #expect(f.currentSize == 44); #expect(f.windowHeight > 190); #expect(f.windowHeight <= 800); #expect(!f.shrunk)
    }
    @Test("au-delà de 80 % : la police diminue, plancher 14 pt, puis la fenêtre grandit jusqu'à la zone visible")
    func shrinksThenCaps() {
        let long = String(repeating: "x", count: 80)
        let small = Self.fitter.fit(lines: [long, long, long], baseSize: 44, visibleHeight: 500)
        #expect(small.shrunk); #expect(small.currentSize < 44); #expect(small.currentSize >= 14); #expect(small.windowHeight <= 400)
        let huge = String(repeating: "x", count: 4000)
        let f = Self.fitter.fit(lines: [huge, huge, huge], baseSize: 44, visibleHeight: 600)
        #expect(f.currentSize == 14); #expect(f.exceedsMaxHeight); #expect(f.windowHeight == 600)
    }
}
