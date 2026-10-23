#if DEBUG
import Foundation

/// Journal de diagnostic (`--diagnostics <fichier>`) : une ligne JSON par enregistrement, sans paroles ; titres seulement en
/// faux lecteur (invention). Écho sur la sortie standard.
final class DiagLog: @unchecked Sendable {
    static let shared = DiagLog()
    private var handle: FileHandle?
    private let lock = NSLock()

    func open(path: String?) {
        guard let path else { return }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func write(_ record: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        var r = record
        r["t"] = (ProcessClock.seconds() * 1000).rounded() / 1000          // même horloge que le modèle (mesure 3)
        guard let data = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
        handle?.write(Data((line + "\n").utf8))
    }
}
#endif
