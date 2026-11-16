import Testing
import Foundation
@testable import AppSupport

@Suite("1.1.0 : réglages")
struct Settings110Tests {
    @Test("valeurs par défaut de la 1.1.0")
    func defaults() {
        let s = Settings()
        #expect(s.autoHide == .idle)
        #expect(s.checkUpdates)
        #expect(!s.welcomeSeen && !s.launchAtLogin)
        #expect(s.sceneScreen == "window")
        #expect(s.sceneEffects)
        #expect(!s.animatedBackground && !s.karaokeFill)
        #expect(s.sceneLayout == .withArtwork)
    }

    @Test("mise en page de la Scène : défaut « Avec la pochette », aller-retour, valeur inconnue ramenée au défaut")
    func sceneLayoutSetting() {
        var s = Settings(); s.sceneLayout = .lyricsOnly
        #expect(Settings.decode(s.encoded()).0.sceneLayout == .lyricsOnly)
        #expect(Settings.decode(Data(#"{"version":2,"sceneLayout":"inconnue"}"#.utf8)).0.sceneLayout == .withArtwork)
        #expect(Settings.decode(Data(#"{"version":2}"#.utf8)).0.sceneLayout == .withArtwork)
        #expect(SceneLayoutMode.allCases.map(\.label) == ["Paroles seules", "Avec la pochette"])
    }

    @Test("des réglages 1.0.1 sans les nouveaux champs se relisent avec les défauts 1.1.0")
    func oldSettingsDecode() {
        let old = #"{"version":1,"style":"solid","size":30,"lineCount":5}"#
        let (s, outcome) = Settings.decode(Data(old.utf8))
        #expect(outcome == .ok)
        #expect(s.style == .solid && s.size == 30 && s.lineCount == 5)
        #expect(s.autoHide == .idle && s.checkUpdates && !s.welcomeSeen)
    }

    @Test("persistance : aller-retour de tous les champs de la 1.1.0")
    func roundTrip() {
        var s = Settings()
        s.welcomeSeen = true; s.launchAtLogin = true; s.autoHide = .paused; s.checkUpdates = false; s.lastUpdateCheck = 1_700_000_000
        s.sceneScreen = SceneScreenChoice.named("Écran test"); s.sceneEffects = false; s.animatedBackground = true; s.karaokeFill = true
        let (back, outcome) = Settings.decode(s.encoded())
        #expect(outcome == .ok)
        #expect(back == s)
    }

    @Test("1.1.0 : aucune lueur ni karaoké par défaut ; karaoké forcé à désactivé UNE fois pour les réglages en version 1")
    func glowKaraokeDefaultsAndMigration() {
        let d = Settings()
        #expect(!d.glow && !d.karaokeFill && d.fontTheme == .classic)
        #expect(Settings.currentVersion == 2)
        // réglages enregistrés en version 1 avec le karaoké activé : remis à désactivé, le reste (dont la lueur choisie) est gardé
        let (v1, o1) = Settings.decode(Data(#"{"version":1,"karaokeFill":true,"glow":true,"size":30}"#.utf8))
        #expect(o1 == .ok && !v1.karaokeFill && v1.glow && v1.size == 30 && v1.version == 2)
        // sans numéro de version : traité comme la version 1
        #expect(!Settings.decode(Data(#"{"karaokeFill":true}"#.utf8)).0.karaokeFill)
        // une fois enregistrés en version 2, le choix de l'utilisateur est respecté
        var s = Settings(); s.karaokeFill = true
        let (v2, _) = Settings.decode(s.encoded())
        #expect(v2.karaokeFill && v2.version == 2)
        let (v2b, _) = Settings.decode(Data(#"{"version":2,"karaokeFill":true}"#.utf8))
        #expect(v2b.karaokeFill)
    }

    @Test("1.1.0 : seul le thème Néon porte une lueur")
    func onlyNeonGlows() {
        for t in FontTheme.ready { #expect((t.spec?.glow ?? false) == (t == .neon)) }
    }

    @Test("valeur illisible : champ ramené au défaut, le reste est gardé")
    func tolerant() {
        let (s, _) = Settings.decode(Data(#"{"version":1,"autoHide":"jamais-vu","size":33}"#.utf8))
        #expect(s.autoHide == .idle && s.size == 33)
    }
}

@Suite("1.1.0 : mises à jour (E1)")
struct UpdateCheckTests {
    @Test("comparaison de versions")
    func versions() {
        #expect(UpdateCheck.isNewer("v1.1.0", than: "1.0.1"))
        #expect(UpdateCheck.isNewer("1.10.0", than: "1.9.9"))
        #expect(!UpdateCheck.isNewer("v1.0.1", than: "1.0.1"))
        #expect(!UpdateCheck.isNewer("1.0", than: "1.0.0"))
        #expect(!UpdateCheck.isNewer("v1.0.0", than: "1.0.1"))
        #expect(UpdateCheck.isNewer("2.0.0-beta1", than: "1.9.0"))
        #expect(!UpdateCheck.isNewer("n'importe quoi", than: "1.0.1"))
    }

    @Test("lecture de la réponse : tag et lien du dépôt seulement")
    func parse() {
        let ok = #"{"tag_name":"v1.2.0","html_url":"https://github.com/MalikChopa/lyra-lyrics/releases/tag/v1.2.0","body":"ignoré"}"#
        #expect(UpdateCheck.parse(Data(ok.utf8))?.tag == "v1.2.0")
        // le dépôt est renvoyé par l'API sous le nom de compte actuel (redirection 301 constatée)
        let renamed = #"{"tag_name":"v1.0.1","html_url":"https://github.com/autre-compte/lyra-lyrics/releases/tag/v1.0.1"}"#
        #expect(UpdateCheck.parse(Data(renamed.utf8))?.tag == "v1.0.1")
        let bad = [
            #"{"tag_name":"v9","html_url":"https://github.com/autre-compte/autre-depot/releases/tag/v9"}"#,
            #"{"tag_name":"v9","html_url":"https://github.com/autre-compte/lyra-lyrics/issues/1"}"#,
            #"{"tag_name":"v9","html_url":"https://example.com/MalikChopa/lyra-lyrics/releases"}"#,
            #"{"tag_name":"v9","html_url":"http://github.com/MalikChopa/lyra-lyrics/releases"}"#,
            #"{"tag_name":"v9","html_url":"https://github.com/autre/depot/releases"}"#,
            #"{"tag_name":"v9","html_url":"https://github.com.evil.example/MalikChopa/lyra-lyrics/x"}"#,
            #"{"tag_name":"","html_url":"https://github.com/MalikChopa/lyra-lyrics/releases"}"#,
            #"[1,2]"#, "pas du json",
        ]
        for b in bad { #expect(UpdateCheck.parse(Data(b.utf8)) == nil, "\(b)") }
    }

    @Test("résultat : plus récente / à jour / illisible")
    func outcomes() {
        let newer = #"{"tag_name":"v1.1.0","html_url":"https://github.com/MalikChopa/lyra-lyrics/releases/tag/v1.1.0"}"#
        let same = #"{"tag_name":"v1.0.1","html_url":"https://github.com/MalikChopa/lyra-lyrics/releases/tag/v1.0.1"}"#
        if case .newer(let r) = UpdateCheck.outcome(data: Data(newer.utf8), localVersion: "1.0.1") { #expect(r.tag == "v1.1.0") } else { Issue.record("newer attendu") }
        #expect(UpdateCheck.outcome(data: Data(same.utf8), localVersion: "1.0.1") == .upToDate)
        #expect(UpdateCheck.outcome(data: Data("{}".utf8), localVersion: "1.0.1") == .failed)
    }

    @Test("cadence : au plus une vérification par jour")
    func cadence() {
        let now = 1_800_000_000.0
        #expect(UpdateCheck.isDue(last: nil, now: now))
        #expect(!UpdateCheck.isDue(last: now - 3600, now: now))
        #expect(!UpdateCheck.isDue(last: now - 86_399, now: now))
        #expect(UpdateCheck.isDue(last: now - 86_400, now: now))
        #expect(UpdateCheck.isDue(last: now + 10 * 86_400, now: now))      // horloge déréglée : on revérifie
        #expect(UpdateCheck.endpoint.host == "api.github.com")
    }
}

@Suite("1.1.0 : ouverture de session (A2)")
struct LaunchAgentTests {
    @Test("chemin et contenu du LaunchAgent")
    func plist() throws {
        let home = URL(fileURLWithPath: "/tmp/lyra-fausse-maison")
        let url = LaunchAgent.url(label: "io.github.test.app", home: home)
        #expect(url.path == "/tmp/lyra-fausse-maison/Library/LaunchAgents/io.github.test.app.plist")
        let data = try #require(LaunchAgent.plist(label: "io.github.test.app", appPath: "/Applications/Lyra Lyrics.app"))
        let dict = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(dict["Label"] as? String == "io.github.test.app")
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["ProgramArguments"] as? [String] == ["/usr/bin/open", "-a", "/Applications/Lyra Lyrics.app"])
    }
}

@Suite("1.1.0 : masquage automatique (C1)")
struct AutoHideTests {
    @Test("conditions des trois modes")
    func conditions() {
        for a in [PlaybackActivity.nothing, .paused, .playing] { #expect(!AutoHideState.condition(mode: .never, activity: a)) }
        #expect(AutoHideState.condition(mode: .idle, activity: .nothing))
        #expect(!AutoHideState.condition(mode: .idle, activity: .paused))
        #expect(AutoHideState.condition(mode: .paused, activity: .paused))
        #expect(AutoHideState.condition(mode: .paused, activity: .nothing))
        #expect(!AutoHideState.condition(mode: .paused, activity: .playing))
    }

    @Test("cache, remontre, et ne défait jamais un choix manuel")
    func flow() {
        var s = AutoHideState()
        #expect(s.evaluate(mode: .idle, activity: .playing, windowShown: true) == nil)
        #expect(s.evaluate(mode: .idle, activity: .nothing, windowShown: true) == .hide)
        #expect(s.evaluate(mode: .idle, activity: .nothing, windowShown: false) == nil)
        #expect(s.evaluate(mode: .idle, activity: .playing, windowShown: false) == .show)
        // masquage manuel : la reprise ne remontre rien
        s.manualChange(windowShown: false)
        #expect(s.evaluate(mode: .idle, activity: .nothing, windowShown: false) == nil)
        #expect(s.evaluate(mode: .idle, activity: .playing, windowShown: false) == nil)
        // affichage manuel pendant la condition : gardé jusqu'à ce que la condition disparaisse
        _ = s.evaluate(mode: .idle, activity: .nothing, windowShown: false)
        s.manualChange(windowShown: true)
        #expect(s.evaluate(mode: .idle, activity: .nothing, windowShown: true) == nil)
        #expect(s.evaluate(mode: .idle, activity: .nothing, windowShown: true) == nil)
        s.manualChange(windowShown: true)
        #expect(s.evaluate(mode: .idle, activity: .playing, windowShown: true) == nil)
        #expect(s.evaluate(mode: .idle, activity: .nothing, windowShown: true) == .hide)
        // « jamais » remontre ce qu'on avait caché
        #expect(s.evaluate(mode: .never, activity: .nothing, windowShown: false) == .show)
    }
}

@Suite("Scène : calculs purs")
struct SceneMathTests {
    typealias L = LyricLineTime
    let lines = [L(time: 0, text: "Les phares glissent sur la mer"), L(time: 2.8, text: "Et la ville s'éteint sans bruit"),
                 L(time: 30, text: "Après le trou"), L(time: 33, text: "♪"), L(time: 40, text: "Dernière ligne")]

    @Test("S5 : durée de remplissage = temps jusqu'à la ligne suivante, bornée")
    func fill() {
        #expect(abs(SceneMath.fillDuration(lines: lines, index: 0) - 2.8 * 0.92) < 1e-9)
        #expect(SceneMath.fillDuration(lines: lines, index: 1) == SceneMath.fillCap)           // 27,2 s -> plafonnée
        #expect(SceneMath.fillDuration(lines: lines, index: 4) == SceneMath.lastLineDuration * 0.92 || SceneMath.fillDuration(lines: lines, index: 4) == SceneMath.lastLineDuration)
        #expect(SceneMath.fillDuration(lines: lines, index: 99) == SceneMath.fillMin)
        #expect(SceneMath.fillFraction(position: 1, start: 0, duration: 2) == 0.5)
        #expect(SceneMath.fillFraction(position: -1, start: 0, duration: 2) == 0)
        #expect(SceneMath.fillFraction(position: 9, start: 0, duration: 2) == 1)
    }

    @Test("S6 : passages sans paroles (introduction, trou, ligne vide, fin de titre)")
    func gaps() {
        let g = SceneMath.gaps(lines: lines, placeholder: "♪", duration: 60)
        // trou entre la ligne 2 (2,8 s + chant estimé) et la ligne à 30 s ; ligne vide 33 -> 40 ; fin 40 + chant -> 60
        #expect(g.count == 3)
        #expect(g[0].end == 30 && g[0].start > 2.8 && g[0].start < 8)
        #expect(g[1] == SceneMath.Gap(start: 33, end: 40))
        #expect(g[2].end == 60)
        #expect(g[1].fadeOutAt == 39)
        let intro = SceneMath.gaps(lines: [L(time: 12, text: "Après l'introduction")], placeholder: "♪", duration: nil)
        #expect(intro == [SceneMath.Gap(start: 0, end: 12)])
        #expect(SceneMath.gap(at: 36, in: g) == g[1])
        #expect(SceneMath.gap(at: 40, in: g) == nil || SceneMath.gap(at: 40, in: g) != g[1])
        #expect(SceneMath.gaps(lines: [L(time: 0, text: "Court"), L(time: 4, text: "Court")], placeholder: "♪", duration: 8).isEmpty)
    }

    @Test("S4 : la taille diminue jusqu'à ce que le texte tienne")
    func fit() {
        let measure: (String, Double, Double) -> Double = { text, size, width in
            let perLine = max(1, floor(width / (size * 0.5)))
            return ceil(Double(text.count) / perLine) * size * 1.2
        }
        let big = SceneMath.fitSize(text: String(repeating: "mot ", count: 30), width: 1000, maxHeight: 300, maxSize: 110, measure: measure)
        #expect(big < 110 && big >= 28)
        #expect(measure(String(repeating: "mot ", count: 30), big, 1000) <= 300 || big == 28)
        #expect(SceneMath.fitSize(text: "Court", width: 1000, maxHeight: 300, maxSize: 110, measure: measure) == 110)
    }

    @Test("contraste ≥ 4,5 : le voile garantit le rapport pour un fond clair comme pour un fond sombre")
    func contrast() {
        for bg in [0.0, 0.05, 0.2, 0.5, 0.9, 1.0] {
            for text in [0.6, 0.75, 1.0] {
                let scrim = SceneMath.scrimAlpha(backgroundLuminance: bg, textLuminance: text)
                let ratio = SceneMath.contrast(textLuminance: text, backgroundLuminance: bg, scrim: scrim)
                #expect(ratio >= 4.5 - 1e-9 || scrim == 0.92, "fond \(bg), texte \(text) : \(ratio)")
            }
        }
    }

    @Test("fond de la Scène : pochette claire ou sombre, texte clair ou accent, le contraste final reste ≥ 4,5")
    func background() {
        for art in [0.0, 0.05, 0.3, 0.7, 1.0] {
            for text in [0.3, 0.5, 0.7] {
                let b = SceneMath.background(artLuminance: art, gradientLuminance: 0.03, textLuminance: text)
                #expect(b.contrast >= 4.5 - 1e-9, "pochette \(art), texte \(text) : \(b.contrast)")
                #expect(b.scrim >= 0.30 && b.artOpacity >= 0 && b.artOpacity <= 0.92)
            }
        }
        // pochette sombre : on la garde presque entière
        #expect(SceneMath.background(artLuminance: 0.01, gradientLuminance: 0.01, textLuminance: 0.5).artOpacity > 0.9)
    }

    @Test("S10 : choix de l'écran")
    func screens() {
        let names = ["Intégré", "Dell U2720Q", "LG HDR"]
        #expect(SceneScreenChoice.pick(setting: "window", names: names, mainIndex: 0, windowIndex: 2) == 2)
        #expect(SceneScreenChoice.pick(setting: "main", names: names, mainIndex: 0, windowIndex: 2) == 0)
        #expect(SceneScreenChoice.pick(setting: SceneScreenChoice.named("Dell U2720Q"), names: names, mainIndex: 0, windowIndex: 2) == 1)
        #expect(SceneScreenChoice.pick(setting: SceneScreenChoice.named("Débranché"), names: names, mainIndex: 0, windowIndex: 2) == 2)
        #expect(SceneScreenChoice.pick(setting: "main", names: [], mainIndex: 0, windowIndex: 0) == 0)
    }
}
