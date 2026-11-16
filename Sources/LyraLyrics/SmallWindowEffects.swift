import AppKit
import SwiftUI
import QuartzCore
import AppSupport

/// Versions réduites des effets de la Scène dans la petite fenêtre (S24), désactivées par défaut.

/// Fond animé : la pochette très floue dérive lentement derrière les paroles (cycle 60 s). Son opacité est réglée pour que le texte
/// garde 4,5 : 1 de contraste (`SceneMath.maxBackgroundLuminance`). « Réduire les animations » : image fixe.
struct ArtworkDriftView: NSViewRepresentable {
    var image: CGImage
    var luminance: Double
    var radius: Double
    var animated: Bool

    final class Host: NSView {
        let art = CALayer()
        var currentImage: CGImage?
        private(set) var driftCount = 0
        #if DEBUG
        nonisolated(unsafe) static var driftStarts = 0
        #endif
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.cornerRadius = 0
            art.bounds = CGRect(x: 0, y: 0, width: bounds.width * 1.5, height: bounds.height * 1.5)
            art.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
            // La dérive est ADDITIVE (décalage ± 5 % de la largeur autour de la position de la mise en page) : sa valeur dépend de la
            // largeur, on la rejoue quand la fenêtre change de largeur.
            if art.animation(forKey: "pf.drift.pos") != nil, abs(bounds.width - driftWidth) > 0.5 { addDrift() }
        }
        private var driftWidth: CGFloat = 0
        private func addDrift() {
            let s = CABasicAnimation(keyPath: "transform.scale")
            s.fromValue = 1.0; s.toValue = 1.14
            let p = CABasicAnimation(keyPath: "position.x")
            p.isAdditive = true
            p.fromValue = -bounds.width * 0.05; p.toValue = bounds.width * 0.05
            for a in [s, p] { a.duration = 60; a.autoreverses = true; a.repeatCount = .infinity; a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) }
            art.add(s, forKey: "pf.drift.scale"); art.add(p, forKey: "pf.drift.pos")
            driftWidth = bounds.width
        }
        func startDrift() {
            guard art.animation(forKey: "pf.drift.scale") == nil else { return }
            addDrift()
            driftCount += 1
            #if DEBUG
            Self.driftStarts += 1
            #endif
        }
        func stopDrift() { art.removeAllAnimations() }
    }

    func makeNSView(context: Context) -> Host {
        let v = Host(frame: .zero)
        v.wantsLayer = true
        v.layer?.masksToBounds = true
        v.layer?.addSublayer(v.art)
        v.art.contentsGravity = .resizeAspectFill
        return v
    }
    func updateNSView(_ v: Host, context: Context) {
        if v.currentImage !== image {
            if v.currentImage != nil {
                let t = CATransition(); t.type = .fade; t.duration = 1.0; t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                v.art.add(t, forKey: "pf.swap")
            }
            v.art.contents = image
            v.currentImage = image
        }
        v.layer?.cornerRadius = radius
        // opacité : le fond effectif reste assez sombre pour un texte de luminance 0,7 (blanc à ~ 70 %)
        let allowed = SceneMath.maxBackgroundLuminance(forText: 0.7)
        v.art.opacity = Float(min(0.6, allowed / max(luminance, 0.01)))
        if animated { v.startDrift() } else { v.stopDrift() }
    }
}
