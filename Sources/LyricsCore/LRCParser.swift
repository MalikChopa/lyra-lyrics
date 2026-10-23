import Foundation

/// Analyseur LRC (§3.2) : `[mm:ss.xx]` / `[mm:ss.xxx]` / `[mm:ss]`, plusieurs horodatages par ligne, `[offset:±ms]`,
/// métadonnées (`[ar:…]`, `[ti:…]`…) ignorées, BOM, CRLF, lignes vides (→ « ♪ »), désordre (tri stable), balises mot à mot
/// `<mm:ss.xx>` retirées. Fichier vide ou corrompu → aucune ligne.
public enum LRCParser {
    public struct Result: Sendable, Equatable {
        public var lines: [LyricLine]
        /// Valeur brute de `[offset:…]` en millisecondes (0 si absent). Convention retenue (délégué) : un décalage positif
        /// avance les lignes (`temps = horodatage − offset`), comme la plupart des lecteurs.
        public var offsetMillis: Int
        public var metadata: [String: String]
        public init(lines: [LyricLine], offsetMillis: Int, metadata: [String: String]) {
            self.lines = lines; self.offsetMillis = offsetMillis; self.metadata = metadata
        }
    }

    public static let placeholder = "♪"

    public static func parse(_ text: String) -> [LyricLine] { parseDetailed(text).lines }

    public static func parseDetailed(_ text: String) -> Result {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var metadata: [String: String] = [:]
        var offsetMillis = 0
        struct Entry { var time: Double; var text: String; var order: Int }
        var entries: [Entry] = []

        for (order, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var rest = Substring(rawLine)
            var times: [Double] = []
            while let tag = leadingTag(rest) {
                if let t = timestamp(tag.content) {
                    times.append(t)
                } else if let colon = tag.content.firstIndex(of: ":"), isMetadataKey(tag.content[..<colon]) {
                    let key = tag.content[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = tag.content[tag.content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if key == "offset" {
                        offsetMillis = Int(value.replacingOccurrences(of: " ", with: "")) ?? 0
                    } else {
                        metadata[key] = value
                    }
                } else {
                    break        // « [Refrain] » ou crochet quelconque : c'est du texte
                }
                rest = tag.rest
            }
            guard !times.isEmpty else { continue }
            let cleaned = stripWordTags(String(rest)).trimmingCharacters(in: .whitespacesAndNewlines)
            let lineText = cleaned.isEmpty ? placeholder : cleaned
            for t in times { entries.append(Entry(time: t, text: lineText, order: order)) }
        }

        let offset = Double(offsetMillis) / 1000
        let sorted = entries.sorted { a, b in a.time != b.time ? a.time < b.time : a.order < b.order }
        let lines = sorted.map { LyricLine(time: max(0, (($0.time - offset) * 1000).rounded() / 1000), text: $0.text) }
        return Result(lines: lines, offsetMillis: offsetMillis, metadata: metadata)
    }

    /// Texte seul d'un LRC (pour le bloc « non synchronisées » quand la durée ne colle pas) : lignes sans horodatage, sans « ♪ ».
    public static func plainText(from lines: [LyricLine]) -> String {
        lines.map(\.text).filter { $0 != placeholder }.joined(separator: "\n")
    }

    // MARK: - Détails

    private static func leadingTag(_ s: Substring) -> (content: Substring, rest: Substring)? {
        guard s.first == "[", let close = s.firstIndex(of: "]") else { return nil }
        let content = s[s.index(after: s.startIndex)..<close]
        guard !content.contains("[") else { return nil }
        return (content, s[s.index(after: close)...])
    }

    private static func isMetadataKey(_ key: Substring) -> Bool {
        let k = key.trimmingCharacters(in: .whitespaces)
        return !k.isEmpty && k.allSatisfy { $0.isLetter || $0 == "#" || $0 == "_" }
    }

    /// `mm:ss`, `mm:ss.xx`, `mm:ss.xxx`, `mm:ss:xx` ; minutes sans limite (> 59 accepté).
    static func timestamp(_ s: Substring) -> Double? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let minutes = Int(parts[0]), minutes >= 0, parts[0].count <= 4 else { return nil }
        var secondsPart = parts[1]
        var fraction: Substring? = nil
        if parts.count == 3 {
            fraction = parts[2]
        } else if let dot = secondsPart.firstIndex(of: ".") {
            fraction = secondsPart[secondsPart.index(after: dot)...]
            secondsPart = secondsPart[..<dot]
        }
        guard let seconds = Int(secondsPart), seconds >= 0, seconds < 60, secondsPart.count <= 2 else { return nil }
        var frac = 0.0
        if let f = fraction {
            guard !f.isEmpty, f.count <= 3, let digits = Int(f) else { return nil }
            frac = Double(digits) / pow(10, Double(f.count))
        }
        return Double(minutes * 60 + seconds) + frac
    }

    /// Retire les balises mot à mot `<mm:ss.xx>` et resserre les espaces.
    static func stripWordTags(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "<", let close = s[i...].firstIndex(of: ">"), timestamp(s[s.index(after: i)..<close]) != nil {
                i = s.index(after: close)
                continue
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
