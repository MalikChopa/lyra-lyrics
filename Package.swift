// swift-tools-version: 6.0
import PackageDescription

// Cibles : cœur portable (LyricsCore), lecteurs (PlayerKit), réglages (AppSupport), app (LyraLyrics) et outils de test.
// Plateforme : .macOS("26.0") (forme chaîne ; .v26 indisponible en outils 6.0, cf. R01). Aucune dépendance, aucun unsafeFlags.
let package = Package(
    name: "LyraLyrics",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "LyraLyrics", targets: ["LyraLyrics"]),
        .executable(name: "pf-fake-player", targets: ["pf-fake-player"]),
        .executable(name: "pf-fake-lrclib", targets: ["pf-fake-lrclib"]),
        .executable(name: "pf-window-probe", targets: ["pf-window-probe"]),
    ],
    targets: [
        // Cœur portable (Foundation seule : ni AppKit, ni CryptoKit ; hachage et transport injectés).
        .target(name: "LyricsCore"),
        .target(name: "PlayerKit", dependencies: ["LyricsCore"]),
        // J2 : réglages, raccourci, mise en page des lignes (Foundation seule, testables sans l'interface). Ajout hors §3.1 (délégué).
        .target(name: "AppSupport"),
        // J3 : moteur du faux LRCLIB (catalogue Fixtures/lrclib/, comportements 429/503/lenteur), partagé par `pf-fake-lrclib`
        // et par le transport en processus de l'app (DEBUG). Foundation seule. Ajout hors §3.1 (délégué).
        .target(name: "FakeLRCLIB"),
        .executableTarget(name: "LyraLyrics", dependencies: ["LyricsCore", "PlayerKit", "AppSupport", "FakeLRCLIB"]),
        .executableTarget(name: "pf-fake-player"),
        .executableTarget(name: "pf-fake-lrclib", dependencies: ["FakeLRCLIB"]),
        .executableTarget(name: "pf-window-probe"),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore", "FakeLRCLIB"]),
        .testTarget(name: "PlayerKitTests", dependencies: ["PlayerKit"]),
        .testTarget(name: "AppSupportTests", dependencies: ["AppSupport"]),
    ]
)
