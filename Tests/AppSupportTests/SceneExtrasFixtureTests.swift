import Testing
import Foundation
@testable import AppSupport

/// W6c+d : fixture PARTAGÉE avec le cœur C# (`windows/LyraLyrics.Core.Tests/W6cdParityTests.cs`) : `golden/scene-extras.json`
/// (produite par `Fixtures/golden/scene-generator.py`). Les formules de karaoké, de passages sans paroles, de carte du titre, de barre de
/// commandes et de sortie de ligne vivent dans l'app Mac (`AppModel.swift`, `SceneView.swift`, `SceneExtras.swift`, `FillMask.swift`), hors de
/// portée des tests : les transcriptions ci-dessous les recopient à l'identique (ordonnées vers le haut, comme le Mac), sauf `SceneMath`
/// (vrai code de `AppSupport`). Le repli d'écran et les particules n'existent que côté Windows : non lus ici.
@Suite("Parité : finitions de la Scène (golden/scene-extras.json)")
struct SceneExtrasFixtureTests {
    private let placeholder = "♪"
    private func d(_ o: [String: Any], _ k: String) -> Double { (o[k] as! NSNumber).doubleValue }
    private func b(_ o: [String: Any], _ k: String) -> Bool { (o[k] as! NSNumber).boolValue }
    private func near(_ want: Double, _ got: Double, _ what: String, _ tol: Double = 1e-9) {
        #expect(abs(want - got) <= tol, "\(what) : attendu \(want), obtenu \(got)")
    }
    private func lines(_ a: Any?) -> [LyricLineTime] { (a as! [[String: Any]]).map { LyricLineTime(time: d($0, "time"), text: $0["text"] as! String) } }
    private func doc() throws -> [String: Any] { try SharedFixtures.json("golden/scene-extras.json") }

    /// AppModel.karaokeSpec (paire ligne + suivante vide).
    @Test("scene-extras.json : karaokeSpec")
    func karaoke() throws {
        let cases = try doc()["karaoke"] as! [[String: Any]]
        for c in cases {
            let all = lines(c["lines"]); let idx = c["index"] as! Int
            var got: (duration: Double, fraction: Double, playing: Bool)?
            if b(c, "enabled"), !b(c, "reduceMotion"), idx >= 0, idx < all.count, all[idx].text != placeholder {
                let line = all[idx]
                let pair = [LyricLineTime(time: line.time, text: line.text)] + (idx + 1 < all.count ? [LyricLineTime(time: all[idx + 1].time, text: "")] : [])
                let dur = SceneMath.fillDuration(lines: pair, index: 0)
                got = (dur, SceneMath.fillFraction(position: d(c, "position"), start: line.time, duration: dur), b(c, "playing"))
            }
            if let want = c["expected"] as? [String: Any] {
                #expect(got != nil, "\(c["song"] as! String) \(idx) : remplissage attendu")
                if let g = got { near(d(want, "duration"), g.duration, "durée"); near(d(want, "fraction"), g.fraction, "part"); #expect(g.playing == b(want, "playing")) }
            } else { #expect(got == nil, "\(c["song"] as! String) \(idx) : aucun remplissage attendu") }
        }
        #expect(cases.count == 60)
    }

    /// FillMask.init (cumulative) et FillMask.set (début, durée de chaque morceau) ; NeedsResync = SceneView.syncFill.
    @Test("scene-extras.json : morceaux du remplissage et resynchronisation")
    func pieces() throws {
        let root = try doc()
        let cases = root["fillPieces"] as! [[String: Any]]
        for c in cases {
            let widths = (c["widths"] as! [NSNumber]).map(\.doubleValue)
            let total = max(1, widths.reduce(0, +))
            var cum = [0.0]; var acc = 0.0
            for w in widths { acc += w / total; cum.append(min(1, acc)) }
            cum[cum.count - 1] = 1
            let want = (c["cumulative"] as! [NSNumber]).map(\.doubleValue)
            #expect(want.count == cum.count)
            for (a, g) in zip(want, cum) { near(a, g, "cumul") }
            let f0 = min(1, max(0, d(c, "startFraction"))), dur = d(c, "duration"), playing = b(c, "playing"), animated = b(c, "animated")
            for (i, p) in (c["pieces"] as! [[String: Any]]).enumerated() {
                let c0 = cum[i], c1 = cum[i + 1]
                let v = c1 > c0 ? min(1, max(0, (f0 - c0) / (c1 - c0))) : 1
                let run = animated && playing && v < 1 && dur > 0
                near(d(p, "start"), v, "départ \(i)")
                near(d(p, "begin"), run ? max(0, c0 - f0) * dur : 0, "retard \(i)")
                near(d(p, "duration"), run ? max(0.05, (c1 - max(c0, f0)) * dur) : 0, "durée \(i)")
                #expect(b(p, "animated") == run)
            }
        }
        #expect(cases.count == 45)
        for c in root["fillResync"] as! [[String: Any]] {
            let got = b(c, "currentPlaying") != b(c, "wantPlaying") || abs(d(c, "expected") - d(c, "wantFraction")) > 0.18
            #expect(got == b(c, "expectedResync"))
        }
    }

    /// SceneView.desiredGap (cas synchronisé : dans un passage et avant le début du fondu de sortie ; états : recherche, hors connexion, occupé = non).
    @Test("scene-extras.json : passage sans paroles voulu (desiredGap)")
    func gapWanted() throws {
        let cases = try doc()["gapWanted"] as! [[String: Any]]
        for c in cases {
            let gaps = (c["gaps"] as! [[String: Any]]).map { SceneMath.Gap(start: d($0, "start"), end: d($0, "end")) }
            let pos = d(c, "position")
            let got: Bool
            switch c["mode"] as! String {
            case "synced":
                if !b(c, "playingOrPaused") { got = false }
                else if let g = SceneMath.gap(at: pos, in: gaps) { got = pos < g.fadeOutAt } else { got = false }
            case "searching", "offline", "busy": got = false
            default: got = true
            }
            #expect(got == b(c, "expected"), "\(c["label"] as! String) \(c["mode"] as! String) à \(pos) s")
        }
        #expect(cases.count == 178)
        let budget = try doc()["particleBudget"] as! [String: Any]
        #expect(Int((d(budget, "birthRate") * d(budget, "lifetime")).rounded(.down)) == (budget["budget"] as! Int))   // c.birthRate = 3.4 ; c.lifetime = 8 (SceneView.layoutGap)
    }

    /// SceneControlsBar.format et layout (ordonnées vers le haut dans l'app, retournées ici : y = H − y_Mac) ; SceneView.leave ; SceneView.buildCard.
    @Test("scene-extras.json : barre de commandes, sortie de ligne, carte du titre")
    func barLeaveCard() throws {
        let root = try doc()
        for c in root["barFormat"] as! [[String: Any]] {
            let s = max(0, Int(d(c, "seconds").rounded(.down)))
            #expect(String(format: "%d:%02d", s / 60, s % 60) == (c["expected"] as! String))
        }
        for c in root["barFraction"] as! [[String: Any]] {
            let dur = c["duration"] as? NSNumber
            let f = (dur?.doubleValue ?? 0) > 0 ? min(1, max(0, d(c, "position") / dur!.doubleValue)) : 0
            near(d(c, "expected"), f, "part de la barre")
        }
        for c in root["barLayout"] as! [[String: Any]] {
            let W = d(c, "width"), H = d(c, "height")
            let w = min(W * 0.56, 720)                                    // layout(W:scale:)
            near(d(c, "barWidth"), w, "largeur"); near(d(c, "left"), (W - w) / 2, "gauche")
            near(d(c, "top"), H - (46 + 96), "haut")                      // position.y = 46 + height / 2, hauteur 96 : bord haut = 46 + 96 vers le haut
            near(d(c, "prevX"), w / 2 - 74, "précédent"); near(d(c, "playX"), w / 2, "lecture"); near(d(c, "nextX"), w / 2 + 74, "suivant"); near(d(c, "exitX"), w - 40, "sortie")
            near(d(c, "rowY"), 96 - 66, "rangée")                          // rowY = 66 depuis le bas de la barre
            near(d(c, "trackLeft"), 84, "piste x"); near(d(c, "trackWidth"), w - 2 * 84, "piste l"); near(d(c, "trackTop"), 96 - 24, "piste y")
            near(d(c, "elapsedLeft"), 14, "écoulé"); near(d(c, "totalLeft"), w - 76, "total"); near(d(c, "timeTop"), 96 - (12 + 18), "temps y")
        }
        for c in root["lineExit"] as! [[String: Any]] {
            let n = c["words"] as! Int
            let step = n > 1 ? min(0.040, 0.32 / Double(n - 1)) : 0                       // SceneView.leave
            let wordDur = max(0.3, 0.6 - Double(max(0, n - 1)) * step)
            near(d(c, "step"), step, "pas"); near(d(c, "wordDuration"), wordDur, "mot"); near(d(c, "total"), Double(max(0, n - 1)) * step + wordDur, "total")
        }
        for c in root["card"] as! [[String: Any]] {
            let W = d(c, "width"), H = d(c, "height")
            let side = min(H * 0.40, W * 0.30); let ts = max(30, H * 0.058), ss = max(18, H * 0.031)
            near(d(c, "side"), side, "côté"); near(d(c, "artLeft"), W / 2 - side / 2, "x"); near(d(c, "artTop"), H - (H * 0.50 + side), "y")
            near(d(c, "artCorner"), side * 0.04, "coin"); near(d(c, "reflectionHeight"), side * 0.28, "reflet h")
            near(d(c, "reflectionTop"), H - ((H * 0.50 - side * 0.28 - 2) + side * 0.28), "reflet y")
            near(d(c, "titleSize"), ts, "titre"); near(d(c, "artistSize"), ss, "artiste")
            let titleY = H * 0.50 - side * 0.30 - ts * 2.0, artistY = titleY - ss * 1.6
            near(d(c, "titleTop"), H - (titleY + ts * 1.3), "titre y"); near(d(c, "artistTop"), H - (artistY + ss * 1.3), "artiste y")
            near(d(c, "textLeft"), W * 0.2, "texte x"); near(d(c, "textWidth"), W * 0.6, "texte l")
        }
        for c in root["cardTiming"] as! [[String: Any]] {
            let rm = b(c, "reduce")
            let inD = rm ? 0.3 : 0.9, hold = 1.5, outD = rm ? 0.3 : 0.9                  // startCard
            near(d(c, "in"), inD, "entrée"); near(d(c, "hold"), hold, "tenue"); near(d(c, "out"), outD, "sortie"); near(d(c, "total"), inD + hold + outD, "total")
        }
    }
}
