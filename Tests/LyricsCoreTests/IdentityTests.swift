import Testing
import Foundation
@testable import LyricsCore

@Suite("Nom de l'app : une seule source (J5)")
struct IdentityTests {
    @Test("jeton User-Agent : ASCII, sans espaces ni accents, calculé depuis le nom")
    func userAgentToken() {
        #expect(AppIdentity.token(from: "Lyra Lyrics") == "LyraLyrics")
        #expect(AppIdentity.token(from: "Mon appli flottante") == "MonAppliFlottante")      // calcul générique, indépendant du nom actuel
        #expect(AppIdentity.token(from: "Écho d'été — Plus") == "EchoDEtePlus")
        #expect(AppIdentity.token(from: "Lyrics") == "Lyrics")
        #expect(AppIdentity.userAgentToken.allSatisfy { $0.isASCII })
        #expect(AppIdentity.userAgent == "LyraLyrics/1.0.0 (+https://github.com/MalikMoussaoui/lyra-lyrics)")
        #expect(AppIdentity.userAgent.allSatisfy { $0.isASCII })
    }

    @Test("les textes qui citent le nom viennent de la constante")
    func textsUseName() {
        #expect(AppIdentity.permissionBody.contains(AppIdentity.displayName))
        #expect(AppIdentity.permissionRefusedBody.contains(AppIdentity.displayName))
        let s = DisplayState(screen: .permissionNeeded(refused: false), hasTrack: false)
        #expect(s.stateText?.body == AppIdentity.permissionBody)
    }

    /// `Resources/Info.plist` ne contient le nom qu'au travers du marqueur `@APP_NAME@` (remplacé par `scripts/bundle.sh`
    /// depuis `AppIdentity.displayName`) : renommer = modifier `AppIdentity.swift` seulement.
    @Test("Info.plist : le nom passe par le marqueur, jamais en dur")
    func infoPlistUsesMarker() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<key>CFBundleName</key><string>@APP_NAME@</string>"))
        #expect(plist.contains("<key>CFBundleDisplayName</key><string>@APP_NAME@</string>"))
        #expect(plist.contains("@APP_NAME@ lit le titre"))
        #expect(!plist.contains(AppIdentity.displayName))
        let source = try String(contentsOf: root.appendingPathComponent("Sources/LyricsCore/AppIdentity.swift"), encoding: .utf8)
        #expect(source.contains("public static let displayName = \"\(AppIdentity.displayName)\""))    // la ligne lue par bundle.sh
    }

    /// Identifiant, version et exécutable : ce que `Resources/Info.plist` fige doit rester cohérent avec le code.
    @Test("Info.plist : identifiant, version 1.0.0 et exécutable cohérents avec le code")
    func infoPlistIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<key>CFBundleIdentifier</key><string>io.github.malikmoussaoui.lyra-lyrics</string>"))
        #expect(plist.contains("<key>CFBundleShortVersionString</key><string>\(AppIdentity.version)</string>"))
        #expect(plist.contains("<key>CFBundleVersion</key><string>1</string>"))
        #expect(plist.contains("<key>CFBundleExecutable</key><string>LyraLyrics</string>"))
        #expect(AppIdentity.version == "1.0.0")
        #expect(!AppIdentity.nameIsProvisional)
    }

    @Test("« Autorisation nécessaire » : texte après refus mentionne le chemin des Réglages")
    func permissionTexts() {
        let refused = DisplayState(screen: .permissionNeeded(refused: true), hasTrack: false).stateText
        #expect(refused?.title == "Autorisation nécessaire")
        #expect(refused?.body.contains("Automatisation") == true)
    }
}
