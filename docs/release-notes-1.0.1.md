# Lyra Lyrics 1.0.1

## English

Fixes for three problems reported with 1.0.0.

- **Well-known songs not found.** LRCLIB's exact lookup often answers "busy" (HTTP 503) the first time it sees a song; 1.0.0 repeated the same request three times and then displayed "Lyrics unavailable". Now it moves straight to the search endpoint, retries the failed requests after the server's `Retry-After`, searches more widely (title without "(feat. …)" / "- Remastered", first artist, "The" ignored, combined query) and accepts lyrics whose duration differs by up to 15 s (instead of 5 s) when title and artist match. A temporary error never shows "Lyrics unavailable" any more: the window says "Lyrics service busy", retries by itself and offers a **Retry** button. Measured against the real LRCLIB with 22 well-known songs: 17 of 22 found with synchronised lyrics before, all 20 replayed ones after (2 not replayed, same code path as before; 59 of the 60 allowed requests used).
- **Click-through and the settings panel.** Turning click-through on closes the settings panel, a 3-second notice tells how to come back, and the panel now has a visible **×** button and closes with **Esc**.
- **Playback buttons with Spotify.** The Automation permission belongs to the app's identifier, which changed with the rename. While it has not been asked yet, the buttons look active and the first click asks for it (a one-line explanation, then the system prompt) and sends the command; if you refused it, a click offers "Open Settings". The settings panel states the real Spotify permission status.

**Download:** `Lyra-Lyrics-1.0.1-macOS.zip` (1,832,074 bytes)
**SHA-256:** `1c150c7954cb7088815f83e435b6703911d1b904170619aff355e858c90b95e2`

**First launch (important).** The app is **not notarised** by Apple, so macOS blocks it the first time. Move **Lyra Lyrics.app** to Applications, open it, then go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**, and confirm. The exact wording may differ on your version of macOS. If you installed 1.0.0, the Automation permission for Spotify may have to be granted again (first click on a playback button).

Known limitations: the real permission prompt and the real playback commands from the buttons are not yet verified on a real player (tested with a simulated permission and sender); LRCLIB is community-run and sometimes busy or without lyrics for a song. See the [README](../README.md) and the [changelog](../CHANGELOG.md).

## Français

Corrections de trois problèmes signalés avec la 1.0.0.

- **Titres connus introuvables.** La requête exacte de LRCLIB répond souvent « occupé » (HTTP 503) la première fois qu'elle voit un morceau ; la 1.0.0 répétait trois fois la même requête puis affichait « Paroles indisponibles ». Maintenant, l'app passe tout de suite à la recherche, réessaie les requêtes en échec après le `Retry-After` du serveur, cherche plus largement (titre sans « (feat. …) » / « - Remastered », premier artiste, « The » ignoré, requête combinée) et accepte des paroles dont la durée diffère jusqu'à 15 s (au lieu de 5 s) quand le titre et l'artiste correspondent. Une erreur passagère n'affiche plus jamais « Paroles indisponibles » : la fenêtre dit « Service de paroles occupé », réessaie seule et propose un bouton **Réessayer**. Mesuré contre le vrai LRCLIB sur 22 morceaux connus : 17 sur 22 trouvés avec paroles synchronisées avant, les 20 rejoués après (2 non rejoués, même chemin de code qu'avant ; 59 des 60 requêtes permises utilisées).
- **Clic-à-travers et volet de réglages.** Activer le clic-à-travers ferme le volet, un avis de 3 secondes dit comment revenir, et le volet a maintenant un bouton **×** visible et se ferme avec **Échap**.
- **Boutons de lecture avec Spotify.** L'autorisation Automatisation est liée à l'identifiant de l'app, qui a changé avec le renommage. Tant qu'elle n'a pas été demandée, les boutons ont l'air actifs et le premier clic la demande (une phrase d'explication, puis l'invite du système) et envoie la commande ; si tu l'as refusée, un clic propose « Ouvrir les Réglages ». Le volet de réglages indique l'état réel de l'autorisation Spotify.

**Téléchargement :** `Lyra-Lyrics-1.0.1-macOS.zip` (1 832 074 octets)
**SHA-256 :** `1c150c7954cb7088815f83e435b6703911d1b904170619aff355e858c90b95e2`

**Premier lancement (important).** L'app n'est **pas notariée** par Apple : macOS la bloque la première fois. Glisse **Lyra Lyrics.app** dans Applications, ouvre-la, puis va dans **Réglages Système > Confidentialité et sécurité**, descends et clique sur **Ouvrir quand même**, puis confirme. Le texte exact peut différer selon ta version de macOS. Si tu avais installé la 1.0.0, l'autorisation Automatisation de Spotify peut devoir être accordée de nouveau (premier clic sur un bouton de lecture).

Limites connues : la vraie invite d'autorisation et les vraies commandes de lecture depuis les boutons ne sont pas encore vérifiées sur un vrai lecteur (testées avec une autorisation et un envoi simulés) ; LRCLIB est communautaire et parfois occupé ou sans paroles pour un titre. Voir le [README](../README.fr.md) et le [journal des versions](../CHANGELOG.md).
