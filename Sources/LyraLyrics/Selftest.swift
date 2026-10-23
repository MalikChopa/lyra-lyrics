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
    /// Autorisation et envoi simulés pour les boutons de lecture (aucun Apple event, aucune invite).
    private let flow = FlowSimulator()

    private func numeric(_ any: Any?) -> Double {
        switch any { case let d as Double: return d; case let i as Int: return Double(i); case let s as String: return Double(s) ?? .nan; default: return .nan }
    }

    init(controller: AppController) { c = controller }

    func run(scriptPath: String) {
        ResizeHandleView.ignoreRealEvents = true
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
        let panel: NSPanel = which == "settings" ? c.settingsController.panel : (which == "about" ? c.aboutController.panel : c.panelController.panel)
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
        let panel: NSPanel = words[0] == "settings" ? c.settingsController.panel : (words[0] == "about" ? c.aboutController.panel : c.panelController.panel)
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

    private func sendEscape(to panel: NSPanel) {
        panel.makeKey()
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                       isARepeat: false, keyCode: 53) else { return }
        panel.sendEvent(e)
    }

    // MARK: Clics et tests de frappe (points en coordonnées de la fenêtre, origine en bas à gauche)

    private func point(named name: String) -> NSPoint {
        let h = c.panelController.panel.frame.height, w = c.panelController.panel.frame.width
        switch name {
        case "button-style": return NSPoint(x: HoverBarLayout.centerX(of: "style", windowWidth: w), y: h - HoverBarLayout.centerFromTop)
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
        d["lineColor"] = m.lineColor(s).hex
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
