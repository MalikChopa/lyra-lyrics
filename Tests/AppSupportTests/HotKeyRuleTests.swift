import Testing
import Foundation
@testable import AppSupport

/// règle du raccourci global, fixture PARTAGÉE avec C# (`golden/hotkey.json`).
@Suite("Parité : raccourci global (golden/hotkey.json)")
struct HotKeyRuleTests {
    @Test("hotkey.json : bascule du clic-à-travers, montre la fenêtre cachée")
    func shared() throws {
        let doc = try SharedFixtures.json("golden/hotkey.json")
        let cases = doc["cases"] as! [[String: Any]]
        for c in cases {
            let want = c["expect"] as! [String: Any]
            let got = HotKeyRule.decide(windowShown: c["windowShown"] as! Bool, clickThrough: c["clickThrough"] as! Bool)
            #expect(got == HotKeyRule.Outcome(clickThrough: want["clickThrough"] as! Bool, showWindow: want["showWindow"] as! Bool), "\(c)")
        }
        #expect(cases.count == 4)
    }

    @Test("jamais de masquage de la fenêtre par le raccourci")
    func neverHides() {
        for shown in [true, false] { for ct in [true, false] { #expect(HotKeyRule.decide(windowShown: shown, clickThrough: ct).showWindow == !shown) } }
    }
}
