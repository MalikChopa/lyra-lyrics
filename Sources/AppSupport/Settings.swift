import Foundation

public enum BackgroundStyle: String, Codable, CaseIterable, Sendable {
    case solid, glass, clear

    public var label: String {
        switch self {
        case .solid: return "Uni"
        case .glass: return "Verre"
        case .clear: return "Transparent"
        }
    }
    /// ◐ : Uni → Verre → Transparent → Uni.
    public var next: BackgroundStyle {
        switch self {
        case .solid: return .glass
        case .glass: return .clear
        case .clear: return .solid
        }
    }
}

public enum LyricFont: String, Codable, CaseIterable, Sendable {
    case system, newYork, sfMono, avenirNext, rounded

    public var label: String {
        switch self {
        case .system: return "Système (SF Pro)"
        case .newYork: return "New York (serif)"
        case .sfMono: return "SF Mono"
        case .avenirNext: return "Avenir Next"
        case .rounded: return "SF Arrondie"
        }
    }
}

/// Graisse de la police des paroles (les thèmes de police règlent aussi la graisse).
public enum LyricWeight: String, Codable, CaseIterable, Sendable {
    case light, regular, semibold, bold

    public var label: String {
        switch self {
        case .light: return "Fin"
        case .regular: return "Normal"
        case .semibold: return "Semi-gras"
        case .bold: return "Gras"
        }
    }
}

/// Nombre de lignes visibles : 1, 3 (défaut) ou 5.
public enum LineCount {
    public static let allowed = [1, 3, 5]
    public static let `default` = 3
    /// Valeur autorisée la plus proche (2 -> 3 : en cas d'égalité on garde plus de lignes ; hors plage -> bornes).
    public static func clamped(_ n: Int) -> Int {
        if n <= 1 { return 1 }
        if n >= 5 { return 5 }
        return n == 2 ? 3 : (n == 4 ? 5 : n)
    }
}

/// Thèmes de police prêts à l'emploi. Un thème règle police, graisse, couleur de pastille, halo et
/// rapport de taille des voisines d'un coup ; les réglages individuels restent disponibles. « Personnalisé » = aucun thème
/// ne correspond aux valeurs courantes (déduit des champs, jamais stocké : il ne peut pas se désynchroniser).
public enum FontTheme: String, Codable, CaseIterable, Sendable {
    case classic, elegant, neon, minimal, custom

    public static let ready: [FontTheme] = [.classic, .elegant, .neon, .minimal]

    public var label: String {
        switch self {
        case .classic: return "Classique"
        case .elegant: return "Élégant"
        case .neon: return "Néon"
        case .minimal: return "Minimal"
        case .custom: return "Personnalisé"
        }
    }

    public struct Spec: Equatable, Sendable {
        public var font: LyricFont
        public var weight: LyricWeight
        public var colorIndex: Int
        public var glow: Bool
        public var neighbourRatio: Double
    }

    /// `nil` pour « Personnalisé ».
    public var spec: Spec? {
        switch self {
        case .classic: return Spec(font: .system, weight: .bold, colorIndex: 0, glow: false, neighbourRatio: 0.66)
        case .elegant: return Spec(font: .newYork, weight: .semibold, colorIndex: 1, glow: false, neighbourRatio: 0.70)
        case .neon: return Spec(font: .rounded, weight: .bold, colorIndex: 2, glow: true, neighbourRatio: 0.62)
        case .minimal: return Spec(font: .system, weight: .light, colorIndex: 0, glow: false, neighbourRatio: 0.72)
        case .custom: return nil
        }
    }
}

/// Quand masquer la fenêtre toute seule (1.1.0, C1). Jamais par-dessus un masquage ou un affichage manuel.
public enum AutoHideMode: String, Codable, CaseIterable, Sendable {
    case never, paused, idle

    public var label: String {
        switch self {
        case .never: return "Jamais"
        case .paused: return "En pause"
        case .idle: return "Quand rien ne joue"
        }
    }
}

/// Mise en page de la Scène (1.1.0) : paroles seules, ou pochette nette à gauche et paroles à droite (défaut).
public enum SceneLayoutMode: String, Codable, CaseIterable, Sendable {
    case lyricsOnly, withArtwork

    public var label: String {
        switch self {
        case .lyricsOnly: return "Paroles seules"
        case .withArtwork: return "Avec la pochette"
        }
    }
}

/// Position mémorisée : centre de la fenêtre relatif au coin bas-gauche de l'écran, avec l'UUID de l'écran (§4).
public struct WindowPosition: Codable, Equatable, Sendable {
    public var screenUUID: String?
    public var centerX: Double
    public var centerY: Double
    public init(screenUUID: String?, centerX: Double, centerY: Double) {
        self.screenUUID = screenUUID; self.centerX = centerX; self.centerY = centerY
    }
}

/// Réglages versionnés. Valeurs par défaut et pastilles = celles de la maquette de conception.
public struct Settings: Codable, Equatable, Sendable {
    /// Version 2 (1.1.0, 2026-10-28) : « Remplissage karaoké » ramené à désactivé une seule fois pour les réglages enregistrés en version 1
    /// (l'utilisateur ne l'aime pas ; la Scène l'imposait jusque-là), puis il redevient un choix libre.
    public static let currentVersion = 2
    public static let sizeRange = 18...44
    public static let opacityRange = 0...85
    /// Pastilles de couleur de la maquette (`#colors i[data-c]`).
    public static let swatches = ["#ffffff", "#ffe27a", "#8fd3ff", "#ffb3d1", "#a8f0b4"]

    public var version: Int = Settings.currentVersion
    public var style: BackgroundStyle = .glass
    public var size: Int = 26
    /// « Opacité fond » en pourcentage (0–85, défaut 38).
    public var backgroundOpacity: Int = 38
    public var font: LyricFont = .system
    public var colorIndex: Int = 0
    public var clickThrough: Bool = false
    public var hotKey: HotKeyCombo = defaultHotKey
    public var position: WindowPosition? = nil
    /// Décision utilisateur du 2026-10-22 (point J2) : case « Icône dans le Dock » DÉCOCHÉE par défaut (`.accessory`), car avec
    /// l'icône (`.regular`) les paroles ne s'affichent plus par-dessus une app en plein écran (test réel TextEdit). Même clé
    /// qu'avant : une valeur `true` déjà stockée reste `true`.
    public var showsDockIcon: Bool = false
    /// lignes visibles (1, 3, 5), graisse, halo, rapport de taille des voisines (réglés par les thèmes de police,
    /// sans commande propre pour le rapport) et « Couleurs de la pochette » (activé par défaut ; désactivé = aucune requête de pochette).
    public var lineCount: Int = LineCount.default
    public var fontWeight: LyricWeight = .bold
    public var glow: Bool = false
    public var neighbourRatio: Double = 0.66
    public var artworkColors: Bool = true
    /// Taille de fenêtre imposée par le redimensionnement à la souris (nil = automatique : 460 pt de large, hauteur selon le contenu).
    public var windowWidth: Double? = nil
    public var windowHeight: Double? = nil
    // 1.1.0
    /// Accueil du premier lancement déjà montré.
    public var welcomeSeen: Bool = false
    /// Case « Lancer à l'ouverture de session » (intention de l'utilisateur ; l'état réel est relu auprès du système).
    public var launchAtLogin: Bool = false
    public var autoHide: AutoHideMode = .idle
    /// « Vérifier les mises à jour » (une requête par jour au plus, vers api.github.com).
    public var checkUpdates: Bool = true
    /// Date (secondes depuis 1970) de la dernière vérification.
    public var lastUpdateCheck: Double? = nil
    /// Scène : écran choisi. « window » = écran de la fenêtre (défaut), « main » = écran principal, « name:<nom> » = par nom.
    public var sceneScreen: String = "window"
    /// Scène : grain et vignette discrets.
    public var sceneEffects: Bool = true
    /// Fond animé tiré de la pochette (petite fenêtre, désactivé par défaut) et « Remplissage karaoké » (petite fenêtre ET Scène, désactivé par défaut).
    public var animatedBackground: Bool = false
    public var karaokeFill: Bool = false
    /// Scène : mise en page (défaut « Avec la pochette »).
    public var sceneLayout: SceneLayoutMode = .withArtwork

    public init() {}

    /// Taille imposée valide (les deux valeurs présentes).
    public var manualSize: (width: Double, height: Double)? {
        guard let w = windowWidth, let h = windowHeight else { return nil }
        return (w, h)
    }

    /// Thème de police correspondant exactement aux valeurs courantes, sinon « Personnalisé ».
    public var fontTheme: FontTheme {
        let current = FontTheme.Spec(font: font, weight: fontWeight, colorIndex: colorIndex, glow: glow, neighbourRatio: neighbourRatio)
        return FontTheme.ready.first { $0.spec == current } ?? .custom
    }

    /// Applique un thème d'un coup (sans effet pour « Personnalisé »). La taille de police n'est pas touchée.
    public mutating func apply(theme: FontTheme) {
        guard let spec = theme.spec else { return }
        font = spec.font; fontWeight = spec.weight; colorIndex = spec.colorIndex; glow = spec.glow; neighbourRatio = spec.neighbourRatio
    }

    public var colorHex: String { Settings.swatches[min(max(colorIndex, 0), Settings.swatches.count - 1)] }

    /// Ramène chaque valeur dans sa plage.
    public mutating func clamp() {
        size = min(max(size, Settings.sizeRange.lowerBound), Settings.sizeRange.upperBound)
        backgroundOpacity = min(max(backgroundOpacity, Settings.opacityRange.lowerBound), Settings.opacityRange.upperBound)
        colorIndex = min(max(colorIndex, 0), Settings.swatches.count - 1)
        lineCount = LineCount.clamped(lineCount)
        if let w = windowWidth, let h = windowHeight, w.isFinite, h.isFinite {
            windowWidth = max(w, LyricsMetrics.minResizeWidth); windowHeight = max(h, LyricsMetrics.minResizeHeight)
        } else { windowWidth = nil; windowHeight = nil }
        neighbourRatio = neighbourRatio.isFinite ? min(max(neighbourRatio, 0.5), 0.85) : 0.66
        if !hotKey.isValid { hotKey = defaultHotKey }
        if let p = position, !p.centerX.isFinite || !p.centerY.isFinite { position = nil }
    }

    // Décodage tolérant : champ absent → valeur par défaut ; valeur hors plage → ramenée dans la plage.
    private enum CodingKeys: String, CodingKey {
        case version, style, size, backgroundOpacity, font, colorIndex, clickThrough, hotKey, position, showsDockIcon
        case lineCount, fontWeight, glow, neighbourRatio, artworkColors, windowWidth, windowHeight
        case welcomeSeen, launchAtLogin, autoHide, checkUpdates, lastUpdateCheck, sceneScreen, sceneEffects, animatedBackground, karaokeFill, sceneLayout
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        style = (try? c.decodeIfPresent(BackgroundStyle.self, forKey: .style)) ?? d.style
        size = (try? c.decodeIfPresent(Int.self, forKey: .size)) ?? d.size
        backgroundOpacity = (try? c.decodeIfPresent(Int.self, forKey: .backgroundOpacity)) ?? d.backgroundOpacity
        font = (try? c.decodeIfPresent(LyricFont.self, forKey: .font)) ?? d.font
        colorIndex = (try? c.decodeIfPresent(Int.self, forKey: .colorIndex)) ?? d.colorIndex
        clickThrough = (try? c.decodeIfPresent(Bool.self, forKey: .clickThrough)) ?? d.clickThrough
        hotKey = (try? c.decodeIfPresent(HotKeyCombo.self, forKey: .hotKey)) ?? d.hotKey
        position = try? c.decodeIfPresent(WindowPosition.self, forKey: .position)
        showsDockIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showsDockIcon)) ?? d.showsDockIcon
        lineCount = (try? c.decodeIfPresent(Int.self, forKey: .lineCount)) ?? d.lineCount
        fontWeight = (try? c.decodeIfPresent(LyricWeight.self, forKey: .fontWeight)) ?? d.fontWeight
        glow = (try? c.decodeIfPresent(Bool.self, forKey: .glow)) ?? d.glow
        neighbourRatio = (try? c.decodeIfPresent(Double.self, forKey: .neighbourRatio)) ?? d.neighbourRatio
        artworkColors = (try? c.decodeIfPresent(Bool.self, forKey: .artworkColors)) ?? d.artworkColors
        windowWidth = try? c.decodeIfPresent(Double.self, forKey: .windowWidth)
        windowHeight = try? c.decodeIfPresent(Double.self, forKey: .windowHeight)
        welcomeSeen = (try? c.decodeIfPresent(Bool.self, forKey: .welcomeSeen)) ?? d.welcomeSeen
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        autoHide = (try? c.decodeIfPresent(AutoHideMode.self, forKey: .autoHide)) ?? d.autoHide
        checkUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .checkUpdates)) ?? d.checkUpdates
        lastUpdateCheck = try? c.decodeIfPresent(Double.self, forKey: .lastUpdateCheck)
        sceneScreen = (try? c.decodeIfPresent(String.self, forKey: .sceneScreen)) ?? d.sceneScreen
        sceneEffects = (try? c.decodeIfPresent(Bool.self, forKey: .sceneEffects)) ?? d.sceneEffects
        animatedBackground = (try? c.decodeIfPresent(Bool.self, forKey: .animatedBackground)) ?? d.animatedBackground
        karaokeFill = (try? c.decodeIfPresent(Bool.self, forKey: .karaokeFill)) ?? d.karaokeFill
        sceneLayout = (try? c.decodeIfPresent(SceneLayoutMode.self, forKey: .sceneLayout)) ?? d.sceneLayout
        clamp()
    }

    public enum DecodeOutcome: Equatable, Sendable {
        case ok, missing, corrupt, newerVersion(Int)
    }

    /// Décode des données stockées. Données absentes ou illisibles → défauts ; version plus récente que la nôtre → défauts
    /// (on ne sait pas l'interpréter, et on ne plante pas).
    public static func decode(_ data: Data?) -> (Settings, DecodeOutcome) {
        guard let data else { return (Settings(), .missing) }
        struct VersionProbe: Decodable { var version: Int? }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { return (Settings(), .corrupt) }
        if let v = probe.version, v > currentVersion { return (Settings(), .newerVersion(v)) }
        guard var s = try? JSONDecoder().decode(Settings.self, from: data) else { return (Settings(), .corrupt) }
        if (probe.version ?? 1) < 2 { s.karaokeFill = false }
        s.version = currentVersion
        return (s, .ok)
    }

    public func encoded() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try? e.encode(self)
    }
}
