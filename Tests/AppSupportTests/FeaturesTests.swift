import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AppSupport

// MARK: Réglages : lignes, thèmes

@Suite("Fonctions 1.0 : réglages")
struct FeaturesSettingsTests {
    @Test("nombre de lignes : 1, 3 (défaut) ou 5 ; les autres valeurs sont ramenées")
    func lineCount() {
        #expect(Settings().lineCount == 3)
        #expect([0, 1, 2, 3, 4, 5, 9, -4].map(LineCount.clamped) == [1, 1, 3, 3, 5, 5, 5, 1])
        var s = Settings(); s.lineCount = 4; s.clamp(); #expect(s.lineCount == 5)
    }

    @Test("un thème règle police, graisse, couleur, halo et rapport d'un coup ; la taille n'est pas touchée")
    func themeApplication() {
        for theme in FontTheme.ready {
            var s = Settings(); s.size = 31
            s.apply(theme: theme)
            let spec = theme.spec!
            #expect(s.font == spec.font); #expect(s.fontWeight == spec.weight); #expect(s.colorIndex == spec.colorIndex)
            #expect(s.glow == spec.glow); #expect(s.neighbourRatio == spec.neighbourRatio)
            #expect(s.size == 31)
            #expect(s.fontTheme == theme)
        }
        #expect(Settings().fontTheme == .classic)
        // les quatre thèmes sont distincts
        #expect(Set(FontTheme.ready.compactMap { $0.spec }.map { "\($0)" }).count == 4)
    }

    @Test("un réglage individuel après un thème = « Personnalisé » ; revenir aux valeurs du thème le retrouve")
    func custom() {
        var s = Settings(); s.apply(theme: .neon)
        #expect(s.fontTheme == .neon)
        s.font = .sfMono; #expect(s.fontTheme == .custom)
        s.apply(theme: .neon); #expect(s.fontTheme == .neon)
        s.glow = false; #expect(s.fontTheme == .custom)
        s.apply(theme: .custom); #expect(s.fontTheme == .custom)       // sans effet
    }

    @Test("décodage tolérant : anciens réglages sans les nouveaux champs ; aller-retour ; pochette activée par défaut")
    func codable() {
        let (old, outcome) = Settings.decode(Data(#"{"version":1,"style":"solid","size":40}"#.utf8))
        #expect(outcome == .ok); #expect(old.lineCount == 3); #expect(old.artworkColors); #expect(old.fontWeight == .bold); #expect(!old.glow)
        var s = Settings(); s.lineCount = 5; s.apply(theme: .elegant); s.artworkColors = false
        let (back, _) = Settings.decode(s.encoded())
        #expect(back == s); #expect(back.fontTheme == .elegant); #expect(back.lineCount == 5); #expect(!back.artworkColors)
        let (bad, _) = Settings.decode(Data(#"{"version":1,"lineCount":2,"neighbourRatio":9}"#.utf8))
        #expect(bad.lineCount == 3); #expect(bad.neighbourRatio == 0.85)
    }
}

// MARK: Mise en page des lignes

@Suite("Fonctions 1.0 : lignes visibles")
struct FeaturesLayoutTests {
    static let fitter = LineFitter { text, size, width in
        let perLine = max(1, Int(width / (size * 0.5)))
        return Double(max(1, (text.count + perLine - 1) / perLine)) * size * 1.22
    }

    @Test("la hauteur de fenêtre s'adapte : 1 ligne < 3 lignes < 5 lignes (même texte court, même taille)")
    func heightGrows() {
        let one = Self.fitter.fit(lines: ["a"], baseSize: 26, visibleHeight: 1000)
        let three = Self.fitter.fit(lines: ["a", "b", "c"], baseSize: 26, visibleHeight: 1000)
        let five = Self.fitter.fit(lines: ["a", "b", "c", "d", "e"], baseSize: 26, visibleHeight: 1000)
        #expect(one.windowHeight == 120); #expect(three.windowHeight == 190)
        #expect(five.windowHeight > three.windowHeight)
        #expect(one.contentHeight < three.contentHeight); #expect(three.contentHeight < five.contentHeight)
    }

    @Test("la ligne courante est celle du milieu ; voisines mesurées à la taille de la courante puis réduites")
    func scaledNeighbours() {
        let h = Self.fitter.displayedHeights(lines: ["x", "x", "x", "x", "x"], currentSize: 30, ratio: 0.66)
        #expect(h[2] > h[1]); #expect(h[1] == h[3]); #expect(h[1] > h[0]); #expect(h[0] == h[4])
        #expect(abs(h[1] / h[2] - 0.66) < 0.0001); #expect(abs(h[0] / h[2] - 0.66 * 0.88) < 0.0001)
    }

    @Test("règles des lignes longues inchangées avec 5 lignes : la fenêtre grandit, puis la police diminue, plancher 14 pt")
    func longLinesFiveLines() {
        let long = String(repeating: "x", count: 80)
        let grows = Self.fitter.fit(lines: Array(repeating: long, count: 5), baseSize: 30, visibleHeight: 2000)
        #expect(grows.currentSize == 30); #expect(grows.windowHeight > 190)
        let shrinks = Self.fitter.fit(lines: Array(repeating: long, count: 5), baseSize: 44, visibleHeight: 700)
        #expect(shrinks.shrunk); #expect(shrinks.currentSize >= 14); #expect(shrinks.windowHeight <= 700 * 0.8 + 0.5)
        let huge = String(repeating: "x", count: 5000)
        let capped = Self.fitter.fit(lines: Array(repeating: huge, count: 5), baseSize: 44, visibleHeight: 600)
        #expect(capped.currentSize == 14); #expect(capped.exceedsMaxHeight); #expect(capped.windowHeight == 600)
    }

    @Test("aspect : échelle, opacité et flou décroissent avec l'éloignement")
    func look() {
        #expect(LineLook.scale(offset: 0, ratio: 0.66) == 1)
        #expect(LineLook.scale(offset: -1, ratio: 0.66) == 0.66 && LineLook.scale(offset: 1, ratio: 0.66) == 0.66)
        #expect(LineLook.scale(offset: 2, ratio: 0.66) < 0.66)
        #expect(LineLook.opacity(offset: 0) > LineLook.opacity(offset: 1)); #expect(LineLook.opacity(offset: 1) > LineLook.opacity(offset: 2))
        #expect(LineLook.blur(offset: 0) == 0); #expect(LineLook.blur(offset: 2) > LineLook.blur(offset: 1))
    }
}

// MARK: Couleurs de pochette

/// Pochettes INVENTÉES (aplats et dégradés) générées en mémoire.
private func rgba(_ pixels: [(Double, Double, Double)], width: Int = 16) -> [UInt8] {
    pixels.flatMap { [UInt8($0.0 * 255), UInt8($0.1 * 255), UInt8($0.2 * 255), 255] }
}
private func flat(_ c: (Double, Double, Double), n: Int = 256) -> [UInt8] { rgba(Array(repeating: c, count: n)) }
private func png(_ pixels: [UInt8], side: Int) -> Data {
    var p = pixels
    let ctx = p.withUnsafeMutableBytes {
        CGContext(data: $0.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    let image = ctx.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

@Suite("Fonctions 1.0 : couleurs de pochette")
struct FeaturesPaletteTests {
    @Test("contraste WCAG : noir/blanc = 21, identique = 1, valeurs connues")
    func wcag() {
        #expect(abs(RGB.contrast(RGB(0, 0, 0), RGB(1, 1, 1)) - 21) < 0.001)
        #expect(abs(RGB.contrast(RGB(0.5, 0.5, 0.5), RGB(0.5, 0.5, 0.5)) - 1) < 0.001)
        // #767676 sur blanc = 4,54 (valeur de référence WCAG)
        #expect(abs(RGB.contrast(RGB(118 / 255, 118 / 255, 118 / 255), RGB(1, 1, 1)) - 4.54) < 0.02)
    }

    @Test("dominante : la couleur de la plus grande zone, la secondaire est une couleur nettement différente")
    func dominantAndSecondary() throws {
        // 75 % de bleu, 25 % de jaune
        var px = [(Double, Double, Double)](repeating: (0.1, 0.3, 0.8), count: 192)
        px += [(Double, Double, Double)](repeating: (0.95, 0.8, 0.2), count: 64)
        let p = try #require(ArtworkPalette.from(rgba: rgba(px), width: 16, height: 16))
        #expect(p.dominant.hsb.h > 0.5 && p.dominant.hsb.h < 0.7)           // bleu
        #expect(p.secondary.hsb.h > 0.08 && p.secondary.hsb.h < 0.2)         // jaune
        #expect(p.dominant.hex == RGB(0.1, 0.3, 0.8).hex || RGB(0.1, 0.3, 0.8).mixed(with: p.dominant, 1).hex == p.dominant.hex)
    }

    @Test("lisibilité : l'accent respecte 4,5 : 1 contre la teinte pour des pochettes variées (rouge, jaune pâle, blanc, noir, gris, vert vif)")
    func contrastGuaranteed() throws {
        let covers: [(String, (Double, Double, Double))] = [
            ("rouge", (0.9, 0.1, 0.1)), ("jaune pâle", (1, 0.97, 0.7)), ("blanc", (1, 1, 1)), ("noir", (0, 0, 0)),
            ("gris", (0.5, 0.5, 0.5)), ("vert vif", (0, 1, 0.2)), ("cyan", (0, 0.9, 1)), ("violet foncé", (0.2, 0, 0.3)),
        ]
        for (name, c) in covers {
            let p = try #require(ArtworkPalette.from(rgba: flat(c), width: 16, height: 16), "\(name)")
            #expect(p.accentContrast >= ArtworkPalette.minContrast, "\(name) : \(p.accentContrast)")
            #expect(p.tint.hsb.v <= ArtworkPalette.maxTintValue + 0.0001, "\(name) : teinte trop claire")
        }
    }

    @Test("balayage : 300 couleurs au hasard (graine fixe), contraste toujours >= 4,5")
    func sweep() {
        var seed: UInt64 = 42
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        for _ in 0..<300 {
            let a = (next(), next(), next()), b = (next(), next(), next())
            let px = Array(repeating: a, count: 150) + Array(repeating: b, count: 106)
            guard let p = ArtworkPalette.from(rgba: rgba(px), width: 16, height: 16) else { Issue.record("palette nulle"); return }
            #expect(p.accentContrast >= ArtworkPalette.minContrast)
        }
    }

    @Test("image vide ou transparente : pas de palette")
    func empty() {
        #expect(ArtworkPalette.from(rgba: [], width: 0, height: 0) == nil)
        #expect(ArtworkPalette.from(rgba: [UInt8](repeating: 0, count: 16 * 16 * 4), width: 16, height: 16) == nil)
    }

    @Test("décodage d'un vrai PNG en mémoire (ImageIO) ; données invalides ou trop grosses : nil")
    func decode() throws {
        let data = png(flat((0.2, 0.7, 0.3), n: 32 * 32), side: 32)
        let p = try #require(ArtworkDecoder.palette(from: data))
        #expect(p.dominant.hsb.h > 0.25 && p.dominant.hsb.h < 0.45)         // vert
        #expect(p.accentContrast >= 4.5)
        #expect(ArtworkDecoder.palette(from: Data("pas une image".utf8)) == nil)
        #expect(ArtworkDecoder.palette(from: Data(count: ArtworkDecoder.maxBytes + 1)) == nil)
    }
}

// MARK: Politique de la pochette

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private struct StubTransport: ArtworkTransport {
    var counter: Counter
    var data: Data
    var delay: Duration = .zero
    func data(from url: URL) async throws -> Data {
        counter.bump()
        try await Task.sleep(for: delay)
        return data
    }
}

@Suite("Fonctions 1.0 : politique de la pochette")
@MainActor
struct FeaturesArtworkPolicyTests {
    nonisolated static let coverPNG = png(flat((0.8, 0.2, 0.2), n: 32 * 32), side: 32)

    @MainActor final class Probe {
        var delivered: [(String, ArtworkPalette?)] = []
        /// Attend (au plus 5 s) que `n` livraisons soient arrivées : le premier décodage ImageIO peut être lent à froid.
        func waitFor(_ n: Int) async {
            for _ in 0..<500 where delivered.count < n { try? await Task.sleep(for: .milliseconds(10)) }
        }
    }

    fileprivate func makeService(enabled: @escaping @MainActor () -> Bool, reads: Counter, http: Counter, delay: Duration = .zero, probe: Probe)
        -> ArtworkService {
        let providers = ArtworkProviders(
            musicData: { reads.bump(); return Self.coverPNG },
            spotifyURL: { reads.bump(); return "https://i.scdn.co/image/abc123" },
            transport: StubTransport(counter: http, data: Self.coverPNG, delay: delay))
        return ArtworkService(enabled: enabled, providers: providers, deliver: { probe.delivered.append(($0, $1)) })
    }

    @Test("réglage désactivé : AUCUN Apple event et AUCUN HTTP, aucune livraison")
    func nothingWhenOff() async throws {
        let reads = Counter(), http = Counter(), probe = Probe()
        let service = makeService(enabled: { false }, reads: reads, http: http, probe: probe)
        service.trackChanged(identity: "a", source: .spotify, permitted: true)
        service.trackChanged(identity: "b", source: .appleMusic, permitted: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(reads.value == 0); #expect(http.value == 0); #expect(probe.delivered.isEmpty)
        #expect(service.started == 0); #expect(service.skippedDisabled == 2)
    }

    @Test("autorisation absente : aucune requête (aucune invite provoquée)")
    func nothingWithoutPermission() async throws {
        let reads = Counter(), http = Counter(), probe = Probe()
        let service = makeService(enabled: { true }, reads: reads, http: http, probe: probe)
        service.trackChanged(identity: "a", source: .spotify, permitted: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(reads.value == 0); #expect(http.value == 0)
    }

    @Test("Apple Music : octets par Apple event, jamais d'HTTP ; palette livrée pour le bon titre")
    func musicPath() async throws {
        let reads = Counter(), http = Counter(), probe = Probe()
        let service = makeService(enabled: { true }, reads: reads, http: http, probe: probe)
        service.trackChanged(identity: "m1", source: .appleMusic, permitted: true)
        await probe.waitFor(1)
        #expect(reads.value == 1); #expect(http.value == 0)
        #expect(probe.delivered.count == 1 && probe.delivered[0].0 == "m1" && probe.delivered[0].1 != nil)
    }

    @Test("Spotify : une lecture d'URL puis UN SEUL GET")
    func spotifyPath() async throws {
        let reads = Counter(), http = Counter(), probe = Probe()
        let service = makeService(enabled: { true }, reads: reads, http: http, probe: probe)
        service.trackChanged(identity: "s1", source: .spotify, permitted: true)
        await probe.waitFor(1)
        #expect(reads.value == 1); #expect(http.value == 1)
        #expect(probe.delivered.map(\.0) == ["s1"])
    }

    @Test("changement de titre : la requête en cours est ANNULÉE, sa réponse n'est jamais livrée")
    func cancelledOnTrackChange() async throws {
        let reads = Counter(), http = Counter(), probe = Probe()
        let service = makeService(enabled: { true }, reads: reads, http: http, delay: .seconds(1), probe: probe)
        service.trackChanged(identity: "lent", source: .spotify, permitted: true)
        for _ in 0..<300 where http.value < 1 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(http.value == 1); #expect(service.isBusy)
        service.trackChanged(identity: "autre", source: .appleMusic, permitted: true)
        #expect(service.cancelled == 1)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(probe.delivered.map(\.0) == ["autre"])
        // fin de lecture : annulation sans livraison
        service.trackChanged(identity: "lent2", source: .spotify, permitted: true)
        for _ in 0..<300 where http.value < 2 { try await Task.sleep(for: .milliseconds(10)) }
        service.cancel()
        try await Task.sleep(for: .milliseconds(1200))
        #expect(probe.delivered.map(\.0) == ["autre"])
    }

    @Test("URL de pochette : https et hôte du CDN d'images de Spotify seulement")
    func urlValidation() {
        #expect(ArtworkPolicy.validated("https://i.scdn.co/image/ab67616d0000b273") != nil)
        for bad in ["http://i.scdn.co/image/x", "https://example.com/x.png", "https://i.scdn.co.evil.example/x", "https://user:pw" + "\u{40}" + "i.scdn.co/x",
                    "https://i.scdn.co:8443/x", "file:///etc/passwd", "ftp://i.scdn.co/x", "", "pas une url", "https://evil.example/i.scdn.co"] {
            #expect(ArtworkPolicy.validated(bad) == nil, "\(bad)")
        }
        #expect(ArtworkPolicy.allowedHosts == ["i.scdn.co"])
        // bouclage de l'autotest : seulement si l'appelant l'autorise explicitement
        #expect(ArtworkPolicy.validated("http://127.0.0.1:4181/art/x.png") == nil)
        #expect(ArtworkPolicy.validated("http://127.0.0.1:4181/art/x.png", extraHosts: ["127.0.0.1"], allowInsecureLoopback: true) != nil)
    }

    @Test("jamais sur le disque : session éphémère, ni cache d'URL, ni cookies, ni identifiants ; aucun fichier créé")
    func neverOnDisk() async throws {
        let config = URLSessionArtworkTransport.makeConfiguration(userAgent: "Test/1")
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(config.httpCookieStorage == nil); #expect(config.httpShouldSetCookies == false); #expect(config.urlCredentialStorage == nil)
        #expect(config.identifier == nil)                            // une session de fond (identifiant) écrirait sur le disque
        #expect(config.waitsForConnectivity == false)
        // Aucun fichier créé dans le dossier temporaire par un cycle complet (palette comprise).
        let tmp = NSTemporaryDirectory()
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? [])
        let reads = Counter(), http = Counter(), probe = Probe()
        let service = makeService(enabled: { true }, reads: reads, http: http, probe: probe)
        service.trackChanged(identity: "s", source: .spotify, permitted: true)
        await probe.waitFor(1)
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? [])
        #expect(after.subtracting(before).isEmpty)
        #expect(probe.delivered.count == 1)
    }
}

// MARK: Fenêtre redimensionnable

@Suite("Fonctions 1.0 : fenêtre redimensionnable")
struct FeaturesResizeTests {
    static let fitter = FeaturesLayoutTests.fitter
    static let lines = ["Les phares glissent sur la mer", "Et la ville s'éteint sans bruit", "Je compte les vagues une à une"]

    @Test("trois tailles de fenêtre donnent trois tailles de police croissantes (jusqu'à la taille max)")
    func textFollowsWindow() {
        let sizes = [(300.0, 130.0), (460.0, 190.0), (640.0, 280.0)].map {
            Self.fitter.fit(lines: Self.lines, baseSize: 44, fixedWindowWidth: $0.0, fixedWindowHeight: $0.1, ratio: 0.66).currentSize
        }
        #expect(sizes[0] < sizes[1]); #expect(sizes[1] < sizes[2])
        #expect(sizes[0] >= 14); #expect(sizes[2] <= 44)
        // jamais au-dessus de la taille max
        let capped = Self.fitter.fit(lines: Self.lines, baseSize: 20, fixedWindowWidth: 1500, fixedWindowHeight: 900, ratio: 0.66)
        #expect(capped.currentSize == 20); #expect(!capped.shrunk)
    }

    @Test("la hauteur compte autant que la largeur")
    func heightMatters() {
        let tall = Self.fitter.fit(lines: Self.lines, baseSize: 44, fixedWindowWidth: 1200, fixedWindowHeight: 500, ratio: 0.66)
        let flat = Self.fitter.fit(lines: Self.lines, baseSize: 44, fixedWindowWidth: 1200, fixedWindowHeight: 150, ratio: 0.66)
        #expect(flat.currentSize < tall.currentSize)
    }

    @Test("retour à la ligne seulement si la ligne la plus longue ne tient pas, même au plancher de 14 pt")
    func wrapsOnlyAtFloor() {
        let ok = Self.fitter.fit(lines: Self.lines, baseSize: 44, fixedWindowWidth: 460, fixedWindowHeight: 400, ratio: 0.66)
        // le bouchon compte une ligne de moins de 0,5 × taille par caractère : pas de retour à la ligne tant que la police est > 14
        #expect(ok.currentSize > 14)
        let one = Self.fitter.measure("M", ok.currentSize, LyricsMetrics.textWidth(forWindowWidth: 460))
        #expect(Self.fitter.measure(Self.lines[1], ok.currentSize, LyricsMetrics.textWidth(forWindowWidth: 460)) <= one * 1.4)
        let long = [String(repeating: "x", count: 300), String(repeating: "y", count: 300), String(repeating: "z", count: 300)]
        let f = Self.fitter.fit(lines: long, baseSize: 44, fixedWindowWidth: 460, fixedWindowHeight: 190, ratio: 0.66)
        #expect(f.currentSize == 14)
        #expect(Self.fitter.measure(long[1], 14, LyricsMetrics.textWidth(forWindowWidth: 460)) > Self.fitter.measure("M", 14, LyricsMetrics.textWidth(forWindowWidth: 460)) * 1.4)
        #expect(f.exceedsMaxHeight)
    }

    @Test("le nombre de lignes est respecté : 5 lignes demandent plus de place que 1")
    func lineCountRespected() {
        let one = Self.fitter.fit(lines: ["Les phares glissent sur la mer"], baseSize: 44, fixedWindowWidth: 700, fixedWindowHeight: 220, ratio: 0.66)
        let five = Self.fitter.fit(lines: Self.lines + Self.lines.prefix(2), baseSize: 44, fixedWindowWidth: 700, fixedWindowHeight: 220, ratio: 0.66)
        #expect(five.currentSize < one.currentSize)
    }

    @Test("limites de taille : 280 × 110 minimum, 90 % de la zone visible maximum")
    func limits() {
        let v = (width: 1710.0, height: 1074.0)
        #expect(LyricsMetrics.clampedSize(width: 10, height: 10, visible: v) == (280, 110))
        let big = LyricsMetrics.clampedSize(width: 99999, height: 99999, visible: v)
        #expect(abs(big.width - 1539) < 0.001); #expect(abs(big.height - 966.6) < 0.001)
        #expect(LyricsMetrics.clampedSize(width: 500, height: 200, visible: v) == (500, 200))
        // zone visible minuscule : le minimum l'emporte
        #expect(LyricsMetrics.clampedSize(width: 400, height: 400, visible: (200, 100)) == (280, 110))
    }

    @Test("taille imposée : valeurs rangées, persistées, tolérantes ; « Taille par défaut » = nil")
    func persistence() {
        var s = Settings()
        #expect(s.manualSize == nil)
        s.windowWidth = 100; s.windowHeight = 50; s.clamp()
        #expect(s.manualSize?.width == 280); #expect(s.manualSize?.height == 110)
        s.windowWidth = 620; s.windowHeight = 240
        let (back, _) = Settings.decode(s.encoded())
        #expect(back.manualSize?.width == 620); #expect(back.manualSize?.height == 240)
        var half = Settings(); half.windowWidth = 600; half.clamp()
        #expect(half.manualSize == nil && half.windowWidth == nil)           // une seule valeur : retour à l'automatique
        let (old, _) = Settings.decode(Data(#"{"version":1}"#.utf8))
        #expect(old.manualSize == nil)
        #expect(LyricsMetrics.textWidth(forWindowWidth: 460) == 404)
    }
}
