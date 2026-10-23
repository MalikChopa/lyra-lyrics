// Faux LRCLIB (§8.3) : `pf-fake-lrclib --port <p> [--catalog <chemin>]`, 127.0.0.1 seulement, port libre ≥ 4180.
// Sert Fixtures/lrclib/catalog.json (paroles INVENTÉES) : 200, 404, instrumental, texte seul, 429 + Retry-After,
// 503 en série, lenteur. `GET /_fake/log` (journal des requêtes, sans paroles), `/_fake/reset`, `/_fake/quit`.
// Sockets BSD + HTTP/1.1 minimal (GET, `Connection: close`), sans dépendance.
import Foundation
import FakeLRCLIB

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("pf-fake-lrclib : \(message)\n".utf8))
    exit(2)
}

let args = CommandLine.arguments
func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
guard let portText = value("--port"), let port = UInt16(portText), port >= 4180 else {
    fail("usage : pf-fake-lrclib --port <libre ≥ 4180> [--catalog Fixtures/lrclib/catalog.json]")
}
guard let catalogPath = value("--catalog") ?? FakeLRCLIBEngine.defaultCatalogPath() else { fail("catalogue introuvable (Fixtures/lrclib/catalog.json)") }
let catalog: FakeCatalog
do { catalog = try FakeLRCLIBEngine.loadCatalog(at: catalogPath) } catch { fail("catalogue illisible : \(error)") }
let engine = FakeLRCLIBEngine(catalog: catalog)
engine.artDirectory = value("--art-dir") ?? FakeLRCLIBEngine.defaultArtDirectory()

signal(SIGPIPE, SIG_IGN)
let listener = socket(AF_INET, SOCK_STREAM, 0)
guard listener >= 0 else { fail("socket() a échoué") }
var reuse: Int32 = 1
setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
guard bound == 0 else { fail("bind 127.0.0.1:\(port) a échoué (port occupé ?) errno=\(errno)") }
guard listen(listener, 16) == 0 else { fail("listen() a échoué") }
print("pf-fake-lrclib : écoute sur http://127.0.0.1:\(port) ; catalogue \(catalogPath) (\(engine.recordCount) entrées) ; /_fake/quit pour arrêter")
fflush(stdout)

let started = Date()
let stdoutLock = NSLock()

@Sendable func serve(_ client: Int32) {
    defer { close(client) }
    var buffer = [UInt8](repeating: 0, count: 65536)
    var received = Data()
    while received.count < 65536 {
        let n = recv(client, &buffer, buffer.count, 0)
        if n <= 0 { break }
        received.append(buffer, count: n)
        if received.range(of: Data("\r\n\r\n".utf8)) != nil { break }
    }
    // UTF-8 d'abord ; sinon Latin-1 : CFNetwork (URLSession) encode un en-tête non ASCII (« non publié ») en ISO-8859-1,
    // et un décodage UTF-8 strict fermait la connexion sans réponse (-1005 côté app ; trouvé à J3).
    guard let text = String(data: received, encoding: .utf8) ?? String(data: received, encoding: .isoLatin1),
          let requestLine = text.split(separator: "\r\n", omittingEmptySubsequences: true).first else { return }
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else { return }
    let method = String(parts[0])
    let target = String(parts[1])
    let response = engine.handle(method: method, rawTarget: target)
    if response.delay > 0 { Thread.sleep(forTimeInterval: response.delay) }
    var head = "HTTP/1.1 \(response.status) \(FakeLRCLIBEngine.reasonPhrase(response.status))\r\n"
    for (k, v) in response.headers { head += "\(k): \(v)\r\n" }
    head += "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
    var out = Data(head.utf8)
    out.append(response.body)
    out.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let n = send(client, raw.baseAddress! + offset, raw.count - offset, 0)
            if n <= 0 { break }
            offset += n
        }
    }
    let t = String(format: "%.3f", Date().timeIntervalSince(started))
    let retry = response.headers.first { $0.0 == "Retry-After" }.map { " Retry-After=\($0.1)" } ?? ""
    let delay = response.delay > 0 ? String(format: " lenteur=%.1fs", response.delay) : ""
    stdoutLock.lock()
    print("t=\(t) \(method) \(target.removingPercentEncoding ?? target) -> \(response.status)\(retry)\(delay)")
    fflush(stdout)
    stdoutLock.unlock()
    if response.shouldQuit {
        print("pf-fake-lrclib : arrêt demandé (/_fake/quit)")
        fflush(stdout)
        exit(0)
    }
}

while true {
    let client = accept(listener, nil, nil)
    if client < 0 { continue }
    DispatchQueue.global(qos: .userInitiated).async { serve(client) }
}
