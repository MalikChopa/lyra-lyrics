#if DEBUG
import Foundation
import LyricsCore
import FakeLRCLIB

/// Transport en processus (DEBUG, `--fake-player` sans `--lyrics-endpoint`) : le moteur du faux LRCLIB répond sans aucun
/// réseau, à partir de Fixtures/lrclib/catalog.json (paroles INVENTÉES). Même logique que `pf-fake-lrclib`.
final class InProcessFakeTransport: LRCLIBTransport, @unchecked Sendable {
    let engine: FakeLRCLIBEngine

    init(engine: FakeLRCLIBEngine) { self.engine = engine }

    static func fromCatalog() -> InProcessFakeTransport? {
        guard let path = FakeLRCLIBEngine.defaultCatalogPath(), let catalog = try? FakeLRCLIBEngine.loadCatalog(at: path) else { return nil }
        return InProcessFakeTransport(engine: FakeLRCLIBEngine(catalog: catalog))
    }

    func send(_ request: URLRequest, timeout: Double) async throws -> HTTPResponse {
        let path = request.url?.path ?? "/"
        let query = request.url?.query.map { "?" + $0 } ?? ""
        let r = engine.handle(method: request.httpMethod ?? "GET", rawTarget: path + query)
        if r.delay > 0 {
            if r.delay > timeout {
                try await Task.sleep(for: .seconds(timeout))
                throw LRCLIBError.timeout
            }
            try await Task.sleep(for: .seconds(r.delay))
        }
        return HTTPResponse(status: r.status, headers: Dictionary(r.headers, uniquingKeysWith: { a, _ in a }), body: r.body)
    }
}
#endif
