import SwiftUI
import AppSupport
import LyricsCore

/// Fenêtre « À propos et droits » (textes de la maquette ; le lien « Signaler » n'ouvre rien tant que l'URL n'est pas vérifiée).
struct AboutView: View {
    var close: @MainActor () -> Void
    private let link = Color(red: 0.486, green: 0.753, blue: 1)

    /// Transparence réseau (même phrase que dans le README, rubrique Vie privée) ; avis juridique non analysé.
    static let networkSentence = "Pour trouver les paroles, le titre, l'artiste, l'album et la durée du morceau en cours sont envoyés à lrclib.net (avec ton adresse IP, comme toute requête web). Si « Couleurs de la pochette » est activé, la pochette du morceau Spotify est téléchargée une fois depuis le serveur d'images de Spotify (i.scdn.co) et gardée en mémoire seulement ; celle d'Apple Music est lue dans l'app Musique, sans téléchargement. Rien d'autre ne quitte ton Mac : ni statistiques, ni rapport de plantage."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AppIdentity.displayName).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(SettingsView.version)\(AppIdentity.nameIsProvisional ? " · nom provisoire" : "")").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).padding(.top, 4)
            Group {
                Text("Paroles fournies par ") + Text("LRCLIB").bold() + Text(" (lrclib.net), base communautaire.")
                Text("Les paroles appartiennent à leurs auteurs et éditeurs. Elles sont affichées pour un usage personnel ; cette application ne les stocke pas sur un serveur et ne les redistribue pas.")
                Text(Self.networkSentence)
                Text("Application indépendante, non affiliée à LRCLIB, Spotify ou Apple.")
                Text("Signaler un problème avec ces paroles").foregroundStyle(link)
            }
            .font(.system(size: 13)).lineSpacing(13 * 1.55 - 16).foregroundStyle(.white.opacity(0.85)).padding(.top, 10)
            Button { close() } label: {
                Text("Fermer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 10 / 255, green: 132 / 255, blue: 1)))
            }
            .buttonStyle(.plain).padding(.top, 16).accessibilityLabel("Fermer la fenêtre À propos et droits")
        }
        .padding(.horizontal, 26).padding(.vertical, 24)
        .frame(width: 440, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            GlassCard(tint: Color(red: 40 / 255, green: 40 / 255, blue: 48 / 255), tintOpacity: 0.82, radius: 18,
                      gradientStart: 0, gradientEnd: 0, border: 0.18, highlight: 0)
        }
        .environment(\.colorScheme, .dark)
    }
}
