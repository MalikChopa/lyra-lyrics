import Testing
import Foundation
@testable import AppSupport

/// W3 : fixtures PARTAGÉES avec le cœur C# (`windows/LyraLyrics.Core.Tests/W3ParityTests.cs`) : réglages et palette de pochette.
enum SharedFixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    static func json(_ relative: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(relative))) as! [String: Any]
    }
}

@Suite("Parité : réglages et palette (golden/settings-defaults.json, golden/palette.json)")
struct W3FixtureTests {
    /// Compare deux valeurs JSON ; les chaînes sans tenir compte de la casse (énumérations : Mac camelCase, Windows PascalCase).
    private func same(_ got: Any?, _ want: Any?) -> Bool {
        if want == nil || want is NSNull { return got == nil || got is NSNull }
        guard let got else { return false }
        if let w = want as? String { return (got as? String)?.lowercased() == w.lowercased() }
        if let w = want as? NSNumber, let g = got as? NSNumber {
            if CFGetTypeID(w) == CFBooleanGetTypeID() || CFGetTypeID(g) == CFBooleanGetTypeID() { return CFGetTypeID(w) == CFGetTypeID(g) && w.boolValue == g.boolValue }
            return abs(w.doubleValue - g.doubleValue) < 1e-9
        }
        return false
    }

    private func encodedFields(_ s: Settings) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try #require(s.encoded())) as! [String: Any]
    }

    @Test("settings-defaults.json : mêmes champs et mêmes valeurs par défaut que Windows")
    func defaults() throws {
        let doc = try SharedFixtures.json("golden/settings-defaults.json")
        let common = doc["common"] as! [String: Any]
        let fields = try encodedFields(Settings())
        var failures: [String] = []
        for (k, v) in common where !same(fields[k], v) { failures.append("\(k) = \(String(describing: fields[k])), attendu \(v)") }
        let expectedKeys = Set(common.filter { !($0.value is NSNull) }.keys).union(doc["sameKeyOwnDefault"] as! [String]).union(doc["macOnly"] as! [String])
        if Set(fields.keys) != expectedKeys { failures.append("clés écrites : \(Set(fields.keys).symmetricDifference(expectedKeys).sorted())") }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("settings-defaults.json : décodage tolérant (inconnu, mauvais type, hors plage, version)")
    func decoding() throws {
        let doc = try SharedFixtures.json("golden/settings-defaults.json")
        var failures: [String] = []
        let cases = doc["decode"] as! [[String: Any]]
        for c in cases {
            let name = c["name"] as! String
            let (s, outcome) = Settings.decode((c["input"] as! String).data(using: .utf8))
            let got: String
            switch outcome { case .ok: got = "ok"; case .corrupt: got = "corrupt"; case .missing: got = "missing"; case .newerVersion: got = "newerVersion" }
            if got != c["outcome"] as! String { failures.append("\(name) : issue \(got)") }
            let fields = try encodedFields(s)
            for (k, v) in c["expect"] as! [String: Any] where !same(fields[k], v) { failures.append("\(name) : \(k) = \(String(describing: fields[k])), attendu \(v)") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(cases.count >= 10)
    }

    @Test("palette.json : mêmes couleurs que le C# pour des pixels synthétiques")
    func palette() throws {
        let doc = try SharedFixtures.json("golden/palette.json")
        var failures: [String] = []
        let cases = doc["cases"] as! [[String: Any]]
        for c in cases {
            let name = c["name"] as! String
            var px: [UInt8] = []
            for f in c["fill"] as! [[String: Any]] {
                let rgba = (f["rgba"] as! [NSNumber]).map { UInt8($0.intValue) }
                for _ in 0..<(f["count"] as! NSNumber).intValue { px += rgba }
            }
            let p = ArtworkPalette.from(rgba: px, width: (c["width"] as! NSNumber).intValue, height: (c["height"] as! NSNumber).intValue)
            if let want = c["expect"] as? [String: String] {
                guard let p else { failures.append("\(name) : palette nulle"); continue }
                let got = ["dominant": p.dominant.hex, "secondary": p.secondary.hex, "tint": p.tint.hex, "accent": p.accent.hex]
                if got != want { failures.append("\(name) : \(got), attendu \(want)") }
                if p.accentContrast < ArtworkPalette.minContrast { failures.append("\(name) : contraste \(p.accentContrast)") }
            } else if p != nil { failures.append("\(name) : palette inattendue") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(cases.count >= 16)
    }
}

@Suite("Parité : apparence des lignes (golden/linelook.json)")
struct LineLookParityTests {
    @Test("linelook.json : échelle, opacité, flou identiques au C#")
    func lineLook() throws {
        let doc = try SharedFixtures.json("golden/linelook.json")
        let rows = doc["rows"] as! [[NSNumber]]
        for r in rows {
            let off = r[0].intValue, ratio = r[1].doubleValue
            #expect(abs(LineLook.scale(offset: off, ratio: ratio) - r[2].doubleValue) < 1e-9, "échelle \(off)")
            #expect(abs(LineLook.opacity(offset: off) - r[3].doubleValue) < 1e-9, "opacité \(off)")
            #expect(abs(LineLook.blur(offset: off) - r[4].doubleValue) < 1e-9, "flou \(off)")
            #expect(abs(LineLook.opacity(offset: off) * 0.62 - r[5].doubleValue) < 1e-9, "atténuée \(off)")
        }
        #expect(rows.count >= 10)
    }
}
