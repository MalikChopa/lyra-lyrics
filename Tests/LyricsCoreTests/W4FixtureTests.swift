import Testing
import Foundation
@testable import LyricsCore

/// W4 : `golden/lookup-manual.json`, partagée avec le cœur C# (`W4ParityTests.cs`) : règles de l'index (choix manuel, 24 h, 200 / 500 entrées).
@Suite("Parité : index et choix manuel (golden/lookup-manual.json)")
struct W4LookupFixtureTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func describe(_ o: LookupIndex.Outcome?) -> String? {
        switch o { case nil: return nil; case .notFound?: return "notFound"; case .found(let id)?: return "found:\(id)" }
    }

    @Test("scénarios de l'index")
    func scenarios() throws {
        let doc = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Self.root.appendingPathComponent("golden/lookup-manual.json"))) as? [String: Any])
        var failures: [String] = []
        let scenarios = doc["scenarios"] as! [[String: Any]]
        for sc in scenarios {
            var index = LookupIndex()
            let name = sc["name"] as! String
            for (i, step) in (sc["steps"] as! [[String: Any]]).enumerated() {
                let op = step["op"] as! String
                func at() -> Date { t0.addingTimeInterval((step["at"] as? NSNumber)?.doubleValue ?? 0) }
                func key() -> String { step["key"] as! String }
                switch op {
                case "record": index.record(key: key(), outcome: .found(id: (step["id"] as! NSNumber).intValue), now: at())
                case "recordNotFound": index.record(key: key(), outcome: .notFound, now: at())
                case "recordManual": index.recordManual(key: key(), id: (step["id"] as! NSNumber).intValue, now: at())
                case "recordRange":
                    for n in (step["from"] as! Int)..<(step["to"] as! Int) { index.record(key: "\(step["prefix"] as! String)\(n)", outcome: .found(id: n), now: at()) }
                case "recordManualRange":
                    for n in (step["from"] as! Int)..<(step["to"] as! Int) { index.recordManual(key: "\(step["prefix"] as! String)\(n)", id: n, now: at()) }
                case "removeManual": index.removeManual(key: key())
                case "remove": index.remove(key: key())
                case "purge": index.purge(now: at())
                case "clear": index.clear()
                case "lookup":
                    let got = describe(index.lookup(key: key(), now: at()))
                    if got != step["expect"] as? String { failures.append("\(name) pas \(i) lookup : \(got ?? "nil")") }
                case "manualChoice":
                    let got = index.manualChoice(key: key())
                    if got != (step["expect"] as? NSNumber)?.intValue { failures.append("\(name) pas \(i) manualChoice : \(got.map(String.init) ?? "nil")") }
                case "count":
                    if index.count != (step["expect"] as! Int) { failures.append("\(name) pas \(i) count : \(index.count)") }
                default: failures.append("\(name) : op inconnue \(op)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(scenarios.count >= 7)
    }
}
