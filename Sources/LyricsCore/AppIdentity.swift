import Foundation

/// NOM DE L'APP : l'unique endroit à modifier pour renommer l'application. Tout le reste en découle :
/// - chaque texte d'interface, menu, À propos, états, titre de fenêtre, VoiceOver : `AppIdentity.displayName` ;
/// - le jeton du `User-Agent` : `userAgentToken` (ASCII, calculé) ;
/// - `Info.plist` (CFBundleName, CFBundleDisplayName, texte d'invite Automatisation) : `scripts/bundle.sh` lit la ligne
///   `displayName` de CE fichier et remplace le marqueur `@APP_NAME@` de `Resources/Info.plist` ;
/// - le nom du dossier `.app` et de l'archive zip : `scripts/package.sh` le lit au même endroit.
/// Rien d'autre à toucher, sauf : l'identifiant de bundle (`Resources/Info.plist` et `scripts/bundle.sh`) porte les
/// autorisations du système (le changer remet les autorisations à zéro et change le domaine des préférences), et le nom
/// de l'exécutable SwiftPM (`LyraLyrics`) est celui de la cible dans `Package.swift`.
public enum AppIdentity {
    // La ligne ci-dessous est lue par scripts/bundle.sh et scripts/package.sh (grep) : garder la forme `static let displayName = "…"`.
    public static let displayName = "Lyra Lyrics"
    /// Vrai tant que le nom est provisoire (affiché dans « À propos »). Faux depuis la version 1.0.0.
    public static let nameIsProvisional = false

    /// Version publiée (doit égaler `CFBundleShortVersionString` de `Resources/Info.plist` : un test le vérifie).
    public static let version = "1.0.0"
    /// Adresse du dépôt public (dans le User-Agent, pour que le service LRCLIB sache qui l'appelle).
    public static let projectURL = "https://github.com/MalikMoussaoui/lyra-lyrics"

    /// « Lyra Lyrics » → « LyraLyrics » : sans accents, sans espaces, ASCII seul (CFNetwork encode l'en-tête en Latin-1).
    public static var userAgentToken: String { token(from: displayName) }

    public static func token(from name: String) -> String {
        let ascii = name.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let words = ascii.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    public static var userAgent: String { "\(userAgentToken)/\(version) (+\(projectURL))" }

    // Phrases réutilisées par plusieurs écrans (une seule rédaction, une seule place pour le nom).
    public static var permissionBody: String { "Pour suivre Apple Music, autorise \(displayName)." }
    public static var permissionRefusedBody: String {
        "Pour suivre Apple Music, autorise \(displayName) dans Réglages Système > Confidentialité et sécurité > Automatisation."
    }
    public static var allowAccessibilityLabel: String { "Autoriser \(displayName) à suivre Apple Music" }
    public static var quitMenuTitle: String { "Quitter \(displayName)" }
}
