# Lyra Lyrics 1.3.1

## English

Fixes after the first test on a real Windows PC.

- **Windows: no more silent closing in the Scene.** The app could close a few seconds after opening the full-screen Scene in the middle of a song (at the first line change). The cause was the way the karaoke-style fill was drawn: it is rewritten with two plain text layers (like on the Mac), and the leaving line no longer uses an animated blur and an off-screen mask; it still rises, shrinks a little and fades from left to right. The Scene now writes a short trace of each step to its log file (never titles or lyrics), so any future problem can be located.
- **Windows: karaoke-style fill** now starts exactly at the first letter of the line (it started late on centred lines).
- **Windows: the white colour swatch** in the settings is now visible on a light background.
- **Shortcut (Mac and Windows):** ⌃⌥⌘L / Ctrl+Alt+Shift+L now **turns click-through on and off**; if the window is hidden, it also shows it. Show or hide the window from the menu bar menu (Mac) or the notification-area menu (Windows).

**Download:** `Lyra-Lyrics-1.3.1-macOS.zip` (2,134,875 bytes)

**SHA-256:** `503205f71ad859d6362ae087195e92a17250c5adc134814e61329e78dec7267b`

**Download:** `Lyra-Lyrics-1.3.1-windows-x64-setup.exe` (built by GitHub Actions from the `v1.3.1` tag; its size and SHA-256 are on the release page and in the attached `.sha256` file)

**First launch on the Mac (important).** The app is **not notarised**: move **Lyra Lyrics.app** to Applications, open it, then **System Settings > Privacy & Security > Open Anyway**. The exact wording may differ on your version of macOS.

**First launch on Windows (important).** The installer and the app are **not signed**. Run `Lyra-Lyrics-1.3.1-windows-x64-setup.exe`; if Windows SmartScreen shows "Windows protected your PC" (French: "Windows a protégé votre ordinateur"), click **More info** ("Informations complémentaires"), then **Run anyway** ("Exécuter quand même"). On Windows 11 with Smart App Control turned on, that button may not exist and Windows may refuse the file: this has not been checked on a real PC. To check your download, compare its SHA-256 with the line above (`Get-FileHash <file>` in PowerShell, or `shasum -a 256 <file>` on a Mac). To uninstall: Settings > Apps > Lyra Lyrics (the uninstaller asks whether to delete your settings; the default answer keeps them).

Known limitations: the Windows Scene crash was reproduced by an automatic run of the real Scene on GitHub's Windows runner (karaoke on) and that run passes with this version; it must still be confirmed on a real PC. The new shortcut behaviour was not run in the Mac app before this release (logic covered by tests). Windows stays a beta, Spotify only, with an unsigned installer.

## Français

Corrections après le premier essai sur un vrai PC Windows.

- **Windows : plus de fermeture silencieuse dans la Scène.** L'app pouvait se fermer quelques secondes après l'ouverture de la Scène plein écran en plein morceau (au premier changement de ligne). La cause était la façon de dessiner le remplissage façon karaoké : il est réécrit avec deux simples couches de texte (comme sur Mac), et la ligne qui part n'utilise plus de flou animé ni de masque hors écran ; elle monte toujours un peu, rétrécit et s'efface de gauche à droite. La Scène écrit maintenant une courte trace de chaque étape dans son journal (jamais de titre ni de paroles), pour situer tout problème futur.
- **Windows : le remplissage façon karaoké** part maintenant exactement de la première lettre de la ligne (il démarrait trop tard sur les lignes centrées).
- **Windows : la pastille de couleur blanche** des réglages se voit maintenant sur un fond clair.
- **Raccourci (Mac et Windows) :** ⌃⌥⌘L / Ctrl+Alt+Maj+L **active et coupe le clic-à-travers** ; si la fenêtre est cachée, il la montre aussi. Montrer ou cacher la fenêtre se fait depuis le menu de la barre de menus (Mac) ou de la zone de notification (Windows).

**Téléchargement :** `Lyra-Lyrics-1.3.1-macOS.zip` (2 134 875 octets)

**SHA-256 :** `503205f71ad859d6362ae087195e92a17250c5adc134814e61329e78dec7267b`

**Téléchargement :** `Lyra-Lyrics-1.3.1-windows-x64-setup.exe` (construit par GitHub Actions à partir de l'étiquette `v1.3.1` ; sa taille et son SHA-256 sont sur la page de la release et dans le fichier `.sha256` joint)

**Premier lancement sur Mac (important).** L'app n'est **pas notariée** : glisse **Lyra Lyrics.app** dans Applications, ouvre-la, puis **Réglages Système > Confidentialité et sécurité > Ouvrir quand même**. Le texte exact peut différer selon ta version de macOS.

**Premier lancement sur Windows (important).** L'installateur et l'app ne sont **pas signés**. Lance `Lyra-Lyrics-1.3.1-windows-x64-setup.exe` ; si Windows SmartScreen affiche « Windows a protégé votre ordinateur », clique sur **Informations complémentaires**, puis sur **Exécuter quand même**. Sous Windows 11 avec le Contrôle intelligent des applications activé, ce bouton peut ne pas exister et Windows peut refuser le fichier : non vérifié sur un vrai PC. Pour vérifier ton téléchargement, compare son SHA-256 avec la ligne ci-dessus (`Get-FileHash <fichier>` dans PowerShell, ou `shasum -a 256 <fichier>` sur Mac). Pour désinstaller : Paramètres > Applications > Lyra Lyrics (le désinstallateur demande s'il faut supprimer tes réglages ; la réponse par défaut les conserve).

Limites connues : le plantage de la Scène Windows a été reproduit par un essai automatique de la vraie Scène sur l'exécuteur Windows de GitHub (karaoké allumé), et cet essai passe avec cette version ; il reste à le confirmer sur un vrai PC. Le nouveau raccourci n'a pas été lancé dans l'app Mac avant cette version (règle couverte par des tests). Windows reste une bêta, Spotify seulement, avec un installateur non signé.
