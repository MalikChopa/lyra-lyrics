import Testing
import Foundation
@testable import AppSupport

/// W4 : fixtures PARTAGÉES avec le cœur C# (`windows/LyraLyrics.Core.Tests/W4ParityTests.cs`) :
/// masquage automatique (`golden/autohide.json`) et vérification des mises à jour (`golden/update-check.json`).
@Suite("Parité : masquage automatique et mises à jour (golden/autohide.json, golden/update-check.json)")
struct W4FixtureTests {
    private func mode(_ s: String) -> AutoHideMode { AutoHideMode(rawValue: s)! }
    private func activity(_ s: String) -> PlaybackActivity { PlaybackActivity(rawValue: s)! }
    private func label(_ a: AutoHideState.Action?) -> String? { a.map { $0 == .hide ? "hide" : "show" } }

    @Test("autohide.json : conditions des modes")
    func conditions() throws {
        let doc = try SharedFixtures.json("golden/autohide.json")
        let cases = doc["conditions"] as! [[String: Any]]
        for c in cases {
            let got = AutoHideState.condition(mode: mode(c["mode"] as! String), activity: activity(c["activity"] as! String))
            #expect(got == (c["expected"] as! Bool), "\(c)")
        }
        #expect(cases.count == 9)
    }

    @Test("autohide.json : scénarios (mode, activité, fenêtre, geste manuel -> action)")
    func scenarios() throws {
        let doc = try SharedFixtures.json("golden/autohide.json")
        var failures: [String] = []
        let scenarios = doc["scenarios"] as! [[String: Any]]
        for sc in scenarios {
            var state = AutoHideState()
            for (i, step) in (sc["steps"] as! [[String: Any]]).enumerated() {
                if step["op"] as! String == "manual" { state.manualChange(windowShown: step["windowShown"] as! Bool); continue }
                let got = label(state.evaluate(mode: mode(step["mode"] as! String), activity: activity(step["activity"] as! String), windowShown: step["windowShown"] as! Bool))
                let want = step["expect"] as? String
                if got != want { failures.append("\(sc["name"] as! String) pas \(i) : \(got ?? "nil"), attendu \(want ?? "nil")") }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(scenarios.count >= 12)
    }

    @Test("update-check.json : lecture de la réponse (tag et lien de confiance)")
    func parse() throws {
        let doc = try SharedFixtures.json("golden/update-check.json")
        var failures: [String] = []
        let cases = doc["parse"] as! [[String: Any]]
        for c in cases {
            let r = UpdateCheck.parse(Data((c["payload"] as! String).utf8))
            let wantTag = c["tag"] as? String, wantURL = c["url"] as? String
            if r?.tag != wantTag { failures.append("\(c["name"] as! String) : tag \(r?.tag ?? "nil"), attendu \(wantTag ?? "nil")") }
            if let wantURL, r?.url.absoluteString != wantURL { failures.append("\(c["name"] as! String) : url \(r?.url.absoluteString ?? "nil")") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(cases.count >= 30)
    }

    @Test("update-check.json : comparaison, cadence, liens de confiance, résultat")
    func rest() throws {
        let doc = try SharedFixtures.json("golden/update-check.json")
        var failures: [String] = []
        for c in doc["newer"] as! [[String: Any]] {
            let got = UpdateCheck.isNewer(c["remote"] as! String, than: c["local"] as! String)
            if got != (c["expected"] as! Bool) { failures.append("newer \(c)") }
        }
        for c in doc["due"] as! [[String: Any]] {
            let last = (c["last"] as? NSNumber)?.doubleValue
            if UpdateCheck.isDue(last: last, now: (c["now"] as! NSNumber).doubleValue) != (c["expected"] as! Bool) { failures.append("due \(c)") }
        }
        for c in doc["trusted"] as! [[String: Any]] {
            let url = URL(string: c["url"] as! String)
            if (url.map(UpdateCheck.isTrusted) ?? false) != (c["expected"] as! Bool) { failures.append("trusted \(c)") }
        }
        for c in doc["outcome"] as! [[String: Any]] {
            let got: String
            switch UpdateCheck.outcome(data: Data((c["payload"] as! String).utf8), localVersion: c["local"] as! String) {
            case .newer(let r): got = "newer:\(r.tag)"
            case .upToDate: got = "upToDate"
            case .failed: got = "failed"
            }
            if got != (c["expected"] as! String) { failures.append("outcome \(c["name"] as! String) : \(got)") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(UpdateCheck.endpoint.absoluteString == doc["endpoint"] as! String)
        #expect(UpdateCheck.host == doc["host"] as! String)
    }
}
