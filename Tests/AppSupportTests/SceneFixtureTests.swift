import Testing
import Foundation
@testable import AppSupport

/// W6a : fixtures PARTAGÉES avec le cœur C# (`windows/LyraLyrics.Core.Tests/W6ParityTests.cs`) :
/// `golden/scene-screen.json`, `golden/scene-math.json`, `golden/scene-layout.json` (valeurs produites par `Fixtures/golden/scene-generator.py`).
/// Écrans, calculs (SceneMath) : le VRAI code de `AppSupport`. Géométrie (mise en page, place des lignes, zoom) : ces formules vivent dans l'app
/// (`Sources/LyraLyrics/SceneView.swift`, `SceneController.swift`, `SceneExtras.swift`), hors de portée des tests ; la transcription ci-dessous
/// les recopie à l'identique (ordonnées vers le haut, comme le Mac), puis retourne l'axe (y = H − y_Mac) pour comparer avec la fixture.
@Suite("Parité : Scène (golden/scene-screen.json, scene-math.json, scene-layout.json)")
struct SceneFixtureTests {
    private func d(_ o: [String: Any], _ k: String) -> Double { (o[k] as! NSNumber).doubleValue }
    private func near(_ want: Double, _ got: Double, _ what: String, _ tol: Double = 1e-9) {
        #expect(abs(want - got) <= tol, "\(what) : attendu \(want), obtenu \(got)")
    }
    private func lines(_ a: Any?) -> [LyricLineTime] { (a as! [[String: Any]]).map { LyricLineTime(time: d($0, "time"), text: $0["text"] as! String) } }
    private func rgb(_ a: Any?) -> RGB { let v = (a as! [NSNumber]).map(\.doubleValue); return RGB(v[0], v[1], v[2]) }

    @Test("scene-screen.json : choix de l'écran")
    func screens() throws {
        let doc = try SharedFixtures.json("golden/scene-screen.json")
        let cases = doc["cases"] as! [[String: Any]]
        for c in cases {
            let got = SceneScreenChoice.pick(setting: c["setting"] as! String, names: c["names"] as! [String], mainIndex: c["mainIndex"] as! Int, windowIndex: c["windowIndex"] as! Int)
            #expect(got == (c["expected"] as! Int), "\(c["label"] as! String) : attendu \(c["expected"] as! Int), obtenu \(got)")
        }
        #expect(cases.count == 18)
    }

    @Test("scene-math.json : remplissage (fillDuration, fillFraction)")
    func fill() throws {
        let doc = try SharedFixtures.json("golden/scene-math.json")
        let fill = doc["fill"] as! [String: Any]
        let songs = (fill["songs"] as! [String: Any]).mapValues { lines($0) }
        let durations = fill["durations"] as! [[String: Any]]
        for c in durations { near(d(c, "expected"), SceneMath.fillDuration(lines: songs[c["song"] as! String]!, index: c["index"] as! Int), "fillDuration \(c)") }
        let fractions = fill["fractions"] as! [[String: Any]]
        for c in fractions { near(d(c, "expected"), SceneMath.fillFraction(position: d(c, "position"), start: d(c, "start"), duration: d(c, "duration")), "fillFraction \(c)") }
        #expect(durations.count == 18 && fractions.count == 11)
    }

    @Test("scene-math.json : durée de chant (caractères = graphèmes)")
    func sung() throws {
        let doc = try SharedFixtures.json("golden/scene-math.json")
        let cases = doc["sungDuration"] as! [[String: Any]]
        for c in cases {
            let text = c["text"] as! String
            #expect(text.count == (c["characters"] as! Int), "nombre de caractères de « \(text) »")
            near(d(c, "expected"), SceneMath.sungDuration(of: text), "sungDuration « \(text) »")
        }
        #expect(cases.count == 12)
    }

    @Test("scene-math.json : passages sans paroles")
    func gaps() throws {
        let doc = try SharedFixtures.json("golden/scene-math.json")
        let cases = doc["gaps"] as! [[String: Any]]
        for c in cases {
            let duration = (c["duration"] as? NSNumber)?.doubleValue
            let got = SceneMath.gaps(lines: lines(c["lines"]), placeholder: c["placeholder"] as! String, duration: duration)
            let want = c["expected"] as! [[String: Any]]
            #expect(want.count == got.count, "\(c["label"] as! String) : \(want.count) attendu(s), \(got.count) obtenu(s)")
            for (w, g) in zip(want, got) {
                near(d(w, "start"), g.start, "\(c["label"] as! String) début"); near(d(w, "end"), g.end, "\(c["label"] as! String) fin")
                near(d(w, "fadeOutAt"), g.fadeOutAt, "\(c["label"] as! String) fadeOutAt")
            }
        }
        #expect(cases.count == 12)
        let at = doc["gapAt"] as! [[String: Any]]
        for c in at {
            let gs = (c["gaps"] as! [[String: Any]]).map { SceneMath.Gap(start: d($0, "start"), end: d($0, "end")) }
            let found = SceneMath.gap(at: d(c, "position"), in: gs)
            #expect((found.flatMap { gs.firstIndex(of: $0) } ?? -1) == (c["expectedIndex"] as! Int), "gapAt \(c)")
        }
        #expect(at.count == 11)
    }

    /// Mesure factice de la fixture : lignes = ceil(n / max(1, floor(largeur / (taille × 0,5)))), hauteur = lignes × taille × 1,2.
    private static func fakeMeasure(_ text: String, _ size: Double, _ width: Double) -> Double {
        let perLine = max(1, (width / (size * 0.5)).rounded(.down))
        return (Double(text.count) / perLine).rounded(.up) * size * 1.2
    }

    @Test("scene-math.json : taille du texte (fitSize, mesure factice)")
    func fit() throws {
        let doc = try SharedFixtures.json("golden/scene-math.json")
        let cases = doc["fitSize"] as! [[String: Any]]
        for c in cases {
            let got = SceneMath.fitSize(text: c["text"] as! String, width: d(c, "width"), maxHeight: d(c, "maxHeight"), maxSize: d(c, "maxSize"), minSize: d(c, "minSize"), measure: Self.fakeMeasure)
            near(d(c, "expected"), got, "fitSize \(c["label"] as! String)")
        }
        #expect(cases.count == 10)
    }

    @Test("scene-math.json : contraste, voile, réglage du fond")
    func contrast() throws {
        let doc = try SharedFixtures.json("golden/scene-math.json")
        let k = doc["contrast"] as! [String: Any]
        var n = 0
        for c in k["maxBackground"] as! [[String: Any]] { near(d(c, "expected"), SceneMath.maxBackgroundLuminance(forText: d(c, "text")), "maxBackground"); n += 1 }
        for c in k["scrim"] as! [[String: Any]] { near(d(c, "expected"), SceneMath.scrimAlpha(backgroundLuminance: d(c, "background"), textLuminance: d(c, "text")), "scrim \(c)"); n += 1 }
        for c in k["contrast"] as! [[String: Any]] { near(d(c, "expected"), SceneMath.contrast(textLuminance: d(c, "text"), backgroundLuminance: d(c, "background"), scrim: d(c, "scrim")), "contraste \(c)"); n += 1 }
        for c in k["background"] as! [[String: Any]] {
            let b = SceneMath.background(artLuminance: d(c, "art"), gradientLuminance: d(c, "gradient"), textLuminance: d(c, "text"))
            near(d(c, "artOpacity"), b.artOpacity, "fond pochette \(c)"); near(d(c, "scrim"), b.scrim, "fond voile \(c)"); near(d(c, "contrast"), b.contrast, "fond contraste \(c)")
            n += 1
        }
        #expect(n == 6 + 33 + 6 + 45)
    }

    /// Dégradé du fond de la Scène (SceneView.updateBackground) : dominante × 0,62, teinte, secondaire × 0,45 ; luminance = max(dom × 0,4 ; sec × 0,25 ; teinte).
    @Test("scene-math.json : dégradé de fond (palette de la pochette)")
    func gradient() throws {
        let doc = try SharedFixtures.json("golden/scene-math.json")
        let g = doc["gradient"] as! [String: Any]
        let palettes = g["palettes"] as! [[String: Any]]
        for c in palettes {
            let label = c["label"] as! String
            let p = ArtworkPalette(dominant: rgb(c["dominant"]), secondary: rgb(c["secondary"]))
            let tint = rgb(c["tint"])
            near(tint.r, p.tint.r, "\(label) teinte R"); near(tint.g, p.tint.g, "\(label) teinte V"); near(tint.b, p.tint.b, "\(label) teinte B")
            let cols = [RGB(p.dominant.r * 0.62, p.dominant.g * 0.62, p.dominant.b * 0.62), p.tint, RGB(p.secondary.r * 0.45, p.secondary.g * 0.45, p.secondary.b * 0.45)]
            for (i, w) in (c["colors"] as! [Any]).enumerated() {
                let want = rgb(w); near(want.r, cols[i].r, "\(label) R"); near(want.g, cols[i].g, "\(label) V"); near(want.b, cols[i].b, "\(label) B")
            }
            near(d(c, "luminance"), max(p.dominant.luminance * 0.4, p.secondary.luminance * 0.25, p.tint.luminance), "\(label) luminance")
        }
        #expect(palettes.count == 5)
    }

    // MARK: Géométrie : transcription de SceneView.swift / SceneExtras.swift (ordonnées vers le haut), axe retourné à la fin

    private struct MacFrame {
        var artSide, artLeft, columnLeft, textWidth, textCenterX, centerY, artTop, artCorner: Double
        var titleSize, artistSize, titleTop, artistTop, maxLineSize, infoTitleSize, infoSubSize, infoTitleTop, infoSubTop: Double
    }
    private func macFrame(W: Double, H: Double, withArtwork: Bool) -> MacFrame {
        // SceneView : artSide, artLeft, columnLeft, textWidth, textCenterX
        let artSide = min(W * 0.34, H * 0.56), artLeft = W * 0.05
        let columnLeft = artLeft + artSide + W * 0.04
        let textWidth = withArtwork ? (W * 0.95 - columnLeft) * 0.96 : W * 0.70
        let textCenterX = withArtwork ? (columnLeft + W * 0.95) / 2 : W / 2
        // layoutArtPanel : centerY = H × 0,56 ; SceneArtPanel.layout : coin = côté × 0,045, tailles, cadres du titre et de l'artiste
        let centerYMac = H * 0.56
        let tileMinY = centerYMac - artSide / 2
        let ts = max(18, H * 0.028), ss = max(14, H * 0.02)
        let titleFrameY = tileMinY - ts * 1.7, titleFrameH = ts * 1.4
        let artistFrameY = tileMinY - ts * 1.7 - ss * 1.5, artistFrameH = ss * 1.4
        // layoutInfo
        let its = max(30, H * 0.06), iss = max(16, H * 0.03)
        let infoTitleY = H * 0.40, infoTitleH = its * 2.4, infoSubY = H * 0.30, infoSubH = iss * 2.6
        return MacFrame(artSide: artSide, artLeft: artLeft, columnLeft: columnLeft, textWidth: textWidth, textCenterX: textCenterX,
                        centerY: H - centerYMac, artTop: H - (centerYMac + artSide / 2), artCorner: artSide * 0.045,
                        titleSize: ts, artistSize: ss, titleTop: H - (titleFrameY + titleFrameH), artistTop: H - (artistFrameY + artistFrameH),
                        maxLineSize: min(max(H * 0.085, 44), 124), infoTitleSize: its, infoSubSize: iss,
                        infoTitleTop: H - (infoTitleY + infoTitleH), infoSubTop: H - (infoSubY + infoSubH))
    }

    @Test("scene-layout.json : mise en page selon la taille de l'écran")
    func frames() throws {
        let doc = try SharedFixtures.json("golden/scene-layout.json")
        let frames = doc["frames"] as! [[String: Any]]
        for c in frames {
            let W = d(c, "width"), H = d(c, "height"), art = c["withArtwork"] as! Bool
            let f = macFrame(W: W, H: H, withArtwork: art)
            let e = c["frame"] as! [String: Any]
            let tag = "\(W)x\(H) \(art ? "pochette" : "seules") "
            for (k, v) in [("artSide", f.artSide), ("artLeft", f.artLeft), ("columnLeft", f.columnLeft), ("textWidth", f.textWidth), ("textCenterX", f.textCenterX),
                           ("centerY", f.centerY), ("artTop", f.artTop), ("artCorner", f.artCorner), ("titleSize", f.titleSize), ("artistSize", f.artistSize),
                           ("titleTop", f.titleTop), ("artistTop", f.artistTop), ("maxLineSize", f.maxLineSize), ("infoTitleSize", f.infoTitleSize),
                           ("infoSubSize", f.infoSubSize), ("infoTitleTop", f.infoTitleTop), ("infoSubTop", f.infoSubTop)] { near(d(e, k), v, tag + k) }
            for (role, sc) in [(0, 1.0), (1, 0.5), (2, 0.42)] {      // SceneView.displayScale / layoutWidth / fitSize(for:role:)
                near(d(c["layoutWidth"] as! [String: Any], "\(role)"), f.textWidth / sc, tag + "layoutWidth \(role)")
                near(d(c["fitMaxHeight"] as! [String: Any], "\(role)"), H * 0.27 / sc, tag + "fitMaxHeight \(role)")
            }
        }
        #expect(frames.count == 18)
    }

    /// SceneView.target(for:offset:) (ordonnées vers le haut).
    private func macTarget(offset: Int, H: Double, hCur: Double, hNext: Double, hSelf: Double, fill: Bool) -> (y: Double, scale: Double, opacity: Double, sharp: Double, soft: Double) {
        let yCur = H * 0.56
        switch offset {
        case 0: return (yCur, 1, 1, fill ? 0.78 : 0, 0)
        case 1: let sc = 0.5; return (yCur - hCur / 2 - H * 0.05 - hSelf * sc / 2, sc, 0.76, 1, 0)
        case 2: let sc = 0.42; let h1 = hNext * 0.5; return (yCur - hCur / 2 - H * 0.05 - h1 - H * 0.035 - hSelf * sc / 2, sc, 0.72, 1, 0)
        case -1: return (yCur + hCur / 2 + H * 0.13, 0.82, 0, 0.2, 0.7)
        default: return (yCur - H * 0.4, 0.4, 0, 1, 0)
        }
    }

    @Test("scene-layout.json : place des lignes (courante, suivantes, partante)")
    func targets() throws {
        let doc = try SharedFixtures.json("golden/scene-layout.json")
        let cases = doc["targets"] as! [[String: Any]]
        for c in cases {
            let H = d(c, "height")
            let t = macTarget(offset: c["offset"] as! Int, H: H, hCur: d(c, "hCur"), hNext: d(c, "hNext"), hSelf: d(c, "hSelf"), fill: c["fillEnabled"] as! Bool)
            let tag = "H=\(H) décalage \(c["offset"] as! Int) "
            near(d(c, "y"), H - t.y, tag + "y"); near(d(c, "scale"), t.scale, tag + "échelle"); near(d(c, "opacity"), t.opacity, tag + "opacité")
            near(d(c, "sharp"), t.sharp, tag + "net"); near(d(c, "soft"), t.soft, tag + "flou")
        }
        #expect(cases.count == 48)
    }

    /// SceneController.localRect(of:on:) : CGRect.intersects (aire non nulle), sinon rectangle centré 27 % × 0,42.
    @Test("scene-layout.json : rectangle de départ du zoom (S25)")
    func zoom() throws {
        let doc = try SharedFixtures.json("golden/scene-layout.json")
        let cases = doc["zoom"] as! [[String: Any]]
        func r(_ a: Any?) -> CGRect { let v = (a as! [NSNumber]).map(\.doubleValue); return CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }
        for c in cases {
            let small = r(c["small"]), screen = r(c["screen"])
            let local: CGRect
            if screen.intersects(small) {
                local = CGRect(x: small.minX - screen.minX, y: small.minY - screen.minY, width: small.width, height: small.height)
            } else {
                let w = screen.width * 0.27, h = w * 0.42
                local = CGRect(x: (screen.width - w) / 2, y: (screen.height - h) / 2, width: w, height: h)
            }
            let want = r(c["expectedLocal"]); let tag = c["label"] as! String
            near(want.minX, local.minX, tag + " x"); near(want.minY, local.minY, tag + " y"); near(want.width, local.width, tag + " largeur"); near(want.height, local.height, tag + " hauteur")
            near(d(c, "expectedStartScale"), max(0.05, local.width / max(1, screen.width)), tag + " échelle de départ")
        }
        #expect(cases.count == 7)
    }
}
