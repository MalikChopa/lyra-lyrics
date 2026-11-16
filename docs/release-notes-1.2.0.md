# Lyra Lyrics 1.2.0

## English

The first **Windows version (beta)**, released together with the Mac version, plus fixes shared by both.

- **Windows (beta).** Windows 10 version 1809 or later and Windows 11, 64-bit. **Spotify only** (the app reads Spotify through the Windows media controls; nothing to authorise). The same small always-on-top window as on the Mac: synchronised lyrics on one, three or five lines, soft scrolling, text that adapts to the window size, three backgrounds, font themes, colours from the album cover, manual offset, playback buttons, click-through mode, a global shortcut (Ctrl+Alt+Shift+L), a notification-area icon, a welcome screen, auto-hide, launch at Windows start, and a way to pick another version of the lyrics when they are wrong. It comes with an **installer** (per user, no administrator rights, Start menu shortcut, uninstaller).
- **Not on Windows yet.** The full-screen **Scene** (planned for 1.3.0), the animated cover background, the karaoke-style fill and Apple Music. The interface is in French only.
- **Update notice on Windows**, like on the Mac: at most one request a day to `api.github.com` (this repository's latest release), nothing sent about you, can be switched off in the settings.
- **Fixes for both apps.** Titles and artists with "feat.", "ft." or "vs." are matched the same way on both; a server asking to wait for a very long time (`Retry-After`) now freezes the app for 5 minutes at most; LRC lyrics lines that are indented are no longer dropped; on the Mac, waiting for the network to come back can now be cancelled. Both apps now run against the same shared test files.
- The Mac features of 1.1.0 (Scene, manual lyrics search, welcome screen, auto-hide...) are unchanged.

**Download:** `Lyra-Lyrics-1.2.0-macOS.zip` (2,134,225 bytes)

**SHA-256:** `1810089ccdf1db9c41bc2660f3144630769f6d5edabe433a89178c2eb3bbd31e`

**Download:** `Lyra-Lyrics-1.2.0-windows-x64-setup.exe` (built by GitHub Actions from the `v1.2.0` tag; its size and SHA-256 are on the release page and in the attached `.sha256` file)

**First launch on the Mac (important).** The app is **not notarised**: move **Lyra Lyrics.app** to Applications, open it, then **System Settings > Privacy & Security > Open Anyway**. The exact wording may differ on your version of macOS.

**First launch on Windows (important).** The installer and the app are **not signed**. Run `Lyra-Lyrics-1.2.0-windows-x64-setup.exe`; if Windows SmartScreen shows "Windows protected your PC" (French: "Windows a protégé votre ordinateur"), click **More info** ("Informations complémentaires"), then **Run anyway** ("Exécuter quand même"). On Windows 11 with Smart App Control turned on, that button may not exist and Windows may refuse the file: this has not been checked on a real PC. To check your download, compare its SHA-256 with the line above (`Get-FileHash <file>` in PowerShell, or `shasum -a 256 <file>` on a Mac). To uninstall: Settings > Apps > Lyra Lyrics (the uninstaller asks whether to delete your settings; the default answer keeps them).

Known limitations: **the Windows version is a beta and had never run on a real PC before this release**: the installer, the window rendering, the Spotify detection, the shortcut, the notification icon and the update check are only verified on the developer's Mac (unit tests, build, shared test files), not on Windows. The installer is built by GitHub Actions and was never tried before this release. No Scene, Spotify only, French interface only, Windows on Arm not verified. The Mac limits of 1.1.0 remain (real Spotify prompt, real covers, a second display and smoothness to the eye are not verified). Lyrics come from LRCLIB and belong to their authors and publishers: they are shown for personal use and never stored or redistributed. See the [README](../README.md) and the [changelog](../CHANGELOG.md).

## Français

La première **version Windows (bêta)**, publiée en même temps que la version Mac, plus des corrections communes aux deux.

- **Windows (bêta).** Windows 10 version 1809 ou plus récent et Windows 11, en 64 bits. **Spotify seulement** (l'app lit Spotify par le contrôle multimédia de Windows ; rien à autoriser). La même petite fenêtre toujours au-dessus que sur Mac : paroles synchronisées sur une, trois ou cinq lignes, défilement doux, texte qui s'adapte à la taille de la fenêtre, trois fonds, thèmes de police, couleurs de la pochette, décalage manuel, boutons de lecture, mode clic-à-travers, raccourci global (Ctrl+Alt+Maj+L), icône dans la zone de notification, écran d'accueil, masquage automatique, lancement au démarrage de Windows, et un moyen de choisir une autre version des paroles quand elles sont fausses. Elle s'installe avec un **installateur** (par utilisateur, sans droits d'administrateur, raccourci du menu Démarrer, désinstallateur).
- **Pas encore sur Windows.** La **Scène** plein écran (prévue en 1.3.0), le fond de pochette animé, le remplissage façon karaoké et Apple Music. L'interface est en français seulement.
- **Avis de nouvelle version sous Windows**, comme sur Mac : une requête par jour au plus vers `api.github.com` (dernière version de ce dépôt), rien de toi n'est envoyé, désactivable dans les réglages.
- **Corrections pour les deux apps.** Les titres et artistes avec « feat. », « ft. » ou « vs. » sont reconnus de la même façon des deux côtés ; un serveur qui demande d'attendre très longtemps (`Retry-After`) ne bloque plus l'app plus de 5 minutes ; les lignes de paroles LRC indentées ne sont plus ignorées ; sur Mac, l'attente du retour du réseau peut maintenant être annulée. Les deux apps sont maintenant testées avec les mêmes fichiers d'essai communs.
- Les fonctions Mac de la 1.1.0 (Scène, recherche manuelle de paroles, écran d'accueil, masquage automatique...) ne changent pas.

**Téléchargement :** `Lyra-Lyrics-1.2.0-macOS.zip` (2 134 225 octets)

**SHA-256 :** `1810089ccdf1db9c41bc2660f3144630769f6d5edabe433a89178c2eb3bbd31e`

**Téléchargement :** `Lyra-Lyrics-1.2.0-windows-x64-setup.exe` (construit par GitHub Actions à partir de l'étiquette `v1.2.0` ; sa taille et son SHA-256 sont sur la page de la release et dans le fichier `.sha256` joint)

**Premier lancement sur Mac (important).** L'app n'est **pas notariée** : glisse **Lyra Lyrics.app** dans Applications, ouvre-la, puis **Réglages Système > Confidentialité et sécurité > Ouvrir quand même**. Le texte exact peut différer selon ta version de macOS.

**Premier lancement sur Windows (important).** L'installateur et l'app ne sont **pas signés**. Lance `Lyra-Lyrics-1.2.0-windows-x64-setup.exe` ; si Windows SmartScreen affiche « Windows a protégé votre ordinateur », clique sur **Informations complémentaires**, puis sur **Exécuter quand même**. Sous Windows 11 avec le Contrôle intelligent des applications activé, ce bouton peut ne pas exister et Windows peut refuser le fichier : non vérifié sur un vrai PC. Pour vérifier ton téléchargement, compare son SHA-256 avec la ligne ci-dessus (`Get-FileHash <fichier>` dans PowerShell, ou `shasum -a 256 <fichier>` sur Mac). Pour désinstaller : Paramètres > Applications > Lyra Lyrics (le désinstallateur demande s'il faut supprimer tes réglages ; la réponse par défaut les conserve).

Limites connues : **la version Windows est une bêta et n'avait jamais tourné sur un vrai PC avant cette release** : l'installateur, l'affichage de la fenêtre, la détection de Spotify, le raccourci, l'icône de notification et la vérification de mise à jour ne sont vérifiés que sur le Mac du développeur (tests unitaires, compilation, fichiers d'essai communs), pas sous Windows. L'installateur est construit par GitHub Actions et n'avait jamais été essayé avant cette release. Pas de Scène, Spotify seulement, interface en français seulement, Windows sur Arm non vérifié. Les limites Mac de la 1.1.0 restent (vraie invite Spotify, vraies pochettes, second écran et fluidité à l'œil non vérifiés). Les paroles viennent de LRCLIB et appartiennent à leurs auteurs et éditeurs : elles sont affichées pour un usage personnel, jamais stockées ni redistribuées. Voir le [README](../README.fr.md) et le [journal des versions](../CHANGELOG.md).
