import AppKit
import SwiftUI
import AppSupport

/// Flou du fond derrière la fenêtre (`NSVisualEffectView`, `.behindWindow`, `.active`, `.hudWindow`, §4 : délégué).
/// Ne rend rien hors d'une vraie fenêtre non opaque affichée (le flou est fait par le Window Server).
struct VisualEffectBlur: NSViewRepresentable {
    var radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        #if DEBUG
        // Captures (--snapshot) : `cacheDisplay` ne sait pas rendre le flou du Window Server et peint un aplat gris ;
        // on le masque pour que la teinte et le dégradé se voient sur le faux bureau (le flou reste NON montré).
        if SnapshotFlags.skipBlur { v.alphaValue = 0 }
        #endif
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.maskImage = Self.maskImage(radius: radius)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.maskImage = Self.maskImage(radius: radius)
    }

    /// Image étirable à coins arrondis (la façon documentée d'arrondir un effet « derrière la fenêtre »).
    static func maskImage(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Carte « verre » de la maquette : flou + teinte + dégradé blanc 135° + bordure + reflet haut.
struct GlassCard: View {
    var tint: Color
    var tintOpacity: Double
    var radius: Double
    var gradientStart: Double = 0.20
    var gradientEnd: Double = 0.05
    var border: Double = 0.22
    var highlight: Double = 0.35

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            VisualEffectBlur(radius: radius)
            shape.fill(tint.opacity(tintOpacity))
            shape.fill(LinearGradient(colors: [.white.opacity(gradientStart), .white.opacity(gradientEnd)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(.white.opacity(border), lineWidth: 1)
            // inset 0 1px 0 rgba(255,255,255,.35) : reflet fin en haut
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(highlight), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.1)), lineWidth: 1)
        }
    }
}

/// Fond de la fenêtre de paroles : Uni / Verre / Transparent (§4). Le style EFFECTIF (après « Réduire la transparence ») est passé.
struct BackgroundView: View {
    var style: BackgroundStyle
    /// « Opacité fond » en pourcentage (0–85).
    var opacityPercent: Int
    /// Teinte tirée de la pochette (nil : couleurs d'origine).
    var tint: RGB? = nil

    private func base(default fallback: Color) -> Color {
        guard let tint else { return fallback }
        return Color(red: tint.r, green: tint.g, blue: tint.b)
    }

    var body: some View {
        let alpha = Double(opacityPercent) / 100
        let shape = RoundedRectangle(cornerRadius: LyricsMetrics.cornerRadius, style: .continuous)
        Group {
            switch style {
            case .solid:
                // rgba(22,22,28, .35 + alpha × 1,6), bordure 1 px blanc 8 %
                shape.fill(base(default: Color(red: 22 / 255, green: 22 / 255, blue: 28 / 255)).opacity(min(1, 0.35 + 1.6 * alpha)))
                    .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
            case .glass:
                GlassCard(tint: base(default: Color(red: 26 / 255, green: 26 / 255, blue: 34 / 255)), tintOpacity: tint == nil ? alpha : min(1, alpha + 0.18), radius: LyricsMetrics.cornerRadius)
            case .clear:
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
enum SnapshotFlags { nonisolated(unsafe) static var skipBlur = false }
#endif
