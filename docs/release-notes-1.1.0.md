# Lyra Lyrics 1.1.0

## English

A full-screen **Scene** mode and a set of improvements.

- **Scene.** Click the full-screen button in the hover bar (or double-click the window): it zooms to full screen (choose the screen in the settings). The blurred cover drifts behind large lyrics, the current line is highlighted (optional karaoke-style fill, off by default; no glow by default), calm animations fill intros and instrumentals, a title card shows at each new song, with light grain and vignette. Esc, double-click, the exit button that appears when the mouse moves, or your shortcut leave it.
- **Richer Scene.** Layout setting: cover on the left with title and artist and lyrics on the right (default), or lyrics only; a control bar (previous, play/pause, next, progress, exit) when the mouse moves; Space, arrows and Esc; the leaving line rises and fades word by word; a livelier background.
- **Fixes.** A vertical line in the small window after widening it (animated cover background); the text colour you pick now always wins over the cover colours.
- **Wrong lyrics?** Search LRCLIB and pick another version; it is remembered for that song (identifier only, no text).
- Welcome screen at first launch, **launch at login**, **auto-hide** (when nothing plays by default), re-opening the app opens the settings, an elegant waiting animation while lyrics are searched, optional animated cover background and karaoke-style fill, a lighter plain-text block (about 0 % CPU).
- **New address and identifier.** The GitHub account was renamed: links point to `MalikChopa/lyra-lyrics` and the app identifier is now `io.github.malikchopa.lyra-lyrics`. If you ran an earlier version, your settings start from their defaults once and the Spotify Automation permission is asked again once.
- **Update notice.** At most one request a day at launch to `api.github.com` (this repository's latest release); nothing about you is sent; it can be switched off.

**Download:** `Lyra-Lyrics-1.1.0-macOS.zip` (2,125,066 bytes)
**SHA-256:** `677fb5f0a102cae67874ebd631f435d25c6f35989ea62c86c3c0f889c7461397`

**First launch (important).** The app is **not notarised**: move **Lyra Lyrics.app** to Applications, open it, then **System Settings > Privacy & Security > Open Anyway**. The exact wording may differ on your version of macOS.

Known limitations: tested with a fake player and invented lyrics and covers; the real Spotify permission prompt, real covers, a real second display and smoothness to the eye are not yet verified. Measured CPU (app process only, release build with debug flags, fake player): Scene 1.7 to 2.1 % on average, small window 0.2 %; the same figures as before this work on the same machine and the same day (1.9 to 2.1 % and 0.25 %). See the [README](../README.md) and the [changelog](../CHANGELOG.md).

## Français

Un mode **Scène** plein écran et une série d'améliorations.

- **Scène.** Clic sur le bouton plein écran de la barre au survol (ou double-clic sur la fenêtre) : elle grandit jusqu'au plein écran (écran à choisir dans les réglages). La pochette floue dérive derrière de grandes paroles, la ligne courante est mise en valeur (remplissage façon karaoké en option, désactivé par défaut ; aucune lueur par défaut), des animations calmes occupent les introductions et les instrumentaux, une carte s'affiche à chaque nouveau morceau, avec un grain et une vignette légers. Échap, double-clic, le bouton de sortie qui apparaît quand la souris bouge, ou ton raccourci pour en sortir.
- **Scène enrichie.** Réglage de mise en page : pochette à gauche avec titre et artiste, paroles à droite (défaut), ou paroles seules ; une barre de commandes (précédent, lecture/pause, suivant, progression, sortie) quand la souris bouge ; Espace, flèches et Échap ; la ligne qui part monte et s'efface mot à mot ; un fond plus vivant.
- **Corrections.** Une ligne verticale dans la petite fenêtre après l'avoir élargie (fond de pochette animé) ; la couleur de texte choisie l'emporte maintenant toujours sur les couleurs de la pochette.
- **Mauvaises paroles ?** Cherche sur LRCLIB et choisis une autre version ; elle est retenue pour ce morceau (identifiant seulement, jamais de texte).
- Écran d'accueil au premier lancement, **lancement à l'ouverture de session**, **masquage automatique** (quand rien ne joue par défaut), relancer l'app ouvre les réglages, attente élégante pendant la recherche des paroles, fond de pochette animé et remplissage façon karaoké en option, bloc de texte non synchronisé plus léger (environ 0 % de CPU).
- **Nouvelle adresse et nouvel identifiant.** Le compte GitHub a été renommé : les liens pointent vers `MalikChopa/lyra-lyrics` et l'identifiant de l'app devient `io.github.malikchopa.lyra-lyrics`. Si tu as déjà utilisé une version précédente, tes réglages repartent des valeurs par défaut une fois et l'autorisation Automatisation de Spotify est redemandée une fois.
- **Avis de nouvelle version.** Une requête par jour au plus, au lancement, vers `api.github.com` (dernière version de ce dépôt) ; rien de toi n'est envoyé ; désactivable.

**Téléchargement :** `Lyra-Lyrics-1.1.0-macOS.zip` (2 125 066 octets)
**SHA-256 :** `677fb5f0a102cae67874ebd631f435d25c6f35989ea62c86c3c0f889c7461397`

**Premier lancement (important).** L'app n'est **pas notariée** : glisse **Lyra Lyrics.app** dans Applications, ouvre-la, puis **Réglages Système > Confidentialité et sécurité > Ouvrir quand même**. Le texte exact peut différer selon ta version de macOS.

Limites connues : testé avec un faux lecteur, des paroles et des pochettes inventées ; la vraie invite Spotify, de vraies pochettes, un vrai second écran et la fluidité à l'œil ne sont pas encore vérifiés. CPU mesuré (processus de l'app seulement, build release avec drapeaux de diagnostic, faux lecteur) : Scène 1,7 à 2,1 % en moyenne, petite fenêtre 0,2 % ; les mêmes chiffres qu'avant ces travaux, sur la même machine le même jour (1,9 à 2,1 % et 0,25 %). Voir le [README](../README.fr.md) et le [journal des versions](../CHANGELOG.md).
