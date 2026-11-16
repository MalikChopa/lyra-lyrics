import AppKit
import QuartzCore
import AppSupport
import PlayerKit

/// Éléments de la Scène ajoutés en 1.1.0 (1.1.0) : barre de commandes, pochette nette avec titre, sortie de ligne mot à mot.
/// Tout est en couches Core Animation (aucun redessin par image).

private func sfSymbol(_ name: String, size: Double) -> CGImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// Barre du bas de la Scène : précédent / lecture-pause / suivant, barre de progression fine avec temps écoulé et total, bouton de sortie.
/// Affichée quand la souris bouge, masquée après 3 s (même minuterie que le contrôle de sortie du coin).
@MainActor
final class SceneControlsBar {
    static let height = 96.0
    let layer = CALayer()
    private let names = ["previous", "playPause", "next", "exit"]
    private var buttons: [String: CALayer] = [:]
    private let track = CALayer(), fill = CALayer()
    private let elapsed = CATextLayer(), total = CATextLayer()
    private(set) var playing = false
    private(set) var fraction = 0.0
    private(set) var elapsedText = "0:00", totalText = "-:--"
    private var trackWidth = 0.0

    init() {
        layer.opacity = 0
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        layer.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 22
        for n in names {
            let b = CALayer()
            b.contentsGravity = .center
            b.contentsScale = 2
            buttons[n] = b
            layer.addSublayer(b)
        }
        buttons["previous"]?.contents = sfSymbol("backward.fill", size: 20)
        buttons["next"]?.contents = sfSymbol("forward.fill", size: 20)
        buttons["exit"]?.contents = sfSymbol("arrow.down.right.and.arrow.up.left", size: 16)
        setPlaying(false)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        track.cornerRadius = 2
        fill.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        fill.cornerRadius = 2
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer.addSublayer(track); layer.addSublayer(fill)
        for (t, align) in [(elapsed, CATextLayerAlignmentMode.right), (total, CATextLayerAlignmentMode.left)] {
            t.fontSize = 13
            t.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            t.foregroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            t.alignmentMode = align
            layer.addSublayer(t)
        }
        elapsed.string = elapsedText; total.string = totalText
    }

    /// Place la barre en bas au centre de la scène (coordonnées de la vue, origine en bas à gauche).
    func layout(W: Double, scale: Double) {
        let w = min(W * 0.56, 720)
        layer.bounds = CGRect(x: 0, y: 0, width: w, height: Self.height)
        layer.position = CGPoint(x: W / 2, y: 46 + Self.height / 2)
        let rowY = 66.0
        for (n, x) in [("previous", w / 2 - 74), ("playPause", w / 2), ("next", w / 2 + 74), ("exit", w - 40)] {
            let size = n == "playPause" ? 52.0 : 44.0
            buttons[n]?.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            buttons[n]?.position = CGPoint(x: x, y: rowY)
        }
        trackWidth = w - 2 * 84
        track.frame = CGRect(x: 84, y: 20, width: trackWidth, height: 4)
        fill.bounds = CGRect(x: 0, y: 0, width: trackWidth * fraction, height: 4)
        fill.position = CGPoint(x: 84, y: 22)
        for t in [elapsed, total] { t.contentsScale = scale }
        elapsed.frame = CGRect(x: 14, y: 12, width: 62, height: 18)
        total.frame = CGRect(x: w - 76, y: 12, width: 62, height: 18)
    }

    /// Rectangle d'un bouton en coordonnées de la vue.
    func frame(of name: String) -> CGRect {
        guard let b = buttons[name] else { return .zero }
        let o = layer.frame.origin
        return CGRect(x: o.x + b.position.x - b.bounds.width / 2, y: o.y + b.position.y - b.bounds.height / 2, width: b.bounds.width, height: b.bounds.height)
    }
    var allButtonNames: [String] { names }
    func hit(_ p: CGPoint) -> String? { names.first { frame(of: $0).insetBy(dx: -4, dy: -4).contains(p) } }
    func label(of name: String) -> String {
        switch name {
        case "previous": return "Titre précédent"
        case "next": return "Titre suivant"
        case "exit": return "Quitter le plein écran"
        default: return playing ? "Pause" : "Lecture"
        }
    }

    func setPlaying(_ on: Bool) {
        playing = on
        buttons["playPause"]?.contents = sfSymbol(on ? "pause.fill" : "play.fill", size: 26)
    }

    static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Mise à jour (toutes les 250 ms, seulement quand la barre est visible) : largeur de la barre pleine, textes, icône.
    func update(position: Double, duration: Double?, playing nowPlaying: Bool) {
        if nowPlaying != playing { setPlaying(nowPlaying) }
        fraction = (duration ?? 0) > 0 ? min(1, max(0, position / duration!)) : 0
        let e = Self.format(position), t = duration.map { Self.format($0) } ?? "-:--"
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.bounds = CGRect(x: 0, y: 0, width: trackWidth * fraction, height: 4)
        if e != elapsedText { elapsedText = e; elapsed.string = e }
        if t != totalText { totalText = t; total.string = t }
        CATransaction.commit()
    }
}

/// Pochette nette à gauche de la Scène (coins arrondis, ombre douce, léger reflet comme S19), titre et artiste dessous.
@MainActor
final class SceneArtPanel {
    let layer = CALayer()
    private let tile = CALayer(), image = CALayer(), reflection = CALayer(), note = CATextLayer()
    private let title = CATextLayer(), artist = CATextLayer()
    private(set) var hasImage = false
    private(set) var side = 0.0
    private(set) var titleText = "", artistText = ""

    init() {
        tile.shadowColor = NSColor.black.cgColor
        tile.shadowOpacity = 0.5; tile.shadowRadius = 28; tile.shadowOffset = CGSize(width: 0, height: -12)
        image.masksToBounds = true
        image.contentsGravity = .resizeAspectFill
        image.borderWidth = 1; image.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        note.string = "♪"; note.alignmentMode = .center
        note.foregroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        reflection.opacity = 0.24
        reflection.contentsGravity = .resizeAspectFill
        let mask = CAGradientLayer()
        mask.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.startPoint = CGPoint(x: 0.5, y: 0); mask.endPoint = CGPoint(x: 0.5, y: 1)
        reflection.mask = mask
        for t in [title, artist] { t.alignmentMode = .left; t.truncationMode = .end; t.isWrapped = false }
        tile.addSublayer(image); image.addSublayer(note)
        for l in [reflection, tile, title, artist] { layer.addSublayer(l) }
    }

    /// `x` = bord gauche, `centerY` = milieu de la pochette ; `font` = police des paroles.
    func layout(x: Double, centerY: Double, side: Double, H: Double, scale: Double, font: LyricFont, weight: LyricWeight) {
        self.side = side
        let r = side * 0.045
        tile.frame = CGRect(x: x, y: centerY - side / 2, width: side, height: side)
        tile.shadowPath = CGPath(roundedRect: tile.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        image.frame = tile.bounds; image.cornerRadius = r
        note.fontSize = side * 0.4; note.contentsScale = scale
        note.frame = CGRect(x: 0, y: side * 0.5 - side * 0.28, width: side, height: side * 0.56)
        let rh = side * 0.16
        reflection.frame = CGRect(x: x, y: tile.frame.minY - rh - 2, width: side, height: rh)
        reflection.contentsRect = CGRect(x: 0, y: 0.84, width: 1, height: 0.16)
        reflection.transform = CATransform3DMakeScale(1, -1, 1)
        reflection.mask?.frame = reflection.bounds
        let ts = max(18, H * 0.028), ss = max(14, H * 0.02)
        title.fontSize = ts; artist.fontSize = ss
        title.font = FontResolver.resolve(font, size: ts, weight: weight).nsFont
        artist.font = FontResolver.resolve(font, size: ss, weight: .regular).nsFont
        title.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        artist.foregroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        title.contentsScale = scale; artist.contentsScale = scale
        title.frame = CGRect(x: x, y: tile.frame.minY - ts * 1.7, width: side, height: ts * 1.4)
        artist.frame = CGRect(x: x, y: tile.frame.minY - ts * 1.7 - ss * 1.5, width: side, height: ss * 1.4)
    }

    func setArtwork(_ img: CGImage?, animated: Bool) {
        if animated {
            let t = CATransition(); t.type = .fade; t.duration = 0.8; t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            image.add(t, forKey: "pf.swap"); reflection.add(t, forKey: "pf.swap")
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        image.contents = img; reflection.contents = img
        image.backgroundColor = img == nil ? NSColor.white.withAlphaComponent(0.08).cgColor : nil
        note.opacity = img == nil ? 1 : 0
        reflection.isHidden = img == nil
        CATransaction.commit()
        hasImage = img != nil
    }

    func setTrack(title t: String, artist a: String) {
        titleText = t; artistText = a
        title.string = t; artist.string = a
    }
}

/// Dernière sortie de ligne mot à mot (autotest) : nombre de mots, pas, durée totale, clés d'animation.
struct LeaveRecord {
    var words = 0
    var stepMs = 0.0
    var wordMs = 0.0
    var totalMs = 0.0
    var containerKeys: [String] = []
    var wordKeys = 0
}
