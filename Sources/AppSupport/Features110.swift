import Foundation

// 1.1.0 : logique pure (Foundation seule, testable sans interface) des améliorations de la partie 1.

// MARK: E1 : vérification des mises à jour

/// Vérification des mises à jour : UNE requête GET par jour au plus vers l'API publique de GitHub (aucune donnée envoyée hormis
/// le User-Agent de l'app). Ici : seulement la logique pure (URL, lecture de la réponse, comparaison de versions, cadence).
public enum UpdateCheck {
    public static let host = "api.github.com"
    public static let repository = "MalikChopa/lyra-lyrics"
    public static let endpoint = URL(string: "https://api.github.com/repos/MalikChopa/lyra-lyrics/releases/latest")!
    public static let interval: TimeInterval = 24 * 3600

    public struct Release: Equatable, Sendable {
        public var tag: String
        public var url: URL
        public init(tag: String, url: URL) { self.tag = tag; self.url = url }
    }

    public enum Outcome: Equatable, Sendable {
        case newer(Release)
        case upToDate
        case failed
    }

    /// `tag_name` et `html_url` de la réponse. Le lien n'est accepté que s'il pointe vers github.com, dans le dépôt de l'app
    /// (la réponse est une donnée, pas une instruction : aucun autre lien ne sera jamais ouvert).
    public static func parse(_ data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String, !tag.isEmpty, tag.count <= 40,
              let link = object["html_url"] as? String, let url = URL(string: link), isTrusted(url) else { return nil }
        return Release(tag: tag, url: url)
    }

    public static let repositoryName = "lyra-lyrics"

    /// Lien accepté : https, github.com, dépôt `lyra-lyrics`, rubrique `releases`. Le propriétaire n'est PAS figé : l'API de GitHub renvoie
    /// le dépôt sous le nom de compte actuel quand le compte a été renommé (redirection 301 constatée le 2026-10-27), et ce nom peut
    /// encore changer ; seul un lien vers une page de versions de ce dépôt, sur github.com, sera jamais ouvert.
    public static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "github.com", url.user == nil, url.port == nil else { return false }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        return parts.count >= 3 && parts[1] == repositoryName && parts[2] == "releases"
    }

    /// Composantes numériques d'une version (« v1.2.3 » → [1, 2, 3]) ; `nil` si illisible.
    public static func components(_ version: String) -> [Int]? {
        var v = version.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        if let dash = v.firstIndex(where: { $0 == "-" || $0 == "+" }) { v = String(v[..<dash]) }
        let parts = v.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let r = components(remote), let l = components(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Une vérification est due si la dernière date de plus de 24 h (ou n'a jamais eu lieu, ou est dans le futur).
    public static func isDue(last: Double?, now: Double) -> Bool {
        guard let last else { return true }
        return now - last >= interval || last > now + 3600
    }

    public static func outcome(data: Data, localVersion: String) -> Outcome {
        guard let release = parse(data) else { return .failed }
        return isNewer(release.tag, than: localVersion) ? .newer(release) : .upToDate
    }
}

// MARK: A2 : lancement à l'ouverture de session (repli LaunchAgent)

public enum LaunchAgent {
    /// `~/Library/LaunchAgents/<identifiant>.plist` : écrit SEULEMENT quand l'utilisateur coche la case, supprimé quand il la décoche.
    public static func url(label: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func plist(label: String, appPath: String) -> Data? {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

// MARK: C1 : masquage automatique

public enum PlaybackActivity: String, Sendable { case nothing, paused, playing }

/// Masquage automatique. Jamais par-dessus un choix manuel : seule la fenêtre que NOUS avons masquée est remontrée, et un
/// affichage manuel pendant la condition la garde affichée jusqu'à ce que la condition disparaisse puis revienne.
public struct AutoHideState: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case hide, show }
    public private(set) var autoHidden = false
    public private(set) var overrideActive = false
    public private(set) var lastCondition = false

    public init() {}

    public static func condition(mode: AutoHideMode, activity: PlaybackActivity) -> Bool {
        switch mode {
        case .never: return false
        case .paused: return activity != .playing
        case .idle: return activity == .nothing
        }
    }

    public mutating func evaluate(mode: AutoHideMode, activity: PlaybackActivity, windowShown: Bool) -> Action? {
        let cond = Self.condition(mode: mode, activity: activity)
        lastCondition = cond
        if cond {
            if windowShown && !overrideActive && !autoHidden { autoHidden = true; return .hide }
            return nil
        }
        overrideActive = false
        if autoHidden { autoHidden = false; return windowShown ? nil : .show }
        return nil
    }

    /// À appeler après un masquage / affichage fait par l'utilisateur (raccourci, menu).
    public mutating func manualChange(windowShown: Bool) {
        if windowShown { autoHidden = false; overrideActive = lastCondition } else { autoHidden = false; overrideActive = false }
    }
}

// MARK: S10 : choix de l'écran de la Scène

public enum SceneScreenChoice {
    public static let window = "window", main = "main"
    public static func named(_ name: String) -> String { "name:\(name)" }

    /// Indice de l'écran à utiliser. Écran introuvable (débranché) → écran de la fenêtre.
    public static func pick(setting: String, names: [String], mainIndex: Int, windowIndex: Int) -> Int {
        guard !names.isEmpty else { return 0 }
        let w = min(max(windowIndex, 0), names.count - 1)
        if setting == main { return min(max(mainIndex, 0), names.count - 1) }
        if setting.hasPrefix("name:") {
            let wanted = String(setting.dropFirst(5))
            return names.firstIndex(of: wanted) ?? w
        }
        return w
    }
}

// MARK: Scène : calculs purs

public enum SceneMath {
    // S5 : remplissage progressif
    public static let fillCap = 7.0
    public static let fillMin = 0.8
    public static let lastLineDuration = 4.0

    /// Durée estimée du chant d'une ligne : temps jusqu'à la ligne suivante, moins un souffle, bornée (7 s au plus).
    public static func fillDuration(lines: [LyricLineTime], index: Int) -> Double {
        guard index >= 0, index < lines.count else { return fillMin }
        let gap = index + 1 < lines.count ? lines[index + 1].time - lines[index].time : lastLineDuration
        return min(fillCap, max(fillMin, gap * 0.92))
    }

    /// Part remplie (0…1) à la position (déjà corrigée du décalage) pour une ligne qui commence à `start`.
    public static func fillFraction(position: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (position - start) / duration))
    }

    // S6 : passages sans paroles
    public static let gapThreshold = 6.0
    public static let gapFadeOut = 1.0

    /// Durée estimée du chant d'une ligne de texte (pour repérer les trous).
    public static func sungDuration(of text: String) -> Double { min(6, 1.2 + 0.06 * Double(text.count)) }

    public struct Gap: Equatable, Sendable {
        public var start: Double
        public var end: Double
        /// Fin de l'animation : 1 s avant la ligne suivante.
        public var fadeOutAt: Double { max(start, end - SceneMath.gapFadeOut) }
        public init(start: Double, end: Double) { self.start = start; self.end = end }
    }

    /// Passages sans paroles : avant la première ligne (> 6 s), entre deux lignes (> 6 s après le chant estimé de la première, ou
    /// ligne vide « ♪ » de 3 s au moins), et après la dernière (> 6 s avant la fin du titre, si la durée est connue).
    public static func gaps(lines: [LyricLineTime], placeholder: String, duration: Double?) -> [Gap] {
        var out: [Gap] = []
        guard let first = lines.first else { return out }
        if first.time > gapThreshold && first.text != placeholder { out.append(Gap(start: 0, end: first.time)) }
        for i in lines.indices {
            let l = lines[i]
            let next = i + 1 < lines.count ? lines[i + 1].time : duration
            guard let end = next else { continue }
            if l.text == placeholder {
                if end - l.time >= 3 { out.append(Gap(start: l.time, end: end)) }
            } else {
                let sungUntil = l.time + sungDuration(of: l.text)
                if end - sungUntil > gapThreshold { out.append(Gap(start: sungUntil, end: end)) }
            }
        }
        return out
    }

    /// Passage en cours à `position` (début inclus, fin exclue).
    public static func gap(at position: Double, in gaps: [Gap]) -> Gap? { gaps.first { position >= $0.start && position < $0.end } }

    // S4 : taille du texte courant
    /// Plus grande taille (≤ `maxSize`) pour laquelle le texte, renvoyé à la ligne dans `width`, tient dans `maxHeight`.
    public static func fitSize(text: String, width: Double, maxHeight: Double, maxSize: Double, minSize: Double = 28,
                               measure: (String, Double, Double) -> Double) -> Double {
        var size = maxSize
        while size > minSize && measure(text, size, width) > maxHeight { size = max(minSize, (size * 0.94).rounded(.down)) }
        return size
    }

    // Contraste du texte sur le fond de la Scène
    /// Luminance relative maximale admise sous le texte pour qu'un texte de luminance `textLuminance` garde 4,5 : 1.
    public static func maxBackgroundLuminance(forText textLuminance: Double, ratio: Double = 4.5) -> Double {
        max(0, (textLuminance + 0.05) / ratio - 0.05)
    }

    /// Opacité du voile noir à poser sur un fond de luminance maximale `background` pour garder 4,5 : 1 au texte de luminance
    /// `textLuminance` (la luminance linéaire d'un fond voilé vaut `background × (1 − voile)`). Au moins 0,30 (ambiance).
    public static func scrimAlpha(backgroundLuminance background: Double, textLuminance: Double, minimum: Double = 0.30) -> Double {
        let allowed = maxBackgroundLuminance(forText: textLuminance)
        guard background > 0 else { return minimum }
        return min(0.92, max(minimum, 1 - allowed / background))
    }

    /// Réglage du fond de la Scène : opacité de la pochette floutée et voile noir qui gardent `textLuminance` à ≥ 4,5 : 1.
    /// Fond effectif = (L_pochette × a + L_dégradé × (1 − a)) × (1 − voile). Voile de 0,30 au moins (ambiance) ; la pochette s'efface
    /// d'abord (a de 0,92 vers 0) tant que le contraste n'y est pas ; si le dégradé seul ne suffit pas, le voile monte.
    public static func background(artLuminance: Double, gradientLuminance: Double, textLuminance: Double) -> (artOpacity: Double, scrim: Double, contrast: Double) {
        func effective(_ a: Double, _ s: Double) -> Double { (artLuminance * a + gradientLuminance * (1 - a)) * (1 - s) }
        func ratio(_ a: Double, _ s: Double) -> Double { contrast(textLuminance: textLuminance, backgroundLuminance: effective(a, s), scrim: 0) }
        var scrim = 0.30
        while scrim <= 0.95 {
            var a = 0.92
            while a >= 0 {
                if ratio(a, scrim) >= 4.5 { return (a, scrim, ratio(a, scrim)) }
                a -= 0.04
            }
            scrim += 0.05
        }
        return (0, 0.95, ratio(0, 0.95))
    }

    /// Contraste obtenu pour ce fond voilé.
    public static func contrast(textLuminance: Double, backgroundLuminance: Double, scrim: Double) -> Double {
        let bg = backgroundLuminance * (1 - scrim)
        return (max(textLuminance, bg) + 0.05) / (min(textLuminance, bg) + 0.05)
    }
}

/// Ligne horodatée sans dépendance à LyricsCore (AppSupport reste autonome).
public struct LyricLineTime: Equatable, Sendable {
    public var time: Double
    public var text: String
    public init(time: Double, text: String) { self.time = time; self.text = text }
}
