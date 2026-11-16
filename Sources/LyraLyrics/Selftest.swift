#if DEBUG
import AppKit
import AppSupport
import LyricsCore
import PlayerKit

/// `--selftest <script>` (DEBUG uniquement) : enchaîne des actions sur l'app en cours (style, réglages, volet, À propos,
/// clic-à-travers, titre via le faux lecteur, raccourci, décalage, cache, réseau, mesure de synchro…) et écrit l'état des
/// fenêtres dans le journal de diagnostic. Format : une action par ligne, `#` = commentaire. Voir Fixtures/selftests/*.txt.
/// Code de sortie 1 si une attente échoue. Le journal ne contient jamais de paroles (indices et longueurs seulement).
@MainActor
final class SelftestRunner {
    private let c: AppController
    private var pass = 0
    private var fail = 0
    private var last: [String: Any] = [:]
    private var marks: [String: Double] = [:]
    /// Mesures de preuve en pixels (`winshot`), ajoutées à l'état lisible par `expect`.
    private var extra: [String: Any] = [:]
    /// Autorisation et envoi simulés pour les boutons de lecture (aucun Apple event, aucune invite).
    private let flow = FlowSimulator()

    private func numeric(_ any: Any?) -> Double {
        switch any { case let d as Double: return d; case let i as Int: return Double(i); case let s as String: return Double(s) ?? .nan; default: return .nan }
    }

    init(controller: AppController) { c = controller }

    func run(scriptPath: String) {
        ResizeHandleView.ignoreRealEvents = true
        KeyablePanel.selftestActive = true
        guard let text = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
            DiagLog.shared.write(["selftest": "script-introuvable", "path": scriptPath]); exit(2)
        }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))      // premier affichage
            for line in lines { await self.exec(line) }
            DiagLog.shared.write(["selftest": "fin", "ok": self.pass, "echecs": self.fail])
            exit(self.fail == 0 ? 0 : 1)
        }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(300)) }

    // MARK: Actions

    private func exec(_ line: String) async {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0]
        let arg = parts.count > 1 ? parts[1] : ""
        let on = arg == "on"
        switch cmd {
        case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
        case "echo": DiagLog.shared.write(["echo": arg])
        case "style": if let s = BackgroundStyle(rawValue: arg) { c.setStyle(s) }
        case "cycle": c.cycleStyle()                                              // même chemin que le bouton ◐
        case "size": c.change { $0.size = Int(arg) ?? 26 }
        case "opacity": c.change { $0.backgroundOpacity = Int(arg) ?? 38 }
        case "font": if let f = LyricFont(rawValue: arg) { c.change { $0.font = f } }
        case "color": c.change { $0.colorIndex = Int(arg) ?? 0 }
        // Fonctions 1.0
        case "lines": c.change { $0.lineCount = Int(arg) ?? 3 }
        case "theme": if let t = FontTheme(rawValue: arg) { c.change { $0.apply(theme: t) } }
        case "weight": if let w = LyricWeight(rawValue: arg) { c.change { $0.fontWeight = w } }
        case "glow": c.change { $0.glow = on }
        case "artwork": c.change { $0.artworkColors = on }
        case "playback":
            if let cmd = PlaybackCommand(rawValue: arg) { c.model.sendPlayback(cmd) }
        // 1.1.0
        case "welcome":
            switch arg {
            case "open": c.openWelcome()
            case "first": c.showWelcomeIfFirstLaunch()
            case "start": c.finishWelcome()
            case "close": c.welcomeController.close()
            default: fail += 1
            }
        case "scene":
            switch arg {
            case "enter": c.scene.enter()
            case "exit": c.scene.exit()
            case "toggle": c.toggleScene()
            case "card": c.scene.view?.showCardNow()
            case "enter-probe": await sceneEnterProbe()
            case "fill-probe": await sceneFillProbe()
            case "line-probe": await sceneLineProbe()
            case "dblclick-small": sendDoubleClick(to: c.panelController.panel, at: point(named: "bg"))
            case "dblclick": if let v = c.scene.view { sendDoubleClick(to: c.scene.panel, at: NSPoint(x: v.bounds.midX, y: v.bounds.midY)) } else { fail += 1 }
            case "escape": sendEscape(to: c.scene.panel)
            case "exit-hide": c.scene.view?.debugHideExitControl()
            case "mouse-move": if let v = c.scene.view { v.pointerMoved() } else { fail += 1 }
            case "exit-click":
                if let v = c.scene.view { sendClick(to: c.scene.panel, at: NSPoint(x: v.exitControlFrame.midX, y: v.exitControlFrame.midY)) } else { fail += 1 }
            case "occlude": c.scene.debugSetOccluded(true)
            case "unocclude": c.scene.debugSetOccluded(false)
            case "screen-main": c.change { $0.sceneScreen = SceneScreenChoice.main }
            case "screen-window": c.change { $0.sceneScreen = SceneScreenChoice.window }
            case "screen-missing": c.change { $0.sceneScreen = SceneScreenChoice.named("Écran débranché") }
            case "screen-first": c.change { $0.sceneScreen = SceneScreenChoice.named(NSScreen.screens[0].localizedName) }
            case "layout-art": c.change { $0.sceneLayout = .withArtwork }
            case "layout-lyrics": c.change { $0.sceneLayout = .lyricsOnly }
            case "key-space": sendKey(49, to: c.scene.panel)
            case "key-left": sendKey(123, to: c.scene.panel)
            case "key-right": sendKey(124, to: c.scene.panel)
            case "bar-previous", "bar-playPause", "bar-next", "bar-exit":
                // clic synthétique au centre du bouton (la barre doit être visible : `scene mouse-move` d'abord)
                if let v = c.scene.view { let r = v.bar.frame(of: String(arg.dropFirst(4))); sendClick(to: c.scene.panel, at: NSPoint(x: r.midX, y: r.midY)) } else { fail += 1 }
            case "effects-on": c.change { $0.sceneEffects = true }
            case "effects-off": c.change { $0.sceneEffects = false }
            default: fail += 1
            }
        case "animated-bg": c.change { $0.animatedBackground = on }
        case "karaoke": c.change { $0.karaokeFill = on }
        case "login": c.setLaunchAtLogin(on)
        case "memory-cache-clear": await c.model.service?.clearMemoryCache()
        case "manual":
            let words = arg.split(separator: " ", maxSplits: 1).map(String.init)
            let sub = words.first ?? ""
            let rest = words.count > 1 ? words[1] : ""
            switch sub {
            case "open": c.openManualSearch()
            case "close": c.manualSearch.close()
            case "fields":
                let f = rest.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                c.manualSearch.search.title = f.first ?? ""; c.manualSearch.search.artist = f.count > 1 ? f[1] : ""
            case "search": c.manualSearch.runSearch()
            case "choose":
                if let id = Int(rest), let cand = c.manualSearch.search.results.first(where: { $0.id == id }) { c.manualSearch.choose(cand) } else { fail += 1 }
            case "revert": c.model.revertToAutomatic(); c.manualSearch.search.chosenID = nil
            case "state-button": c.model.mode == .unavailable ? c.openManualSearch() : (fail += 1)
            default: fail += 1
            }
        case "autohide": if let m = AutoHideMode(rawValue: arg) { c.change { $0.autoHide = m } }
        case "update":
            guard let base = Diagnostics.value(of: "--lyrics-endpoint") else { fail += 1; break }
            let url = "https://github.com/MalikChopa/lyra-lyrics/releases/tag/v9.9.9"
            var comps = URLComponents(string: base + "/fake-github/latest")!
            switch arg {
            case "newer": comps.queryItems = [URLQueryItem(name: "tag", value: "v9.9.9"), URLQueryItem(name: "url", value: url)]
            case "same": comps.queryItems = [URLQueryItem(name: "tag", value: "v\(AppIdentity.version)"), URLQueryItem(name: "url", value: url)]
            case "error": comps.queryItems = [URLQueryItem(name: "status", value: "500")]
            case "evil": comps.queryItems = [URLQueryItem(name: "tag", value: "v9.9.9"), URLQueryItem(name: "url", value: "https://example.com/x")]
            default: break
            }
            c.updates.endpoint = comps.url!
            await c.checkForUpdates(force: true)
        case "update-auto": await c.checkForUpdates(force: false)
        case "update-link": c.openUpdatePage()
        case "anim-probe": await animProbe()
        case "anim-list": animList()
        case "hotkey-handler": c.handleHotKey()                                  // même chemin que la frappe, sans passer par Carbon
        case "reopen": c.handleReopen()
        case "resize": await resize(arg, expectHit: true)
        case "resize-blocked": await resize(arg, expectHit: false)      // zone masquée (clic-à-travers) : aucune zone de prise touchée
        case "resize-to":
            // `resize-to <largeur> <hauteur>` : tire le coin bas-droit jusqu'à la taille voulue (événements synthétiques)
            let t = arg.split(separator: " ").compactMap { Double($0) }
            if t.count == 2 {
                let f = c.panelController.panel.frame
                await resize("bottomRight \(t[0] - f.width) \(-(t[1] - f.height))", expectHit: true)
            }
        case "resetsize": c.panelController.resetSize(); c.refreshWindows()
        case "mark": marks[arg] = numeric(stateDict()[arg])
        case "expect-gt", "expect-lt", "expect-eq":
            await settle()
            let now = numeric(stateDict()[arg]), before = marks[arg] ?? .nan
            let ok = cmd == "expect-gt" ? now > before + 0.01 : (cmd == "expect-lt" ? now < before - 0.01 : abs(now - before) < 0.01)
            if ok { pass += 1 } else { fail += 1 }
            DiagLog.shared.write(["expect": "\(cmd) \(arg)", "avant": before, "maintenant": now, "ok": ok])
        case "clickthrough": c.setClickThrough(on)
        case "dock": c.change { $0.showsDockIcon = on }
        case "settings": arg == "open" ? c.openSettings() : (arg == "close" ? c.settingsController.close() : c.toggleSettings())
        case "about": arg == "open" ? c.openAbout() : c.aboutController.close()
        case "escape": sendEscape(to: arg == "about" ? c.aboutController.panel : c.settingsController.panel)
        case "hover": c.model.hovering = on
        case "hover-pulse": c.model.hovering = true; try? await Task.sleep(for: .milliseconds(150)); c.model.hovering = false
        case "play": c.fakePlayer?.perform("play", track: arg)
        case "seek": c.fakePlayer?.perform("seek", track: arg)
        case "pause", "resume", "stop": c.fakePlayer?.perform(cmd)
        case "hide": if c.panelController.isShown { c.toggleVisibility() }
        case "show": if !c.panelController.isShown { c.toggleVisibility() }
        case "reducetransparency": c.model.reduceTransparencyOverride = arg == "auto" ? nil : on; c.refreshWindows()
        case "move": move(arg)
        case "shortcut": shortcut(arg)
        case "shortcut-block": shortcutBlock(arg)
        case "shortcut-unblock": c.hotKey.debugUnblock()
        case "shortcut-default": _ = c.applyHotKey(defaultHotKey)
        case "hotkey-press": await hotkeyPress()
        case "menu": c.statusItem.perform(title: arg)
        case "menustyle": c.statusItem.performStyle(label: arg)
        case "click": await click(arg)
        case "hit": hit(arg)
        // J3
        case "offset": offset(arg)
        case "winshot": await winShot(arg)
        case "multiline": multilineProof()
        case "clearcache": await clearCache()
        case "stats": await c.model.refreshStats()
        case "offline": c.model.setOnline(!on)
        case "wait-for": await waitFor(arg)
        // J5
        case "perm-needed", "unreadable": c.fakePlayer?.perform(cmd)
        case "perm-answer": c.model.musicPermissionAnswered(arg == "granted" ? .granted : .denied)
        case "click-permission": c.requestMusicAccess()          // même chemin que le bouton « Autoriser » / « Ouvrir les Réglages »
        case "spotify-access": c.model.spotifyAccess = Self.status(arg)
        // 1.0.1, point C : les boutons passent par le VRAI déroulé d'autorisation, avec sonde et envoi simulés
        case "spotify-flow":
            c.playbackFlowUnderTest = on
            if on {
                let sim = flow
                c.permissionFlow = PlaybackPermissionFlow(probe: { player, ask in sim.probe(player, ask: ask) }, statusTimeout: 2, askTimeout: 8)
                c.commandSender = { command, player in sim.send(command, player) }
            } else {
                c.permissionFlow = PlaybackPermissionFlow()
                c.commandSender = { AppleEventClient(timeout: 1).send($0, to: $1) }
            }
        case "flow-status": flow.setStatus(Self.status(arg) ?? .notDetermined)       // réponse à la lecture SANS demande
        case "flow-hold": flow.hold(on)                                               // la demande (ask = true) attend `flow-release`
        case "flow-release": flow.release(Self.status(arg) ?? .granted)
        case "flow-answer": flow.setAnswer(Self.status(arg) ?? .granted)              // réponse immédiate à la demande
        case "notice-action": if let action = c.model.noticeAction { action.perform() } else { fail += 1 }
        case "wake": NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        case "reducemotion": c.model.reduceMotionOverride = arg == "auto" ? nil : on
        case "visible-height":
            c.settingsController.visibleHeightOverride = Double(arg)
            c.settingsController.resizeToFit()
        case "ax-audit": axAudit(arg)
        case "ax-press": axPress(arg)                       // `ax-press settings Fermer les réglages` : appuie sur le bouton par son libellé AX
        case "measure-sync": await measureSync(offsetArg: arg)
        case "state": await settle(); record(arg)
        case "expect": await settle(); expect(arg)
        case "quit": exit(fail == 0 ? 0 : 1)
        default: DiagLog.shared.write(["selftest": "action-inconnue", "ligne": line]); fail += 1
        }
        await settle()
    }

    private static func status(_ s: String) -> AutomationStatus? {
        switch s {
        case "granted": return .granted
        case "denied": return .denied
        case "notdetermined": return .notDetermined
        case "notrunning": return .notRunning
        case "hung": return .unknown(-1)
        default: return nil
        }
    }

    // MARK: Arbre d'accessibilité (VoiceOver) de nos propres fenêtres

    /// `ax-audit main|settings|about` : parcourt l'arbre d'accessibilité de la vue (ce que VoiceOver lit), écrit rôle, présence
    /// d'un libellé, longueur de la valeur (jamais le texte d'une ligne de paroles), et signale les contrôles SANS libellé.
    private func axAudit(_ which: String) {
        let panel = panelNamed(which)
        guard let root = panel.contentView else { return }
        // SwiftUI ne construit son arbre d'accessibilité qu'en présence d'un client (VoiceOver) : on se déclare client, dans
        // NOTRE processus seulement (aucun réglage du système).
        NSApp.accessibilitySetValue(true as NSNumber, forAttribute: .init(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true as NSNumber, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
        root.layoutSubtreeIfNeeded()
        let controlRoles: Set<String> = ["AXButton", "AXSlider", "AXCheckBox", "AXPopUpButton", "AXRadioButton", "AXMenuButton", "AXTextField", "AXSwitch"]
        var rows: [String] = []
        var controls = 0
        var unlabeled: [String] = []
        var count = 0
        func str(_ any: Any?) -> String {
            switch any { case let s as String: return s; case let n as NSNumber: return n.stringValue; default: return "" }
        }
        // Éléments SwiftUI : pas toujours des NSView ; on interroge par sélecteurs (accessibilityRole, …) s'ils répondent.
        func ask(_ o: NSObject, _ name: String) -> Any? {
            let sel = Selector(name)
            guard o.responds(to: sel) else { return nil }
            return o.perform(sel)?.takeUnretainedValue()
        }
        func walk(_ obj: Any, _ depth: Int) {
            guard depth < 40, count < 600, let el = obj as? NSObject else { return }
            count += 1
            let role = str(ask(el, "accessibilityRole"))
            let label = str(ask(el, "accessibilityLabel"))
            let title = str(ask(el, "accessibilityTitle"))
            let value = str(ask(el, "accessibilityValue"))
            let isLyricLine = ["Ligne précédente", "Ligne courante", "Ligne suivante", "Paroles non synchronisées"].contains(label)
            let shownLabel = label.isEmpty ? title : label
            rows.append("\(String(repeating: " ", count: depth))\(role) label=\"\(shownLabel)\" valueLen=\(isLyricLine ? value.count : -1)\(isLyricLine ? "" : " value=\"\(value.prefix(40))\"")")
            if controlRoles.contains(role) {
                controls += 1
                if shownLabel.isEmpty && value.isEmpty { unlabeled.append(role) }
                else if shownLabel.isEmpty { unlabeled.append("\(role)(valeur seule)") }
            }
            for child in (ask(el, "accessibilityChildren") as? [Any]) ?? [] { walk(child, depth + 1) }
        }
        walk(root, 0)
        if count <= 1 {
            let kids = root.accessibilityChildren() ?? []
            DiagLog.shared.write(["ax-debug": "\(type(of: root))", "enfants": kids.count, "sousVues": root.subviews.map { "\(type(of: $0))" }.joined(separator: ","),
                                  "navigation": (root.accessibilityChildrenInNavigationOrder() ?? []).count,
                                  "visibles": (root.accessibilityVisibleChildren() ?? []).count, "ignore": root.isAccessibilityElement(),
                                  "fenetreEnfants": (panel.accessibilityChildren() ?? []).count, "role": root.accessibilityRole()?.rawValue ?? "nil",
                                  "appAX": NSApp.isAccessibilityEnabled()])
        }
        DiagLog.shared.write(["action": "ax-audit", "fenetre": which, "elements": count, "controles": controls,
                              "sansLibelle": unlabeled.count, "sansLibelleListe": unlabeled.joined(separator: ","),
                              "arbre": rows.joined(separator: "\n")])
    }

    /// `ax-press <main|settings|about> <libellé>` : trouve dans l'arbre d'accessibilité (ce que lit VoiceOver) le bouton portant ce libellé
    /// et lui envoie l'action « appuyer » : même chemin que VoiceOver, donc la vraie action du bouton SwiftUI.
    private func axPress(_ arg: String) {
        let words = arg.split(separator: " ", maxSplits: 1).map(String.init)
        guard words.count == 2 else { fail += 1; return }
        let panel = panelNamed(words[0])
        guard let root = panel.contentView else { fail += 1; return }
        NSApp.accessibilitySetValue(true as NSNumber, forAttribute: .init(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true as NSNumber, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
        root.layoutSubtreeIfNeeded()
        func ask(_ o: NSObject, _ name: String) -> Any? {
            let sel = Selector(name)
            guard o.responds(to: sel) else { return nil }
            return o.perform(sel)?.takeUnretainedValue()
        }
        var found: NSObject?
        var count = 0
        func walk(_ obj: Any, _ depth: Int) {
            guard found == nil, depth < 40, count < 800, let el = obj as? NSObject else { return }
            count += 1
            if (ask(el, "accessibilityLabel") as? String) == words[1], (ask(el, "accessibilityRole") as? String) == "AXButton" { found = el; return }
            for child in (ask(el, "accessibilityChildren") as? [Any]) ?? [] { walk(child, depth + 1) }
        }
        walk(root, 0)
        var pressed = false
        if let el = found {
            pressed = (el as AnyObject).accessibilityPerformPress?() ?? false
        }
        DiagLog.shared.write(["action": "ax-press", "fenetre": words[0], "libelle": words[1], "trouve": found != nil, "appui": pressed, "elements": count])
        if found != nil && pressed { pass += 1 } else { fail += 1 }
    }

    private func sendClick(to panel: NSPanel, at p: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            panel.sendEvent(e)
        }
    }

    private func sendDoubleClick(to panel: NSPanel, at p: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1) else { continue }
            panel.sendEvent(e)
        }
    }

    /// Entre dans la Scène en échantillonnant la couche PRÉSENTÉE (celle que le serveur de rendu interpole) : échelle, de la petite
    /// fenêtre au plein écran. Prouve un zoom animé (valeurs intermédiaires distinctes, croissantes) et non un saut.
    private func sceneEnterProbe() async {
        c.scene.enter()
        guard let v = c.scene.view else { fail += 1; return }
        let t0 = ProcessClock.seconds()
        var xs: [Double] = []
        while ProcessClock.seconds() - t0 < 1.0 {
            let p = v.stage.presentation()
            xs.append(Double((p?.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1))
            try? await Task.sleep(for: .milliseconds(20))
        }
        // les premiers échantillons peuvent précéder la validation de la transaction (échelle 1) : on part du premier échantillon réduit
        if let k = xs.firstIndex(where: { $0 < 0.95 }) { xs = Array(xs[k...]) }
        let distinct = Set(xs.map { ($0 * 1000).rounded() }).count
        var monotone = true
        for i in 1..<max(xs.count, 1) where xs[i] < xs[i - 1] - 0.002 { monotone = false }
        let ok = distinct >= 8 && monotone && (xs.first ?? 1) < 0.6 && abs((xs.last ?? 0) - 1) < 0.02
        DiagLog.shared.write(["scene-enter-probe": ok, "echantillons": xs.count, "distinctes": distinct, "monotone": monotone,
                              "debut": ((xs.first ?? 0) * 1000).rounded() / 1000, "fin": ((xs.last ?? 0) * 1000).rounded() / 1000])
        if ok { pass += 1 } else { fail += 1 }
    }

    /// Transition de ligne de la Scène : attend le prochain changement de ligne, puis échantillonne (toutes les ~16 ms pendant 900 ms) les couches
    /// PRÉSENTÉES. Preuve : aucune couche visible (opacité effective > 0,03) du texte de l'ancienne ligne, ni une copie du texte de la nouvelle ligne
    /// autre que sa couche courante (rôle 0), ne se trouve SOUS la nouvelle ligne courante (de plus de 2 pt). Écrit aussi le nombre d'images
    /// où l'ancienne ligne est visible et celui où elle est au-dessus de la nouvelle (la sortie douce doit être vue).
    private func sceneLineProbe() async {
        guard let v = c.scene.view else { DiagLog.shared.write(["scene-line-probe": "pas de Scène", "etat": c.scene.state.rawValue]); fail += 1; return }
        let start = c.model.currentIndex
        var waited = 0.0
        while c.model.currentIndex == start && waited < 9 { try? await Task.sleep(for: .milliseconds(4)); waited += 0.004 }
        let all = c.model.syncedLines
        let now = c.model.currentIndex
        guard start >= 0, now >= 0, start < all.count, now < all.count, now != start else { DiagLog.shared.write(["scene-line-probe": "pas de changement"]); fail += 1; return }
        let oldText = all[start].text, newText = all[now].text
        let t0 = ProcessClock.seconds()
        var n = 0, strayOld = 0, strayNew = 0, oldVisible = 0, oldAbove = 0, noCurrent = 0
        var worstPt = 0.0, oldMaxOpacity = 0.0
        var curMin = Double.infinity, curMax = -Double.infinity
        while ProcessClock.seconds() - t0 < 0.9 {
            let ls = v.debugLineLayers()
            n += 1
            if let cur = ls.filter({ $0.text == newText && $0.role == 0 }).max(by: { $0.opacity < $1.opacity }) {
                if cur.opacity > 0.03 { curMin = min(curMin, cur.y); curMax = max(curMax, cur.y) }
                for l in ls where l.opacity > 0.03 {
                    if l.text == oldText {
                        oldVisible += 1; oldMaxOpacity = max(oldMaxOpacity, l.opacity)
                        if l.y > cur.y + 2 { oldAbove += 1 }
                        if l.y < cur.y - 2 { strayOld += 1; worstPt = max(worstPt, cur.y - l.y) }
                    } else if l.text == newText && l.role != 0 && l.y < cur.y - 2 {
                        strayNew += 1; worstPt = max(worstPt, cur.y - l.y)
                        if strayNew == 1 || strayNew == 25 { DiagLog.shared.write(["dt": Int((ProcessClock.seconds() - t0) * 1000), "old": String(oldText.prefix(12)), "new": String(newText.prefix(12)), "scene-line-detail": ls.map { "\($0.role)|\($0.text.prefix(12))|y\(Int($0.y))|o\(Int($0.opacity * 100))" }.joined(separator: " ; "), "cur": Int(cur.y)]) }
                    }
                }
            } else { noCurrent += 1 }
            try? await Task.sleep(for: .milliseconds(16))
        }
        // la nouvelle ligne glisse VRAIMENT vers sa place (montée visible d'au moins 40 pt) sauf avec « Réduire les animations » (fondu sur place)
        let rise = curMax.isFinite ? curMax - curMin : 0
        let glides = c.model.reduceMotion ? rise < 4 : rise >= 40
        let ok = n >= 30 && noCurrent <= 2 && oldVisible > 0 && strayOld == 0 && strayNew == 0 && glides
        DiagLog.shared.write(["scene-line-probe": ok, "echantillons": n, "ancienneSousLaNouvelle": strayOld, "copieDeLaNouvelleEnDessous": strayNew,
                              "ancienneVisible": oldVisible, "ancienneAuDessus": oldAbove, "ancienneOpaciteMax": (oldMaxOpacity * 100).rounded() / 100,
                              "sansCourante": noCurrent, "pireEcartPt": worstPt.rounded(), "montéeDeLaNouvellePt": rise.rounded(),
                              "layout": c.store.settings.sceneLayout.rawValue, "karaoke": c.store.settings.karaokeFill])
        if ok { pass += 1 } else { fail += 1 }
    }

    /// Attend le prochain changement de ligne dans la Scène, puis échantillonne la part REMPLIE affichée (couches présentées) :
    /// doit croître régulièrement et atteindre 1 au bout de la durée estimée (± 0,4 s).
    private func sceneFillProbe() async {
        guard let v = c.scene.view else { fail += 1; return }
        let start = c.model.currentIndex
        var waited = 0.0
        while c.model.currentIndex == start && waited < 8 { try? await Task.sleep(for: .milliseconds(20)); waited += 0.02 }
        try? await Task.sleep(for: .milliseconds(60))
        guard let mask = v.currentFill else { DiagLog.shared.write(["scene-fill-probe": "pas de masque"]); fail += 1; return }
        let d = v.lastFillDuration
        let t0 = ProcessClock.seconds()
        var samples: [(Double, Double)] = []
        while ProcessClock.seconds() - t0 < d + 1.2 {
            samples.append((ProcessClock.seconds() - t0, mask.presentedFraction()))
            if (samples.last?.1 ?? 0) >= 0.999 { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        let end = samples.first(where: { $0.1 >= 0.999 })?.0 ?? -1
        var monotone = true
        for i in 1..<max(samples.count, 1) where samples[i].1 < samples[i - 1].1 - 0.01 { monotone = false }
        let mid = samples.first(where: { $0.1 >= 0.5 })?.0 ?? -1
        let ok = monotone && end > 0 && abs(end - d) < 0.4 && abs(mid - d / 2) < 0.4 && (samples.first?.1 ?? 1) < 0.3
        DiagLog.shared.write(["scene-fill-probe": ok, "dureeAttendue": (d * 1000).rounded() / 1000, "fin": (end * 1000).rounded() / 1000,
                              "moitie": (mid * 1000).rounded() / 1000, "echantillons": samples.count, "monotone": monotone,
                              "debut": ((samples.first?.1 ?? 0) * 1000).rounded() / 1000])
        if ok { pass += 1 } else { fail += 1 }
    }

    private func panelNamed(_ which: String) -> NSPanel {
        switch which {
        case "settings": return c.settingsController.panel
        case "about": return c.aboutController.panel
        case "scene": return c.scene.panel
        case "welcome": return c.welcomeController.panel
        case "manual": return c.manualSearch.panel
        default: return c.panelController.panel
        }
    }

    private func move(_ arg: String) {
        let v = c.panelController.screen.visibleFrame
        let h = c.panelController.panel.frame.height
        switch arg {
        case "right": c.panelController.move(toCenter: NSPoint(x: v.maxX - LyricsMetrics.windowWidth / 2 - 20, y: v.midY))
        case "left": c.panelController.move(toCenter: NSPoint(x: v.minX + LyricsMetrics.windowWidth / 2 + 20, y: v.midY))
        case "bottom": c.panelController.move(toCenter: NSPoint(x: v.midX, y: v.minY + h / 2 + 40))
        default: c.panelController.move(toCenter: NSPoint(x: v.midX, y: v.midY))
        }
    }

    /// `offset 1.0` (valeur), `offset +0.1` / `offset -0.1` (pas), `offset reset`.
    private func offset(_ arg: String) {
        if arg == "reset" { c.model.setManualOffset(0); return }
        if arg.hasPrefix("+") || arg.hasPrefix("-"), let d = Double(arg), abs(d) <= 0.5 { c.model.adjustOffset(by: d); return }
        if let v = Double(arg) { c.model.setManualOffset(v) }
    }

    private func clearCache() async {
        guard let service = c.model.service else { return }
        await service.clearAll()
        await c.model.refreshStats()
        DiagLog.shared.write(["action": "clearcache", "indexCount": c.model.lastIndexCount])
    }

    /// `wait-for clé=valeur [délai s]` : attend (100 ms) que l'état corresponde ; échec si le délai (10 s) expire.
    private func waitFor(_ arg: String) async {
        let tokens = arg.split(separator: " ").map(String.init)
        guard let pair = tokens.first else { return }
        let timeout = tokens.count > 1 ? (Double(tokens[1]) ?? 10) : 10
        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2 else { return }
        let expectedValue = kv[1].replacingOccurrences(of: "_", with: " ")
        let started = ProcessClock.seconds()
        var ok = false
        while ProcessClock.seconds() - started < timeout {
            let actual = stateDict()[kv[0]].map { "\($0)" } ?? "<absent>"
            if actual == expectedValue || (Double(actual) != nil && Double(expectedValue) != nil && Double(actual) == Double(expectedValue)) { ok = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if ok { pass += 1 } else { fail += 1 }
        let actual = stateDict()[kv[0]].map { "\($0)" } ?? "<absent>"
        DiagLog.shared.write(["wait-for": kv[0], "attendu": expectedValue, "obtenu": actual, "ok": ok,
                              "apres": ((ProcessClock.seconds() - started) * 1000).rounded() / 1000])
    }

    // MARK: Mesure 3 du §5 (faux lecteur, LRC aux horodatages connus, seek et pause)

    /// `measure-sync <décalage>` : joue « phares », seek à 20 s après 9 s, pause de 3 s après 6 s de plus, puis 10 s ;
    /// compare chaque changement de ligne affichée (journal) à l'instant attendu (horodatage − 0,15 s − décalage, sur la
    /// position commandée au faux lecteur). Écrit n, p50, p95, max de |écart| ; critère ≤ 0,25 s.
    private func measureSync(offsetArg: String) async {
        guard let fp = c.fakePlayer else { DiagLog.shared.write(["measure": "sync", "erreur": "pas de faux lecteur"]); fail += 1; return }
        let offset = Double(offsetArg) ?? 0
        fp.perform("stop"); await settle()
        c.model.resetLineChanges()
        let a0 = ProcessClock.seconds(); fp.perform("play", track: "phares"); let tPlay = (a0 + ProcessClock.seconds()) / 2
        var waited = 0
        while c.model.mode != .synced && waited < 100 { try? await Task.sleep(for: .milliseconds(50)); waited += 1 }
        guard let lines = c.model.lyrics?.syncedLines, !lines.isEmpty else {
            DiagLog.shared.write(["measure": "sync", "erreur": "paroles non reçues"]); fail += 1; return
        }
        if offset != 0 { c.model.setManualOffset(offset) }
        try? await Task.sleep(for: .seconds(max(0, 9 - (ProcessClock.seconds() - tPlay))))
        let s0 = ProcessClock.seconds(); fp.perform("seek", track: "20"); let tSeek = (s0 + ProcessClock.seconds()) / 2
        try? await Task.sleep(for: .seconds(6))
        let p0 = ProcessClock.seconds(); fp.perform("pause"); let tPause = (p0 + ProcessClock.seconds()) / 2
        try? await Task.sleep(for: .seconds(3))
        let r0 = ProcessClock.seconds(); fp.perform("resume"); let tResume = (r0 + ProcessClock.seconds()) / 2
        try? await Task.sleep(for: .seconds(10))
        let positionAtPause = 20 + (tPause - tSeek)

        /// Instant attendu où la ligne devient courante, selon la position commandée (par morceaux : lecture, seek, pause, reprise).
        func expected(lineTime: Double) -> Double? {
            let target = lineTime - SyncEngine.lead - offset
            if target >= 0, target < tSeek - tPlay { return tPlay + target }
            if target >= 20, target < positionAtPause { return tSeek + (target - 20) }
            if target >= positionAtPause { return tResume + (target - positionAtPause) }
            return nil
        }
        let arrived = c.model.lyricsArrivedAt ?? 0
        var errors: [Double] = []
        for change in c.model.lineChanges where change.index >= 0 && change.index < lines.count {
            guard change.t > arrived + 0.05, let exp = expected(lineTime: lines[change.index].time) else { continue }
            if abs(change.t - tSeek) < 0.05 { continue }                 // le saut du seek lui-même n'est pas un instant « dû »
            let error = change.t - exp
            errors.append(abs(error))
            DiagLog.shared.write(["measure": "sync-line", "offset": offset, "index": change.index, "lineTime": lines[change.index].time,
                                  "attendu": (exp * 1000).rounded() / 1000, "observe": (change.t * 1000).rounded() / 1000,
                                  "ecart": (error * 1000).rounded() / 1000])
        }
        let sorted = errors.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)] }
        let maxE = sorted.last ?? 0
        let ok = !sorted.isEmpty && pct(0.95) <= 0.25
        if ok { pass += 1 } else { fail += 1 }
        DiagLog.shared.write(["measure": "sync", "offset": offset, "n": sorted.count, "p50": (pct(0.5) * 1000).rounded() / 1000,
                              "p95": (pct(0.95) * 1000).rounded() / 1000, "max": (maxE * 1000).rounded() / 1000, "critere": "p95 <= 0.25", "ok": ok,
                              "tPlay": (tPlay * 1000).rounded() / 1000, "tSeek": (tSeek * 1000).rounded() / 1000,
                              "tPause": (tPause * 1000).rounded() / 1000, "tResume": (tResume * 1000).rounded() / 1000])
        fp.perform("stop")
    }

    private static let keyCodes: [Character: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    /// `shortcut ctrl+opt+cmd+k` / `shortcut k` (sans modificateur : doit être refusé).
    private func shortcut(_ arg: String) {
        let tokens = arg.lowercased().split(separator: "+").map(String.init)
        var mods: UInt32 = 0
        for t in tokens.dropLast() {
            switch t {
            case "ctrl": mods |= HotKeyCombo.carbonControl
            case "opt": mods |= HotKeyCombo.carbonOption
            case "cmd": mods |= HotKeyCombo.carbonCommand
            case "shift": mods |= HotKeyCombo.carbonShift
            default: break
            }
        }
        guard let keyChar = tokens.last?.first, let code = Self.keyCodes[keyChar] else { return }
        let accepted = c.recorder.submit(keyCode: code, carbon: mods, label: String(keyChar).uppercased())
        DiagLog.shared.write(["action": "shortcut", "demande": arg, "acceptee": accepted, "message": c.recorder.message ?? "",
                              "enregistrement": registrationName, "raccourci": c.store.settings.hotKey.display])
    }

    /// `shortcut-block ctrl+opt+cmd+j` : occupe la combinaison, puis l'appelant essaie de l'enregistrer (échec attendu).
    private func shortcutBlock(_ arg: String) {
        let tokens = arg.lowercased().split(separator: "+").map(String.init)
        var mods: UInt32 = 0
        for t in tokens.dropLast() {
            switch t { case "ctrl": mods |= HotKeyCombo.carbonControl; case "opt": mods |= HotKeyCombo.carbonOption
            case "cmd": mods |= HotKeyCombo.carbonCommand; case "shift": mods |= HotKeyCombo.carbonShift; default: break }
        }
        guard let ch = tokens.last?.first, let code = Self.keyCodes[ch] else { return }
        let status = c.hotKey.debugBlock(HotKeyCombo(keyCode: code, modifiers: mods, label: String(ch).uppercased()))
        DiagLog.shared.write(["action": "shortcut-block", "combinaison": arg, "statutBlocage": Int(status)])
    }

    private var registrationName: String {
        switch c.hotKey.registration {
        case .none: return "aucun"
        case .registered: return "enregistré"
        case .failed(let s): return "échec(\(s))"
        }
    }

    private func hotkeyPress() async {
        let before = c.panelController.isShown
        let delivered = c.hotKey.deliverSyntheticPress()
        try? await Task.sleep(for: .milliseconds(300))
        DiagLog.shared.write(["action": "hotkey-press-synthetique", "livre": delivered, "visibleAvant": before,
                              "visibleApres": c.panelController.isShown, "pressCount": c.hotKey.pressCount])
    }

    private func sendKey(_ code: UInt16, to panel: NSPanel) {
        panel.makeKey()
        let chars = code == 49 ? " " : (code == 123 ? "\u{F702}" : "\u{F703}")
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: panel.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                       isARepeat: false, keyCode: code) else { return }
        KeyablePanel.injecting = true
        panel.sendEvent(e)
        KeyablePanel.injecting = false
    }

    private func sendEscape(to panel: NSPanel) {
        panel.makeKey()
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                       isARepeat: false, keyCode: 53) else { return }
        KeyablePanel.injecting = true
        panel.sendEvent(e)
        KeyablePanel.injecting = false
    }

    // MARK: Clics et tests de frappe (points en coordonnées de la fenêtre, origine en bas à gauche)

    private func point(named name: String) -> NSPoint {
        let h = c.panelController.panel.frame.height, w = c.panelController.panel.frame.width
        switch name {
        case "button-style": return NSPoint(x: HoverBarLayout.centerX(of: "style", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
        case "button-scene": return NSPoint(x: HoverBarLayout.centerX(of: "scene", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
        case "button-gear": return NSPoint(x: HoverBarLayout.centerX(of: "gear", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
        case "button-previous": return NSPoint(x: HoverBarLayout.centerX(of: "previous", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
        case "button-playpause": return NSPoint(x: HoverBarLayout.centerX(of: "playpause", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
        case "button-next": return NSPoint(x: HoverBarLayout.centerX(of: "next", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
        case "credit-link": return NSPoint(x: w / 2 + 40, y: 14)
        default: return NSPoint(x: 60, y: h / 2)              // fond, hors texte
        }
    }

    private func hit(_ name: String) {
        let p = point(named: name)
        let view = c.panelController.panel.contentView?.hitTest(p)
        DiagLog.shared.write(["action": "hit", "nom": name, "point": "\(Int(p.x)),\(Int(p.y))", "vue": view.map { String(describing: type(of: $0)) } ?? "nil",
                              "mouseDownCanMoveWindow": view?.mouseDownCanMoveWindow ?? false,
                              "isMovableByWindowBackground": c.panelController.panel.isMovableByWindowBackground])
    }

    /// Clic synthétique envoyé à la fenêtre (aucune permission : l'événement ne quitte pas le processus).
    /// Correctif (clic ⚙ intermittent) : la barre n'accepte les clics que tant que `hovering` est vrai, or le suivi de
    /// survol RÉEL (pointeur de l'utilisateur, ou fenêtre redimensionnée sous le pointeur) peut le remettre à faux entre l'ordre
    /// `hover on` et le clic. Le clic simule donc un pointeur posé sur la barre : il rétablit `hovering`, laisse SwiftUI appliquer
    /// l'état (la barre devient cliquable), puis clique.
    private func click(_ name: String) async {
        let panel = c.panelController.panel
        let pinned = name.hasPrefix("button-") || name == "credit-link"
        defer { if pinned { c.panelController.hoverPinned = false } }
        if pinned {
            c.panelController.hoverPinned = true
            c.model.hovering = true
            try? await Task.sleep(for: .milliseconds(120))
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        let p = point(named: name)
        var hitView = "nil"
        hitView = panel.contentView?.hitTest(p).map { String(describing: type(of: $0)) } ?? "nil"
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            panel.sendEvent(e)
        }
        DiagLog.shared.write(["action": "click", "nom": name, "style": c.store.settings.style.rawValue, "settingsOpen": c.model.settingsOpen,
                              "point": "\(Int(p.x)),\(Int(p.y))", "vue": hitView, "hovering": c.model.hovering])
    }

    /// `resize <zone> <dx> <dy>` : tire la zone de prise (left|right|top|bottom|bottomLeft|…) de (dx, dy) points ÉCRAN (y vers le haut),
    /// avec des événements souris synthétiques envoyés au panneau (cible = la vue de prise réellement touchée, pas un appel direct).
    private func resize(_ arg: String, expectHit: Bool) async {
        let t = arg.split(separator: " ").map(String.init)
        guard t.count == 3 || t.count == 4, let zone = ResizeZone.allCases.first(where: { "\($0)" == t[0] }), let dx = Double(t[1]), let dy = Double(t[2]),
              let handle = c.panelController.handle(for: zone) else { DiagLog.shared.write(["resize": "arguments invalides", "arg": arg]); fail += 1; return }
        let panel = c.panelController.panel
        let before = panel.frame
        let startWin = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        let hit = panel.contentView?.hitTest(startWin)
        let hitZone = (hit as? ResizeHandleView).map { "\($0.zone)" } ?? "\(hit.map { String(describing: type(of: $0)) } ?? "nil")"
        let startScreen = panel.convertPoint(toScreen: startWin)
        func send(_ type: NSEvent.EventType, screen: NSPoint) {
            let loc = panel.convertPoint(fromScreen: screen)
            guard let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            panel.sendEvent(e)
        }
        send(.leftMouseDown, screen: startScreen)
        // 4e argument facultatif : durée en secondes (glissement continu à ~60 événements par seconde, mesure du CPU)
        let steps = t.count == 4 ? max(6, Int((Double(t[3]) ?? 0) * 60)) : 6
        for k in 1...steps {
            send(.leftMouseDragged, screen: NSPoint(x: startScreen.x + dx * Double(k) / Double(steps), y: startScreen.y + dy * Double(k) / Double(steps)))
            try? await Task.sleep(for: .milliseconds(16))
        }
        send(.leftMouseUp, screen: NSPoint(x: startScreen.x + dx, y: startScreen.y + dy))
        try? await Task.sleep(for: .milliseconds(150))
        let after = panel.frame
        func r(_ f: NSRect) -> String { "\(Int(f.minX.rounded())),\(Int(f.minY.rounded())),\(Int(f.width.rounded())),\(Int(f.height.rounded()))" }
        DiagLog.shared.write(["action": "resize", "zone": t[0], "dx": dx, "dy": dy, "vueTouchee": hitZone, "avant": r(before), "apres": r(after),
                              "taillePolice": c.model.fit.currentSize, "resizing": c.panelController.isResizing])
        if (hitZone == t[0]) == expectHit { pass += 1 } else { fail += 1 }
    }

    /// `anim-probe` : attend le prochain changement de ligne, puis échantillonne ~0,9 s à ~120 Hz la couche PRÉSENTÉE (celle que le
    /// serveur de rendu interpole) de la ligne courante : position, échelle, opacité. Prouve que la transition est une animation de
    /// couche (valeurs intermédiaires distinctes, croissantes) et non un saut ; liste aussi les clés d'animation posées.
    private func animProbe() async {
        guard let stack = c.model.lineStack else { DiagLog.shared.write(["anim-probe": "pas de pile"]); fail += 1; return }
        let start = c.model.currentIndex
        var waited = 0.0
        while c.model.currentIndex == start && waited < 8 { try? await Task.sleep(for: .milliseconds(5)); waited += 0.005 }
        guard c.model.currentIndex != start else { DiagLog.shared.write(["anim-probe": "aucun changement de ligne en 8 s"]); fail += 1; return }
        let t0 = ProcessClock.seconds()
        var samples: [(t: Double, y: Double, s: Double, o: Double)] = []
        while ProcessClock.seconds() - t0 < 0.9 {
            if let p = stack.currentLinePresentation() { samples.append((ProcessClock.seconds() - t0, p.y, p.scale, p.opacity)) }
            try? await Task.sleep(for: .milliseconds(8))
        }
        let ys = samples.map(\.y), os = samples.map(\.o), ss = samples.map(\.s)
        let distinctY = Set(ys.map { ($0 * 100).rounded() }).count
        let moved = (ys.max() ?? 0) - (ys.min() ?? 0)
        // dernier instant où la valeur bouge encore = fin effective de l'animation
        var lastMove = 0.0
        for i in 1..<max(samples.count, 1) where abs(samples[i].y - samples[i - 1].y) > 0.01 || abs(samples[i].o - samples[i - 1].o) > 0.002 { lastMove = samples[i].t }
        // sens : y de la courante varie d'une valeur initiale vers la finale sans retour (monotone à 0,05 pt près)
        var monotone = true
        if let first = ys.first, let last = ys.last {
            let sign: Double = last >= first ? 1 : -1
            // Départ = l'échantillon le plus éloigné de la valeur finale : un tout premier échantillon pris AVANT que la transition
            // soit visible dans l'arbre présenté (valeur finale) n'est pas un retour en arrière (flou d'ordonnancement vu 2 fois sur 3).
            let start = ys.indices.max(by: { abs(ys[$0] - last) < abs(ys[$1] - last) }) ?? 0
            if start + 1 < ys.count { for i in (start + 1)..<ys.count where (ys[i] - ys[i - 1]) * sign < -0.05 { monotone = false } }
            _ = first
        }
        DiagLog.shared.write(["anim-probe": "ok", "echantillons": samples.count, "valeursDistinctes": distinctY, "deplacement": (moved * 100).rounded() / 100,
                              "yDepart": ((ys.first ?? 0) * 100).rounded() / 100, "yFin": ((ys.last ?? 0) * 100).rounded() / 100,
                              "echelleDepart": ((ss.first ?? 0) * 1000).rounded() / 1000, "echelleFin": ((ss.last ?? 0) * 1000).rounded() / 1000,
                              "opaciteDepart": ((os.first ?? 0) * 1000).rounded() / 1000, "opaciteFin": ((os.last ?? 0) * 1000).rounded() / 1000,
                              "finDuMouvement": (lastMove * 1000).rounded() / 1000, "monotone": monotone, "mouvement": stack.lastMotion.rawValue,
                              "cles": stack.lastAnimationKeys.joined(separator: " | "),
                              "durees": stack.lastAnimationDurations.map { String($0) }.joined(separator: ",")])
        if distinctY >= 8 && monotone && moved > 4 { pass += 1 } else if stack.lastMotion == .fade { pass += 1 } else { fail += 1 }
    }

    private func animList() {
        guard let stack = c.model.lineStack else { return }
        let rows = stack.layerSnapshot().map { "\($0.key) o=\($0.offset) y=\(Int($0.y.rounded())) s=\(String(format: "%.2f", $0.scale)) a=\(String(format: "%.2f", $0.opacity)) anim=[\($0.animations.joined(separator: ","))]" }
        DiagLog.shared.write(["anim-list": rows.joined(separator: "\n"), "mouvement": stack.lastMotion.rawValue, "cles": stack.lastAnimationKeys.joined(separator: " | ")])
    }

    // MARK: État

    func stateDict() -> [String: Any] {
        var d = stateDictBase()
        for (k, v) in extra { d[k] = v }
        return d
    }

    /// `multiline` : surlignage d'une ligne courante renvoyée à la ligne, mesuré en pixels (`MultilineProof.check`, texte inventé) sur une grille réduite
    /// de polices, graisses, corps et largeurs ; résultats dans l'état (`multilineChecked`, `multilineFailed`, `multilineWorst`).
    private func multilineProof() {
        let r = MultilineProof.check(texts: MultilineProof.texts, fonts: [.system, .newYork, .rounded], weights: [.regular, .bold], sizes: [26, 44], widths: [180, 300, 460], verbose: true)
        extra["multilineChecked"] = r.checked; extra["multilineFailed"] = r.failed; extra["multilineWorst"] = (r.worst * 10).rounded() / 10
        DiagLog.shared.write(["multiline": "grille", "cas": r.checked, "echecs": r.failed, "pire": r.worst])
    }

    /// `winshot <nom>` : image réelle de la petite fenêtre (avec ombre, puis pixels exacts) dans `$PF_SHOTS` (défaut /tmp/lyra-shots), puis uniformité.
    private func winShot(_ argument: String) async {
        let words = argument.split(separator: " ").map(String.init)
        let name = words.first ?? "shot"
        try? await Task.sleep(for: .milliseconds(700))
        let p: NSWindow = words.dropFirst().first == "scene" ? c.scene.panel : c.panelController.panel
        let dir = ProcessInfo.processInfo.environment["PF_SHOTS"] ?? "/tmp/lyra-shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let exact = WindowProof.capture(p, framing: false), let frame = WindowProof.capture(p, framing: true) else {
            fail += 1; DiagLog.shared.write(["winshot": name, "echec": "capture-impossible"]); return
        }
        WindowProof.savePNG(exact, to: "\(dir)/\(name)-exact.png"); WindowProof.savePNG(frame, to: "\(dir)/\(name)-cadre.png")
        let scale = Double(exact.width) / Double(p.frame.width)
        let counts = WindowProof.swatchCounts(of: exact, swatches: Settings.swatches.map { hex in
            let v = Int(hex.dropFirst(), radix: 16) ?? 0; return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF) })
        let best = counts.enumerated().max { $0.element < $1.element }
        extra["shotSwatch"] = (best?.element ?? 0) >= 40 ? best!.offset : -1
        extra["shotSwatchPx"] = best?.element ?? 0
        extra["shotSwatchCounts"] = counts.map(String.init).joined(separator: "/")
        let u = WindowProof.uniformity(of: exact, scale: scale)
        extra["shotW"] = Int((Double(u.width) / scale).rounded()); extra["shotH"] = Int((Double(u.height) / scale).rounded())
        extra["shotAlphaDev"] = (u.alphaDeviation * 100).rounded() / 100; extra["shotLumaDev"] = (u.lumaDeviation * 100).rounded() / 100
        extra["shotAlphaStep"] = (u.alphaStep * 100).rounded() / 100; extra["shotLumaStep"] = (u.lumaStep * 100).rounded() / 100
        extra["shotLeftAlpha"] = (u.leftAlpha * 100).rounded() / 100; extra["shotRightAlpha"] = (u.rightAlpha * 100).rounded() / 100
        extra["shotLeftLuma"] = (u.leftLuma * 100).rounded() / 100; extra["shotRightLuma"] = (u.rightLuma * 100).rounded() / 100
        DiagLog.shared.write(["winshot": name, "frame": "\(Int(p.frame.width))x\(Int(p.frame.height))", "px": "\(exact.width)x\(exact.height)",
                              "alphaDev": u.alphaDeviation, "lumaDev": u.lumaDeviation, "alphaStep": u.alphaStep, "lumaStep": u.lumaStep,
                              "left": "\(u.leftAlpha)/\(u.leftLuma)", "right": "\(u.rightAlpha)/\(u.rightLuma)", "framingPx": "\(frame.width)x\(frame.height)"])
        // Un fond qui ne suit pas la fenêtre fait un SAUT (≈ 11 niveaux de luminance, 2 d'alpha, mesuré avant correction) ; un dégradé lisse reste sous 1,5.
        if words.dropFirst().first == "scene" || (u.lumaStep < 4 && u.alphaStep < 1) { pass += 1 } else { fail += 1 }
        DiagLog.shared.write(["winshot": name, "swatchCounts": counts.map(String.init).joined(separator: "/"), "topBright": WindowProof.topBright(of: exact)])
    }

    func stateDictBase() -> [String: Any] {
        let p = c.panelController.panel
        let s = c.store.settings
        let m = c.model
        func rect(_ f: NSRect) -> String { "\(Int(f.origin.x.rounded())),\(Int(f.origin.y.rounded())),\(Int(f.width.rounded())),\(Int(f.height.rounded()))" }
        var names: [String] = []
        let cb = p.collectionBehavior
        if cb.contains(.canJoinAllSpaces) { names.append("canJoinAllSpaces") }
        if cb.contains(.canJoinAllApplications) { names.append("canJoinAllApplications") }
        if cb.contains(.fullScreenAuxiliary) { names.append("fullScreenAuxiliary") }
        if cb.contains(.stationary) { names.append("stationary") }
        if cb.contains(.ignoresCycle) { names.append("ignoresCycle") }
        let sp = c.settingsController.panel
        let font = FontResolver.resolve(s.font, size: Double(s.size), weight: s.fontWeight)
        let visible = m.visibleLines
        var d: [String: Any] = [
            "level": p.level.rawValue, "collectionBehavior": cb.rawValue, "collectionNames": names.joined(separator: "|"),
            "ignoresMouseEvents": p.ignoresMouseEvents, "frame": rect(p.frame), "frameH": Int(p.frame.height.rounded()),
            "backingScale": p.backingScaleFactor, "visible": p.isVisible, "hasShadow": p.hasShadow,
            "style": s.style.rawValue, "effectiveStyle": m.effectiveStyle(s.style).rawValue, "size": s.size, "opacity": s.backgroundOpacity,
            "font": s.font.rawValue, "fontResolved": font.name, "fontFellBack": font.fellBack, "color": s.colorHex, "colorIndex": s.colorIndex,
            "clickThrough": s.clickThrough, "hotKey": s.hotKey.display, "hotKeyRegistration": registrationName,
            "hotKeyPressCount": c.hotKey.pressCount, "dock": s.showsDockIcon, "activationPolicy": c.activationPolicyName,
            "hovering": m.hovering, "settingsOpen": m.settingsOpen, "settingsSide": c.settingsController.side.rawValue,
            "settingsLevel": sp.level.rawValue, "settingsCollectionBehavior": sp.collectionBehavior.rawValue,
            "settingsIsChild": p.childWindows?.contains(sp) ?? false, "settingsNonactivating": sp.styleMask.contains(.nonactivatingPanel),
            "settingsFrame": rect(sp.frame), "aboutOpen": c.aboutController.isOpen,
            "aboutNonactivating": c.aboutController.panel.styleMask.contains(.nonactivatingPanel), "aboutFrame": rect(c.aboutController.panel.frame),
            "mode": m.mode.rawValue, "title": m.title ?? "", "currentIndex": m.currentIndex,
            "fitCurrentSize": m.fit.currentSize, "fitWindowHeight": Int(m.fit.windowHeight.rounded()), "fitContentHeight": Int(m.fit.contentHeight.rounded()),
            "fitShrunk": m.fit.shrunk, "fitExceedsMax": m.fit.exceedsMaxHeight, "renderedLinesHeight": Int(m.renderedLinesHeight.rounded()),
            "reduceTransparency": m.reduceTransparency, "screens": NSScreen.screens.count,
            "visibleFrame": rect(c.panelController.screen.visibleFrame), "loadOutcome": String(describing: c.store.loadOutcome),
            "menuTitles": c.statusItem.menuTitles.joined(separator: "|"),
            "postEventAccess": CGPreflightPostEventAccess(), "hotKeyMessage": c.model.hotKeyMessage ?? "",
            "recorderMessage": c.recorder.message ?? "",
            // J3 (jamais de texte : compte et longueurs seulement)
            "paused": m.isPaused, "offset": m.manualOffset, "lookup": m.lastLookup, "retryInCeil": Int(m.busyRetryIn.rounded(.up)),
            "visibleCount": visible.filter { !$0.isEmpty }.count, "currentLen": visible[visible.count / 2].count,
            "plainLen": m.plainText.count, "searchHint": m.searchHint, "indexCount": m.lastIndexCount,
            "lyricsKind": m.lyrics.map { $0.isSynced ? "synced" : ($0.plainText != nil ? "plain" : "instrumental") } ?? "none",
            "lrclibID": m.lyrics?.lrclibID ?? 0, "usesNetwork": c.usesNetwork,
            // J5
            "reduceMotion": m.reduceMotion, "animationsOn": m.animation(.linear) != nil, "wakeCount": m.wakeCount,
            "openedURLs": c.openedURLs.count, "forcedReadings": c.fakePlayer?.forcedReadings ?? -1, "openedURLLast": c.openedURLs.last?.absoluteString ?? "", "openedAutomationPane": c.openedURLs.last?.absoluteString.hasSuffix("Privacy_Automation") ?? false,
            "permissionRefused": m.permissionRefused, "spotifyAccess": m.spotifyAccess.map { "\($0)" } ?? "nil",
            "settingsH": Int(sp.frame.height.rounded()), "settingsContentH": Int(m.settingsContentHeight.rounded()),
            "settingsMaxH": Int(m.settingsMaxHeight.rounded()), "settingsFitsVisible": sp.frame.height <= c.settingsController.visibleFrame.height + 0.5,
            "settingsScrolls": m.settingsContentHeight > m.settingsMaxHeight + 0.5, "settingsVisibleH": Int(c.settingsController.visibleFrame.height.rounded()),
            "barText": m.barText.title + (m.barText.artist.map { " | \($0)" } ?? ""),
            "stateTitle": m.display.stateText?.title ?? "", "stateBody": m.display.stateText?.body ?? "",
            "noticeVisible": m.notice != nil, "noticeText": m.notice ?? "", "noticesShown": m.noticesShown.count,
            "stateAction": m.stateActionLabel ?? "", "settingsIsKey": sp.isKeyWindow, "settingsKeyRequests": c.settingsController.keyRequests, "unavailableEntries": m.unavailableEntries,
            "noticeAction": m.noticeAction?.label ?? "",
            "playbackRefused": m.playbackAvailability.refused, "playbackHint": m.playbackAvailability.hint ?? "",
            "spotifyLine": m.spotifyAccess.map { SettingsView.spotifyLine($0) } ?? "",
            "flowStatusProbes": flow.statusProbes, "flowAsks": flow.asks, "flowSent": flow.sent.count, "flowSentLast": flow.sent.last ?? "none",
        ]
        // Fonctions 1.0
        d["lineCount"] = s.lineCount; d["visibleSlots"] = visible.count; d["fontTheme"] = s.fontTheme.rawValue; d["fontWeight"] = s.fontWeight.rawValue
        d["glow"] = s.glow; d["artworkColors"] = s.artworkColors; d["neighbourRatio"] = s.neighbourRatio
        d["paletteAccent"] = m.palette?.accent.hex ?? "none"; d["paletteTint"] = m.palette?.tint.hex ?? "none"
        d["paletteContrast"] = m.palette.map { ($0.accentContrast * 100).rounded() / 100 } ?? 0
        d["lineColor"] = m.lineColor(s).hex; d["accentColor"] = m.accentColor(s).hex
        d["artworkStarted"] = c.artwork.started; d["artworkPlayerReads"] = c.artwork.playerReads; d["artworkHttp"] = c.artwork.httpFetches
        d["artworkCancelled"] = c.artwork.cancelled; d["artworkDelivered"] = c.artwork.delivered; d["artworkSkippedDisabled"] = c.artwork.skippedDisabled
        d["artworkBusy"] = c.artwork.isBusy
        d["playbackEnabled"] = m.playbackAvailability.enabled; d["playbackReason"] = m.playbackAvailability.reason ?? ""
        d["playbackSent"] = m.playbackSent.count; d["playbackLast"] = m.playbackSent.last?.rawValue ?? "none"
        d["lastMotion"] = m.lineStack?.lastMotion.rawValue ?? "none"; d["glides"] = m.lineStack?.glides ?? 0; d["fades"] = m.lineStack?.fades ?? 0; d["trackFades"] = m.lineStack?.trackFades ?? 0
        d["layerCount"] = m.lineStack?.layerCount ?? 0; d["animatedLayers"] = m.lineStack?.animatedLayerCount ?? 0
        d["bitmapDraws"] = m.lineStack?.bitmapDraws ?? 0
        d["drawMsSharp"] = (TextBitmapLayer.drawSeconds[0] * 1000).rounded(); d["drawMsSoft"] = (TextBitmapLayer.drawSeconds[1] * 1000).rounded()
        d["drawsSharp"] = TextBitmapLayer.drawCounts[0]; d["drawsSoft"] = TextBitmapLayer.drawCounts[1]
        // Redimensionnement à la souris
        d["winX"] = Int(p.frame.minX.rounded()); d["winW"] = Int(p.frame.width.rounded()); d["winH"] = Int(p.frame.height.rounded())
        d["windowWidthSetting"] = s.windowWidth.map { Int($0) } ?? -1; d["windowHeightSetting"] = s.windowHeight.map { Int($0) } ?? -1
        d["modelWindowWidth"] = Int(m.windowWidth.rounded()); d["textWidth"] = Int(m.textWidth.rounded())
        d["handlesHidden"] = c.panelController.handle(for: .right)?.isHidden ?? true; d["resizing"] = c.panelController.isResizing
        d["lastCursorZone"] = ResizeHandleView.lastCursorZone.map { "\($0)" } ?? "none"
        d["maxWinW"] = Int((c.panelController.screen.visibleFrame.width * LyricsMetrics.maxResizeFraction).rounded())
        d["maxWinH"] = Int((c.panelController.screen.visibleFrame.height * LyricsMetrics.maxResizeFraction).rounded())
        let gap = SettingsPanelController.gap
        d["settingsAttached"] = !m.settingsOpen || (c.settingsController.side == .right ? abs(sp.frame.minX - (p.frame.maxX + gap)) < 1.5 : abs(sp.frame.maxX - (p.frame.minX - gap)) < 1.5)
        // 1.1.0
        d["welcomeOpen"] = c.welcomeController.isOpen; d["welcomeSeen"] = s.welcomeSeen; d["welcomeOpenCount"] = c.welcomeController.openCount
        d["launchAtLogin"] = s.launchAtLogin; d["loginEnabled"] = c.loginItem.isEnabled(); d["loginPath"] = c.loginItem.lastResult.path.rawValue
        d["loginAgentExists"] = c.loginItem.agentExists; d["loginAgentPath"] = c.loginItem.agentURL.path; d["loginMessage"] = m.loginMessage ?? ""
        d["reopenCount"] = c.reopenCount
        let ms = c.manualSearch.search
        d["manualOpen"] = c.manualSearch.isOpen; d["manualResults"] = ms.results.count; d["manualBusy"] = ms.busy; d["manualStatus"] = ms.status ?? ""
        d["manualChosen"] = ms.chosenID ?? 0; d["manualFirstID"] = ms.results.first?.id ?? 0; d["manualSearchCount"] = ms.searchCount
        d["manualSyncedBadges"] = ms.results.filter(\.synced).count
        d["isManualChoice"] = m.isManualChoice; d["manualKeyWindow"] = c.manualSearch.panel.isKeyWindow
        d["autoHide"] = s.autoHide.rawValue; d["autoHideActions"] = c.autoHideActions.count; d["autoHideLast"] = c.autoHideActions.last.map { "\($0)" } ?? "none"
        d["autoHidden"] = c.autoHide.autoHidden; d["panelShown"] = c.panelController.isShown; d["activity"] = m.activity.rawValue
        d["checkUpdates"] = s.checkUpdates; d["updateTag"] = m.updateRelease?.tag ?? "none"; d["updateRequests"] = c.updates.requestCount
        d["updateOutcome"] = c.updates.lastOutcome.map { "\($0)" } ?? "none"; d["lastUpdateCheckSet"] = s.lastUpdateCheck != nil
        d["updateMenuItem"] = c.statusItem.updateItemVisible
        d["unsyncedAnimating"] = m.unsyncedView?.isAnimating ?? false; d["unsyncedAnimCount"] = m.unsyncedView?.animationCount ?? 0
        d["unsyncedPublishCount"] = m.unsyncedPublishCount; d["unsyncedDuration"] = Int((m.unsyncedView?.lastDuration ?? 0).rounded())
        d["unsyncedTravel"] = Int((m.unsyncedView?.travel ?? 0).rounded()); d["unsyncedStamp"] = m.unsyncedScroll.stamp
        // Scène (1.1.0)
        let sc: SceneController = c.scene; let sv = sc.view
        d["sceneState"] = sc.state.rawValue; d["sceneVisible"] = sc.panel.isVisible; d["sceneLevel"] = sc.panel.level.rawValue
        d["sceneFrame"] = rect(sc.panel.frame); d["sceneScreenName"] = sc.lastScreenName; d["sceneScreenFrame"] = rect(sc.pickScreen().frame)
        d["sceneScreenMatches"] = sc.panel.frame == sc.pickScreen().frame
        d["sceneEnterCount"] = sc.enterCount; d["sceneExitCount"] = sc.exitCount; d["sceneCollection"] = sc.panel.collectionBehavior.rawValue
        d["sceneNonactivating"] = sc.panel.styleMask.contains(.nonactivatingPanel); d["sceneBorderless"] = sc.panel.styleMask.contains(.borderless)
        d["sceneCardShown"] = sv?.cardShownCount ?? -1; d["sceneCardActive"] = sv?.cardActive ?? false; d["sceneCardTitle"] = sv?.cardTitle ?? ""
        d["sceneReflection"] = sv?.reflectionPresent ?? false
        d["sceneGapActive"] = sv?.gapActive ?? false; d["sceneGapAnimating"] = sv?.gapAnimating ?? false
        d["sceneGapStarts"] = sv?.gapStarts ?? -1; d["sceneGapStops"] = sv?.gapStops ?? -1; d["sceneParticleBudget"] = Int((sv?.particleBudget ?? -1).rounded()); d["sceneParticlesOK"] = (sv?.particleBudget ?? 99) <= 30
        d["sceneScrim"] = ((sv?.scrimAlpha ?? 0) * 100).rounded() / 100; d["sceneArtOpacity"] = ((sv?.artTarget ?? 0) * 100).rounded() / 100; d["sceneContrast"] = ((sv?.minContrast ?? 0) * 100).rounded() / 100
        d["sceneContrastOK"] = (sv?.minContrast ?? 0) >= 4.5 - 1e-9
        d["sceneDrift"] = sv?.driftActive ?? false; d["sceneArtLayer"] = sv?.artLayerPresent ?? false; d["sceneBgSwaps"] = sv?.backgroundSwaps ?? -1
        d["sceneFillStarts"] = sv?.fillStarts ?? -1; d["sceneFillDurationMs"] = Int(((sv?.lastFillDuration ?? 0) * 1000).rounded())
        d["sceneFillAnimating"] = sv?.currentFill?.isAnimating ?? false; d["sceneAccentOpacity"] = sv?.accentOpacity ?? -1
        d["sceneCurrentIndex"] = sv?.currentLineIndex ?? -9; d["sceneTextSize"] = Int(sv?.currentTextSize ?? 0); d["sceneTextFrac"] = (sv?.currentTextWidthFraction ?? 0)
        d["sceneLines"] = sv?.lineCount ?? -1; d["sceneShimmer"] = sv?.shimmerPresent ?? false; d["sceneShimmerAnimating"] = sv?.shimmerActive ?? false
        d["sceneVignette"] = sv?.vignetteVisible ?? false; d["sceneGrain"] = sv?.grainVisible ?? false
        d["sceneAnimPaused"] = sv?.animationsPaused ?? false; d["sceneContentOpacity"] = ((sv?.contentOpacity ?? -1) * 100).rounded() / 100
        d["sceneLayout"] = s.sceneLayout.rawValue
        d["sceneArtVisible"] = sv.map { $0.withArtwork && !$0.artPanel.layer.isHidden } ?? false
        d["sceneArtImage"] = sv?.artPanel.hasImage ?? false
        d["sceneArtTitle"] = sv?.artPanel.titleText ?? ""; d["sceneArtArtist"] = sv?.artPanel.artistText ?? ""
        if let v = sv, v.viewWidth > 0 {
            d["sceneArtWidthPct"] = Int((v.artSide / v.viewWidth * 100).rounded()); d["sceneColumnLeftPct"] = Int((v.columnLeft / v.viewWidth * 100).rounded())
            d["sceneTextCenterPct"] = Int((v.textCenterX / v.viewWidth * 100).rounded()); d["sceneTextWidthPct"] = Int((v.textWidth / v.viewWidth * 100).rounded())
        }
        d["sceneBarOpacity"] = ((sv?.barOpacityNow ?? -1) * 100).rounded() / 100
        d["sceneBarElapsed"] = sv?.bar.elapsedText ?? ""; d["sceneBarTotal"] = sv?.bar.totalText ?? ""; d["sceneBarFraction"] = ((sv?.bar.fraction ?? -1) * 1000).rounded() / 1000
        d["sceneBarPlaying"] = sv?.bar.playing ?? false; d["sceneBarCommands"] = (sv?.barCommands ?? []).joined(separator: ",")
        d["playbackSentLast"] = m.playbackSent.last?.rawValue ?? ""; d["playbackSentCount"] = m.playbackSent.count
        d["sceneLeaveCount"] = sv?.leaveCount ?? -1; d["sceneLeaveWords"] = sv?.lastLeave.words ?? -1
        d["sceneLeaveStepMs"] = Int((sv?.lastLeave.stepMs ?? 0).rounded()); d["sceneLeaveTotalMs"] = Int((sv?.lastLeave.totalMs ?? 0).rounded())
        d["sceneLeaveKeys"] = (sv?.lastLeave.containerKeys ?? []).joined(separator: ","); d["sceneLeaveWordAnims"] = sv?.lastLeave.wordKeys ?? -1
        d["sceneBreath"] = sv?.breathActive ?? false; d["sceneBreathRunning"] = sv?.breathRunning ?? false; d["sceneBreathPauses"] = sv?.breathPausedCount ?? -1
        d["sceneEffects"] = s.sceneEffects; d["sceneScreenSetting"] = s.sceneScreen
        d["sceneExitShown"] = sv?.exitControlShown ?? false; d["sceneExitShowCount"] = sv?.exitShowCount ?? -1
        d["sceneExitLabel"] = (sv?.accessibilityChildren()?.first as? NSAccessibilityElement)?.accessibilityLabel() ?? ""
        d["sceneExitFrame"] = sv.map { "\(Int($0.exitControlFrame.width))x\(Int($0.exitControlFrame.height))" } ?? ""
        d["animatedBackground"] = s.animatedBackground; d["karaokeFill"] = s.karaokeFill
        d["smallShimmers"] = ShimmerLayer.created; d["smallShimmersAnimated"] = ShimmerLayer.animated; d["smallDriftStarts"] = ArtworkDriftView.Host.driftStarts
        d["smallFillAnimating"] = m.lineStack?.fillMask?.isAnimating ?? false; d["smallFillRestarts"] = m.lineStack?.fillRestarts ?? -1
        d["smallFillPresent"] = m.lineStack?.fillMask != nil
        d["timerRunning"] = m.timerRunning; d["windowVisible"] = m.windowVisible; d["publishCount"] = m.publishCount; d["fadesAdded"] = m.lineStack?.fades ?? 0
        if let pos = s.position { d["position"] = "\(pos.screenUUID ?? "nil"):\(Int(pos.centerX)),\(Int(pos.centerY))" } else { d["position"] = "aucune" }
        return d
    }

    private func record(_ label: String) {
        var d = stateDict()
        d["state"] = label
        last = d
        DiagLog.shared.write(d)
    }

    /// `expect clé=valeur [clé=valeur …]` contre l'état courant.
    private func expect(_ arg: String) {
        let s = stateDict()
        for pair in arg.split(separator: " ") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let expectedValue = kv[1].replacingOccurrences(of: "_", with: " ")
            let actual = s[kv[0]].map { "\($0)" } ?? "<absent>"
            let ok = actual == expectedValue || (Double(actual) != nil && Double(expectedValue) != nil && Double(actual) == Double(expectedValue))
            if ok { pass += 1 } else { fail += 1 }
            DiagLog.shared.write(["expect": kv[0], "attendu": expectedValue, "obtenu": actual, "ok": ok])
        }
    }
}


/// Sonde et envoi simulés pour l'autotest des boutons de lecture. Thread-safe (la sonde tourne hors du fil principal).
final class FlowSimulator: @unchecked Sendable {
    private let lock = NSLock()
    private var status: AutomationStatus = .notDetermined
    private var answer: AutomationStatus = .granted
    private var holding = false
    private var gate = DispatchSemaphore(value: 0)
    private(set) var statusProbes = 0
    private(set) var asks = 0
    private var sentCommands: [String] = []
    var sent: [String] { lock.withLock { sentCommands } }

    func setStatus(_ s: AutomationStatus) { lock.withLock { status = s } }
    func setAnswer(_ s: AutomationStatus) { lock.withLock { answer = s } }
    func hold(_ on: Bool) { lock.withLock { holding = on } }
    func release(_ s: AutomationStatus) { lock.withLock { answer = s; holding = false }; gate.signal() }

    func probe(_ player: PlayerID, ask: Bool) -> AutomationStatus {
        let (isHolding, current, reply): (Bool, AutomationStatus, AutomationStatus) = lock.withLock {
            if ask { asks += 1 } else { statusProbes += 1 }
            return (holding, status, answer)
        }
        if !ask { return current }
        if isHolding { _ = gate.wait(timeout: .now() + 20) }             // l'invite reste ouverte jusqu'à `flow-release`
        let final = lock.withLock { answer }
        _ = reply
        return final
    }

    func send(_ command: PlaybackCommand, _ player: PlayerID) -> Result<Void, ScriptError> {
        lock.withLock { sentCommands.append("\(player.rawValue):\(command.rawValue)") }
        return .success(())
    }
}
#endif
